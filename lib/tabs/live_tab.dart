import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:pandaboat/data/constants.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/gps_data.dart';
import '../data/services/location_logger.dart';
import '../utils/time_format.dart';

class LiveTab extends StatefulWidget {
  final ValueChanged<bool> onRecordingChanged;
  final ValueChanged<String?> onLogIdChanged;

  const LiveTab({super.key, required this.onRecordingChanged, required this.onLogIdChanged});

  @override
  LiveTabState createState() => LiveTabState();
}

class LiveTabState extends State<LiveTab> with AutomaticKeepAliveClientMixin {
  // ----------------------
  // Orientation
  // ----------------------
  bool useFlatOrientation = true;
  bool isForward = true;

  // ----------------------
  // Settings / Thresholds
  // ----------------------
  double baseThreshold = defaultBaseThreshold;
  double maxSPM = defaultMaxSPM;
  late double minIntervalMs;
  double maxSpeed = defaultMaxSpeed;
  double maxDistance = defaultMaxDistance;
  static const int minUpdateInterval = 200; // ms

  // ----------------------
  // Speed / Stroke Tracking
  // ----------------------
  double currentSpeed = 0.0;
  double smoothedSpeed = 0.0;
  List<DateTime> strokes = [];
  int strokeCount = 0;
  double spm = 0;

  // ----------------------
  // GPS and Location Data
  // ----------------------
  double? latitude;
  double? longitude;
  double totalDistance = 0.0;
  Map<String, dynamic>? lastProcessedPosition;
  final List<Map<String, dynamic>> recentData = [];
  final List<Map<String, dynamic>> recentCalculatedData = [];
  final List<Map<String, dynamic>> gpsBuffer = [];

  // ----------------------
  // UI / Recording State
  // ----------------------
  bool isRecording = false;
  DateTime? recordingStartTime;
  String elapsedTime = '—';
  bool outlier = false;
  String? currentLogId;

  // ----------------------
  // Timers
  // ----------------------
  Timer? spmTimer;
  Timer? uiUpdateTimer;
  Timer? gpsFlushTimer;

  // ----------------------
  // Accelerometer / Stroke Detection
  // ----------------------
  late StreamSubscription<UserAccelerometerEvent> accelSubscription;
  static const int bufferSize = 10; // 0.67 seconds
  List<Map<String, double>> completeAccelBuffer = [];
  List<double> forwardAccelBuffer = [];
  double lastPeakTime = 0;

  // ----------------------
  // Logger
  // ----------------------
  final logger = LocationLogger();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initLocation();

