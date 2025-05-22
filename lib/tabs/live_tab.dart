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
import 'package:shake/shake.dart';
import '../data/models/gps_data.dart';
import '../data/services/location_logger.dart';
import '../utils/time_format.dart';

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  LiveTabState createState() => LiveTabState();
}

class LiveTabState extends State<LiveTab> with AutomaticKeepAliveClientMixin {
  // ----------------------
  // Settings / Thresholds
  // ----------------------
  double shakeThresholdGravity = defaultShakeThresholdGravity;
  double baseThreshold = defaultBaseThreshold;
  double stdDevMult = defaultStdDevMult;
  double maxSPM = defaultMaxSPM;
  double maxSpeed = defaultMaxSpeed;
  double maxDistance = defaultMaxDistance;

  // ----------------------
  // Speed / Stroke Tracking
  // ----------------------
  double currentSpeed = 0.0;
  double smoothedSpeed = 0.0;
  List<DateTime> strokes = [];
  int strokeCount = 0;
  double spm = 0;
  List<DateTime> strokes2 = [];
  int strokeCount2 = 0;
  double spm2 = 0;

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
  Timer? spmTimer2;
  Timer? uiUpdateTimer;
  Timer? gpsFlushTimer;

  // ----------------------
  // Shake / Accelerometer / Stroke Detection
  // ----------------------
  ShakeDetector? shakeDetector;
  late StreamSubscription<AccelerometerEvent> accelSubscription;
  static const int bufferSize = 50;
  List<double> forwardAccelBuffer = [];
  double lastPeakTime = 0;
  late
  // ----------------------
  // Logger
  // ----------------------
  final logger = LocationLogger();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initLocation();

