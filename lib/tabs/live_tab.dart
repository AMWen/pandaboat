import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:pandaboat/data/constants.dart';
import 'package:rxdart/rxdart.dart';
import '../data/services/location_logger.dart';
import '../utils/time_format.dart';

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  LiveTabState createState() => LiveTabState();
}

class LiveTabState extends State<LiveTab> with AutomaticKeepAliveClientMixin {
  final logger = LocationLogger();
  double minSpeedChange = 0.3;
  double maxSpeed = 16;

  double currentSpeed = 0.0;
  double smoothedSpeed = 0.0;
  List<DateTime> strokes = [];
  int strokeCount = 0;
  double spm = 0;
  double? latitude;
  double? longitude;
  String elapsedTime = '—';

  bool isRecording = false;
  DateTime? recordingStartTime;
  String? currentLogId;

  final List<Map<String, dynamic>> recentData = [];
  final List<Map<String, dynamic>> gpsBuffer = [];

  double totalDistance = 0.0;
  Timer? spmTimer;
  Timer? uiUpdateTimer;
  Timer? gpsFlushTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initLocation();

    uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateUI());
    spmTimer = Timer.periodic(const Duration(seconds: 1), (_) => calculateSPM());
    gpsFlushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isRecording && gpsBuffer.isNotEmpty) {
        flushGPSData();
      }
    });
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

      // Calculate the distance traveled from the previous position to the current position
      double distance = 0.0;
      double calculatedSpeed = 0.0;
      if (gpsBuffer.isNotEmpty) {
        final lastPosition = gpsBuffer.last;
        distance = Geolocator.distanceBetween(
          lastPosition['lat'],
          lastPosition['lon'],
          position.latitude,
          position.longitude,
        );
        calculatedSpeed = distance * 1000 / (elapsedMs - lastPosition['t']) * 3.6;
      }

      // Skip storing data if due to GPS drift
      if (speed > maxSpeed) return;

      // Update total distance
      totalDistance += distance;

      gpsBuffer.add({
        't': elapsedMs,
        'calculatedSpeed': calculatedSpeed,
        'speed': speed,
        'smoothed': smoothedSpeed,
        'lat': position.latitude,
        'lon': position.longitude,
        'distance': totalDistance,
        'spm': spm,
      });
    }

    recentData.add({'timestamp': now, 'speed': speed});
    recentData.removeWhere((entry) => now.difference(entry['timestamp']).inSeconds > 3);
    final lastJolt = strokes.isNotEmpty ? strokes.last : null;

    if (recentData.length >= 3) {
      final thirdToLast = recentData[recentData.length - 3];
      final secondToLast = recentData[recentData.length - 2];

      double previousSpeedChange = secondToLast['speed'] - thirdToLast['speed'];
      double currentSpeedChange = speed - secondToLast['speed'];

      if (currentSpeedChange > previousSpeedChange &&
          currentSpeedChange > minSpeedChange &&
          now.difference(lastJolt ?? DateTime(2000)).inMilliseconds > 500) {
        strokeCount++;
        strokes.add(now);
      }
    }
  }

  void updateUI() {
    setState(() {
      elapsedTime = getElapsedTime();
    });

    if (gpsBuffer.isEmpty) return;

    final latest = gpsBuffer.last;
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
    Duration window = Duration(seconds: 5);
    final now = strokes.isNotEmpty ? strokes.last : DateTime.now();
    final cutoff = now.subtract(window);
    strokes.retainWhere((s) => s.isAfter(cutoff));
    if (strokes.length < 2) return;

    final duration = strokes.last.difference(strokes.first).inMilliseconds / 1000.0;
    if (duration == 0) return;

    setState(() {
      spm = ((strokes.length - 1) / duration * 60 * 2).round() / 2; // round to nearest 0.5
      strokes = strokes;
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
    uiUpdateTimer?.cancel();
    super.dispose();
  }

  void showSettingsDialog() {
    final minSpeedController = TextEditingController(text: minSpeedChange.toString());
    final maxSpeedController = TextEditingController(text: maxSpeed.toString());

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: minSpeedController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Min Speed Change per Stroke',
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    border: InputBorder.none,
                  ),
                ),
                TextField(
                  controller: maxSpeedController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Max Speed',
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    minSpeedChange = double.tryParse(minSpeedController.text) ?? 0.3;
                    maxSpeed = double.tryParse(maxSpeedController.text) ?? 16;
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
      metric("Total Distance (m)", "${totalDistance.toStringAsFixed(0)}"),
      metric("Instant. Speed (kph)", "${currentSpeed.toStringAsFixed(1)}"),
      metric("Stroke count", "$strokeCount"),
      metric("Avg Speed (3s) (kph)", "${smoothedSpeed.toStringAsFixed(1)}"),
      metric("Latitude", latitude?.toStringAsFixed(6) ?? '—'),
      metric("Longitude", longitude?.toStringAsFixed(6) ?? '—'),
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
              childAspectRatio: 3 / 2,
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

  // Updated metric widget for grid item
  Widget metric(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dullColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: TextStyles.mediumText),
          const SizedBox(height: 6),
          Text(value, style: TextStyles.largeMediumText),
        ],
      ),
    );
  }
}