    accelSubscription = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(onAccelerometerEvent);
    uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateUI());
    spmTimer = Timer.periodic(const Duration(seconds: 1), (_) => calculateSPM());
    gpsFlushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isRecording && gpsBuffer.isNotEmpty) {
        flushGPSData();
      }
    });
    minIntervalMs = calcMinIntervalMs(maxSPM);
  }

  double calcMinIntervalMs(spm) {
    return (1 / spm * 1000 * 60); // min -> sec -> ms
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      baseThreshold = prefs.getDouble('baseThreshold') ?? defaultBaseThreshold;
      maxSPM = prefs.getDouble('maxSPM') ?? defaultMaxSPM;
      maxSpeed = prefs.getDouble('maxSpeed') ?? defaultMaxSpeed;
      maxDistance = prefs.getDouble('maxDistance') ?? defaultMaxDistance;
      minIntervalMs = calcMinIntervalMs(maxSPM);
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('baseThreshold', baseThreshold);
    await prefs.setDouble('maxSPM', maxSPM);
    await prefs.setDouble('maxSpeed', maxSpeed);
    await prefs.setDouble('maxDistance', maxDistance);
  }

  Future<void> _initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    // Needed to request background location
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        intervalDuration: const Duration(milliseconds: minUpdateInterval),
        // Below does not work due to new Android settings
        // forceLocationManager: true,
        // foregroundNotificationConfig: const ForegroundNotificationConfig(
        //   notificationText: "Tracking continues in the background.",
        //   notificationTitle: "Tracking in Background",
        //   enableWakeLock: true,
        // ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = LocationSettings(accuracy: LocationAccuracy.best);
    }

    Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).debounceTime(const Duration(milliseconds: minUpdateInterval)).listen(onPosition);
  }

  void onPosition(Position position) {
    final now = DateTime.now();
    final speed = position.speed * 3.6;

    if (isRecording && recordingStartTime != null) {
      final elapsedMs = now.difference(recordingStartTime!).inMilliseconds;
      processPosition(position, now, elapsedMs, speed);
    }

    // Maintain recent data
    recentData.add({
      'timestamp': now,
      'speed': speed,
      'lat': position.latitude,
      'lon': position.longitude,
    });
    recentData.removeWhere((entry) => now.difference(entry['timestamp']).inSeconds > 4);
  }

  void processPosition(Position position, DateTime now, int elapsedMs, double speed) {
    double distance = 0.0;
    double calculatedSpeed = 0.0;

    if (lastProcessedPosition != null) {
      final last = lastProcessedPosition;
      final timeDelta = elapsedMs - last!['t'];
      if (timeDelta <= 0) return;

      distance = Geolocator.distanceBetween(
        last['lat'],
        last['lon'],
        position.latitude,
        position.longitude,
      );

      calculatedSpeed = distance * 1000 / timeDelta * 3.6;
    }

    outlier = speed > maxSpeed || distance > maxDistance || calculatedSpeed > maxSpeed;
    lastProcessedPosition = {'t': elapsedMs, 'lat': position.latitude, 'lon': position.longitude};
    totalDistance += distance;

    if (!outlier) {
      recentCalculatedData.add({'timestamp': now, 'speed': calculatedSpeed});
    }
    recentCalculatedData.removeWhere((entry) => now.difference(entry['timestamp']).inSeconds > 4);
    final smoothedCalculated =
        recentCalculatedData.isEmpty
            ? 0.0
            : recentCalculatedData.map((e) => e['speed']).reduce((a, b) => a + b) /
                recentCalculatedData.length;

    final gpsEntry = GpsData(
      t: elapsedMs,
      speed: speed,
      calculatedSpeed: calculatedSpeed,
      smoothedCalculated: smoothedCalculated,
      smoothed: smoothedSpeed,
      lat: position.latitude,
      lon: position.longitude,
      distance: totalDistance,
      spm: spm,
      outlier: outlier,
    );
    gpsBuffer.add(gpsEntry.toJson());
  }

  void onAccelerometerEvent(UserAccelerometerEvent event) {
    final now = DateTime.now();
    final t = now.millisecondsSinceEpoch.toDouble();

    // Can be facing forward or backwards, held in hand or lying flat
    double y = event.y;
    double z = event.z;

    if (!isForward) {
      y *= -1;
      z *= -1;
    }

    double forwardAccel =
        useFlatOrientation
            ? (max(y, 0) > baseThreshold ? max(y, 0) : 0)
            : (max(-z, 0) > baseThreshold ? max(-z, 0) : 0);

    // Maintain a moving buffer
    completeAccelBuffer.add({'t': t, 'x': event.x, 'y': event.y, 'z': event.z});
    forwardAccelBuffer.add(forwardAccel);
    if (forwardAccelBuffer.length > bufferSize) {
      forwardAccelBuffer.removeAt(0);
    }

    if (forwardAccelBuffer.length < 3) return;

    // Peak detection logic
    int last = forwardAccelBuffer.length - 1;
    double a = forwardAccelBuffer[last - 2];
    double b = forwardAccelBuffer[last - 1];
    double c = forwardAccelBuffer[last];

    // Peak (simple local maximum)
    if (b > a && b > c) {
      double timeSinceLastPeak = t - lastPeakTime;

      if (timeSinceLastPeak > minIntervalMs) {
        setState(() {
          strokes.add(now);
          strokeCount++;
        });
        lastPeakTime = t;
      }
    }
  }

  void updateUI() {
    setState(() {
      elapsedTime = getElapsedTime();
    });

    if (recentData.isEmpty) return;

    final latest = recentData.last;
    final smooth =
        recentData.isEmpty
            ? 0.0
            : recentData.map((e) => e['speed']).reduce((a, b) => a + b) / recentData.length;

    setState(() {
      currentSpeed = latest['speed'];
      smoothedSpeed = smooth;
      latitude = latest['lat'];
      longitude = latest['lon'];
    });

    if (gpsBuffer.length > 1000) gpsBuffer.clear();
  }

  void calculateSPM() {
    Duration window = Duration(seconds: 3); // SPM is averaged over past 3 seconds
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    strokes.retainWhere((s) => s.isAfter(cutoff));
    setState(() {
      strokes = strokes;
    });

    if (strokes.length < 2) {
      setState(() {
        spm = 0;
      });
      return;
    }

    final duration = strokes.last.difference(strokes.first).inMilliseconds / 1000.0;

    setState(() {
      spm =
          duration == 0
              ? 0
              : ((strokes.length - 1) / duration * 60 * 2).round() / 2; // round to nearest 0.5
    });
  }

  void flushGPSData() {
    logger.appendToLog(currentLogId!, gpsBuffer);
    gpsBuffer.clear();
  }

  void toggleRecording() {
    setState(() {
      isRecording = !isRecording;
    });
    widget.onRecordingChanged(isRecording);

    if (isRecording) {
      completeAccelBuffer = [];
      totalDistance = 0;
      strokeCount = 0;
      lastProcessedPosition = null;
      recordingStartTime = DateTime.now();
      currentLogId = recordingStartTime!.toIso8601String();
      widget.onLogIdChanged(currentLogId);
    } else {
      flushGPSData();
      logger.saveAccel(currentLogId!, completeAccelBuffer);
      logger.saveLog(currentLogId!);
      recordingStartTime = null;
      currentLogId = null;
      widget.onLogIdChanged(null);
    }
  }

  String getElapsedTime() {
    if (!isRecording || recordingStartTime == null) return '-';

    final elapsed = DateTime.now().difference(recordingStartTime!);
    return formatTime(elapsed);
  }

  @override
  void dispose() {
    spmTimer?.cancel();
    spmTimer?.cancel();
    uiUpdateTimer?.cancel();
    gpsFlushTimer?.cancel();
    accelSubscription.cancel();
    super.dispose();
  }

  void showSettingsDialog() {
    final baseThresholdController = TextEditingController(text: baseThreshold.toString());
    final maxSPMController = TextEditingController(text: maxSPM.toString());
    final maxSpeedController = TextEditingController(text: maxSpeed.toString());
    final maxDistanceController = TextEditingController(text: maxDistance.toString());

    Widget settingsTextInput(TextEditingController controller, String labelText) {
      return TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: labelText,
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryColor, width: 2)),
          border: InputBorder.none,
        ),
      );
    }

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Settings', style: TextStyles.dialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                settingsTextInput(baseThresholdController, 'Base Threshold (for Stroke Count)'),
                settingsTextInput(maxSPMController, 'Max SPM'),
                settingsTextInput(maxSpeedController, 'Max Speed (km/hr)'),
                settingsTextInput(maxDistanceController, 'Max Distance (m)'),
              ],
            ),
            actionsOverflowButtonSpacing: 0,
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                      setState(() {
                        baseThreshold =
                            double.tryParse(baseThresholdController.text) ?? defaultBaseThreshold;
                        maxSPM = double.tryParse(maxSPMController.text) ?? defaultMaxSPM;
                        minIntervalMs = calcMinIntervalMs(maxSPM);
                        maxSpeed = double.tryParse(maxSpeedController.text) ?? defaultMaxSpeed;
                        maxDistance =
                            double.tryParse(maxDistanceController.text) ?? defaultMaxDistance;
                      });
                      await _saveSettings();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  baseThresholdController.text = defaultBaseThreshold.toString();
                  maxSPMController.text = defaultMaxSPM.toString();
                  maxSpeedController.text = defaultMaxSpeed.toString();
                  maxDistanceController.text = defaultMaxDistance.toString();
                },
                child: const Text('Reset to Defaults'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // <-- this is required for AutomaticKeepAliveClientMixin

    final metrics = [
      metric("Strokes per Minute", "$spm"),
      metric("Elapsed Time", elapsedTime),
      metric("Total Distance (m)", totalDistance.toStringAsFixed(0)),
      metric("Instant. Speed (kph)", currentSpeed.toStringAsFixed(1)),
      metric("Stroke count", "$strokeCount"),
      metric("Avg Speed (3s) (kph)", smoothedSpeed.toStringAsFixed(1)),
      metric("Latitude", latitude?.toStringAsFixed(2) ?? '—'),
      metric("Longitude", longitude?.toStringAsFixed(2) ?? '—'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Metrics"),
        actions: [
          IgnorePointer(
            ignoring: isRecording, // disables interaction during recording
            child: IconButton(
              icon: Icon(useFlatOrientation ? Icons.stay_current_portrait : Icons.screen_rotation),
              tooltip: useFlatOrientation ? 'Currently: Flat Mode' : 'Currently:  Hand-Held Mode',
              onPressed: () {
                setState(() {
                  useFlatOrientation = !useFlatOrientation;
                });
              },
            ),
          ),
          IgnorePointer(
            ignoring: isRecording,
            child: IconButton(
              icon: Icon(isForward ? Icons.arrow_upward : Icons.arrow_downward),
              tooltip: isForward ? 'Direction: Forward' : 'Direction: Backward',
              onPressed: () {
                setState(() {
                  isForward = !isForward;
                });
              },
            ),
          ),
          IgnorePointer(
            ignoring: isRecording, // disables interaction during recording
            child: IconButton(
              icon: const Icon(Icons.settings),
              onPressed: showSettingsDialog,
              tooltip: 'Settings',
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 3 / 2.1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(), // let outer scroll handle it
              children: metrics,
            ),
            const SizedBox(height: 50),
            Center(
              child: FilledButton(
                onPressed: toggleRecording,
                style: FilledButton.styleFrom(
                  backgroundColor: isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                ),
                child: Icon(
                  isRecording ? Icons.stop : Icons.fiber_manual_record,
                  color: isRecording ? Theme.of(context).colorScheme.surface : Colors.red,
                  size: isRecording ? 32 : 24,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget metric(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dullColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: TextStyles.mediumText, textAlign: TextAlign.center),
          Text(value, style: TextStyles.largeMediumText, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
