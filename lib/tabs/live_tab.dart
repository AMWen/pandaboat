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

  double currentSpeed = 0.0;
  double smoothedSpeed = 0.0;
  int strokeCount = 0;
  int spm = 0;
  double? latitude;
  double? longitude;
  String elapsedTime = '—';

  bool isRecording = false;
  DateTime? recordingStartTime;
  String? currentLogId;

  final List<Map<String, dynamic>> recentData = [];
  final List<Map<String, dynamic>> gpsBuffer = [];

  double totalDistance = 0.0;
  DateTime? lastJolt;
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
    spmTimer = Timer.periodic(const Duration(seconds: 5), (_) => calculateSPM());
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
      if (gpsBuffer.isNotEmpty) {
        final lastPosition = gpsBuffer.last;
        distance = Geolocator.distanceBetween(
          lastPosition['lat'],
          lastPosition['lon'],
          position.latitude,
          position.longitude,
        );
      }

      // Update total distance
      totalDistance += distance;

      gpsBuffer.add({
        't': elapsedMs,
        'speed': speed,
        'lat': position.latitude,
        'lon': position.longitude,
        'distance': totalDistance,
        'spm': spm
      });
    }

    recentData.add({'timestamp': now, 'speed': speed});
    recentData.removeWhere((entry) => now.difference(entry['timestamp']).inSeconds > 3);

    if (recentData.length >= 2) {
      final prev = recentData[recentData.length - 2];
      double delta = speed - prev['speed'];
      if (delta.abs() > 0.8 && now.difference(lastJolt ?? DateTime(2000)).inMilliseconds > 800) {
        strokeCount++;
        lastJolt = now;
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
    final now = DateTime.now();
    final strokesLastMinute =
        recentData.where((entry) => now.difference(entry['timestamp']).inSeconds <= 60).length;
    setState(() {
      spm = (strokeCount * 60) ~/ 60;
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // <-- this is required for AutomaticKeepAliveClientMixin

    return Scaffold(
      appBar: AppBar(title: const Text("Live Metrics")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            metric("Latitude", latitude?.toStringAsFixed(6) ?? '—'),
            metric("Longitude", longitude?.toStringAsFixed(6) ?? '—'),
            metric("Instantaneous Speed", "${currentSpeed.toStringAsFixed(1)} km/hr"),
            metric("Smoothed Speed (3s)", "${smoothedSpeed.toStringAsFixed(1)} km/hr"),
            metric("Strokes per Minute", "$spm spm"),
            metric("Elapsed Time", elapsedTime),
            metric("Total Distance", "${totalDistance.toStringAsFixed(0)} meters"),
            SizedBox(height: 50),
            FilledButton(
              onPressed: toggleRecording,
              style: FilledButton.styleFrom(
                backgroundColor: isRecording ? Colors.red : primaryColor,
              ),
              child: Text(
                isRecording ? 'Stop Recording' : 'Start Recording',
                style: TextStyle(color: secondaryColor),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget metric(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w500)), Text(value)],
      ),
    );
  }
}