    accelSubscription = accelerometerEventStream().listen(onAccelerometerEvent);
    shakeDetector = _initShakeDetector(shakeThresholdGravity);
    uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateUI());
    spmTimer = Timer.periodic(const Duration(seconds: 1), (_) => calculateSPM());
    spmTimer2 = Timer.periodic(const Duration(seconds: 1), (_) => calculateSPM2());
    gpsFlushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isRecording && gpsBuffer.isNotEmpty) {
        flushGPSData();
      }
    });
  }

  double calcMinIntervalMs(spm) {
    return (1 / spm * 1000 * 60); // min -> sec -> ms
  }

  ShakeDetector _initShakeDetector(double threshold) {
    return ShakeDetector.autoStart(
      onPhoneShake: (event) {
        final now = DateTime.now();
        if (strokes.isEmpty ||
            now.difference(strokes.last).inMilliseconds > calcMinIntervalMs(maxSPM)) {
          strokes.add(now);
          strokeCount++;
        }
      },
      shakeThresholdGravity: threshold,
      useFilter: false,
    );
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
        intervalDuration: const Duration(milliseconds: 200),
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
    ).debounceTime(const Duration(milliseconds: 200)).listen(onPosition);
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
      spm2: spm2,
      outlier: outlier,
    );
    gpsBuffer.add(gpsEntry.toJson());
  }

  void onAccelerometerEvent(AccelerometerEvent event) {
    final now = DateTime.now();
    final t = now.millisecondsSinceEpoch.toDouble();

    double forwardAccel = event.y;

    // Maintain a moving buffer
    forwardAccelBuffer.add(forwardAccel);
    if (forwardAccelBuffer.length > bufferSize) {
      forwardAccelBuffer.removeAt(0);
    }

    // Apply a simple moving average for smoothing
    List<double> smoothed = _movingAverage(forwardAccelBuffer, windowSize: 5);
    if (smoothed.length < 3) return;

    // Peak detection logic
    int last = smoothed.length - 1;
    double a = smoothed[last - 2];
    double b = smoothed[last - 1];
    double c = smoothed[last];

    // Peak (simple local maximum)
    if (b > a && b > c) {
      double timeSinceLastPeak = t - lastPeakTime;
      double dynamicThreshold = _dynamicThreshold(smoothed);

      if (b > dynamicThreshold && timeSinceLastPeak > calcMinIntervalMs(maxSPM)) {
        setState(() {
          strokes2.add(now);
          strokeCount2++;
        });
        lastPeakTime = t;
      }
    }
  }

  List<double> _movingAverage(List<double> data, {int windowSize = 5}) {
    List<double> result = [];
    for (int i = 0; i < data.length; i++) {
      int start = max(0, i - windowSize + 1);
      double avg = data.sublist(start, i + 1).reduce((a, b) => a + b) / (i - start + 1);
      result.add(avg);
    }
    return result;
  }

  double _dynamicThreshold(List<double> data) {
    double avg = data.reduce((a, b) => a + b) / data.length;
    double stddev = sqrt(data.map((d) => pow(d - avg, 2)).reduce((a, b) => a + b) / data.length);
    return avg + stddev * stdDevMult + baseThreshold;
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
    Duration window = Duration(seconds: 5); // SPM is averaged over past 5 seconds
    final now = strokes.isNotEmpty ? strokes.last : DateTime.now();
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

  void calculateSPM2() {
    Duration window = Duration(seconds: 5); // SPM is averaged over past 5 seconds
    final now = strokes2.isNotEmpty ? strokes2.last : DateTime.now();
    final cutoff = now.subtract(window);
    strokes2.retainWhere((s) => s.isAfter(cutoff));
    setState(() {
      strokes2 = strokes2;
    });

    if (strokes2.length < 2) {
      setState(() {
        spm2 = 0;
      });
      return;
    }

    final duration = strokes2.last.difference(strokes2.first).inMilliseconds / 1000.0;

    setState(() {
      spm2 =
          duration == 0
              ? 0
              : ((strokes2.length - 1) / duration * 60 * 2).round() / 2; // round to nearest 0.5
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

    if (isRecording) {
      totalDistance = 0;
      strokeCount = 0;
      strokeCount2 = 0;
      lastProcessedPosition = null;
      recordingStartTime = DateTime.now();
      currentLogId = recordingStartTime!.toIso8601String();
      logger.startNewLog(currentLogId!);
    } else {
      flushGPSData();
      logger.saveLog(currentLogId!);
      recordingStartTime = null;
      currentLogId = null;
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
    spmTimer2?.cancel();
    uiUpdateTimer?.cancel();
    gpsFlushTimer?.cancel();
    shakeDetector?.stopListening();
    accelSubscription.cancel();
    super.dispose();
  }

  void showSettingsDialog() {
    final thresholdController = TextEditingController(text: shakeThresholdGravity.toString());
    final baseThresholdController = TextEditingController(text: baseThreshold.toString());
    final stdDevMultController = TextEditingController(text: stdDevMult.toString());
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
          (context) => AlertDialog(
            title: const Text('Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                settingsTextInput(
                  thresholdController,
                  'Shake Threshold Gravity (for Stroke Count)',
                ),
                settingsTextInput(
                  baseThresholdController,
                  'Base Threshold (for Accel Stroke Count)',
                ),
                settingsTextInput(stdDevMultController, 'Std Dev Mutliplier (for Accel)'),
                settingsTextInput(maxSPMController, 'Max SPM'),
                settingsTextInput(maxSpeedController, 'Max Speed (km/hr)'),
                settingsTextInput(maxDistanceController, 'Max Distance (m)'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    shakeThresholdGravity =
                        double.tryParse(thresholdController.text) ?? defaultShakeThresholdGravity;
                    baseThreshold =
                        double.tryParse(baseThresholdController.text) ?? defaultBaseThreshold;
                    stdDevMult = double.tryParse(stdDevMultController.text) ?? defaultStdDevMult;
                    maxSPM = double.tryParse(maxSPMController.text) ?? defaultMaxSPM;
                    maxSpeed = double.tryParse(maxSpeedController.text) ?? defaultMaxSpeed;
                    maxDistance = double.tryParse(maxDistanceController.text) ?? defaultMaxDistance;

                    // Recreate the ShakeDetector with the new threshold
                    shakeDetector?.stopListening();
                    shakeDetector = _initShakeDetector(shakeThresholdGravity);
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save'),
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
      metric("Stroke count gyro", "$strokeCount2"),
      metric("Strokes per Minute2", "$spm2"),
      metric("Latitude", latitude?.toStringAsFixed(2) ?? '—'),
      metric("Longitude", longitude?.toStringAsFixed(2) ?? '—'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Metrics"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: showSettingsDialog,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 3 / 2.1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: metrics,
            ),
            SizedBox(height: 50),
            FilledButton(
              onPressed: toggleRecording,
              style: FilledButton.styleFrom(
                backgroundColor: isRecording ? Colors.red : primaryColor,
              ),
              child: Text(
                isRecording ? 'Stop Recording' : 'Start Recording',
                style: TextStyles.buttonText,
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
