import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pandaboat/data/constants.dart';
import 'package:rxdart/rxdart.dart';
import '../data/services/location_logger.dart';

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  LiveTabState createState() => LiveTabState();
}

class LiveTabState extends State<LiveTab> {
  final logger = LocationLogger();

  double currentSpeed = 0.0;
  double smoothedSpeed = 0.0;
  int strokeCount = 0;
  int spm = 0;
  double? latitude;
  double? longitude;

  bool isRecording = false;
  DateTime? recordingStartTime;
  String? currentLogId;

  final List<Map<String, dynamic>> recentData = [];
  final List<Map<String, dynamic>> gpsBuffer = [];

  DateTime? lastJolt;
  Timer? spmTimer;
  Timer? uiUpdateTimer;

  @override
  void initState() {
    super.initState();
    _initLocation();

    uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateUI());
    spmTimer = Timer.periodic(const Duration(seconds: 5), (_) => calculateSPM());
  }

  Future<void> _initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }
    }

    Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
    ).debounceTime(const Duration(milliseconds: 100)).listen(onPosition);
  }

  void onPosition(Position position) {
    final now = DateTime.now();
    final speed = position.speed * 3.6;

    if (isRecording && recordingStartTime != null) {
      final elapsedMs = now.difference(recordingStartTime!).inMilliseconds;
      logger.appendToLog(currentLogId!, {
        't': elapsedMs,
        'lat': position.latitude,
        'lon': position.longitude,
        'speed': speed,
      });
    }

    gpsBuffer.add({
      'timestamp': now,
      'speed': speed,
      'lat': position.latitude,
      'lon': position.longitude,
    });

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
    if (gpsBuffer.isEmpty) return;

    final latest = gpsBuffer.last;
    final smooth =
        recentData.isEmpty ? 0.0 : recentData.map((e) => e['speed']).reduce((a, b) => a + b) / recentData.length;

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
    final strokesLastMinute = recentData.where((entry) => now.difference(entry['timestamp']).inSeconds <= 60).length;
    setState(() {
      spm = (strokeCount * 60) ~/ 60;
    });
  }

  void toggleRecording() {
    setState(() {
      isRecording = !isRecording;
    });

    if (isRecording) {
      recordingStartTime = DateTime.now();
      currentLogId = recordingStartTime!.toIso8601String();
      logger.startNewLog(currentLogId!);
    } else {
      recordingStartTime = null;
      currentLogId = null;
    }
  }

  @override
  void dispose() {
    spmTimer?.cancel();
    uiUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            SizedBox(height: 50),
            FilledButton(
              onPressed: toggleRecording,
              style: FilledButton.styleFrom(
                backgroundColor: isRecording ? Colors.red : primaryColor,
              ),
              child: Text(isRecording ? 'Stop Recording' : 'Start Recording', style: TextStyle(color: secondaryColor)),
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
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
