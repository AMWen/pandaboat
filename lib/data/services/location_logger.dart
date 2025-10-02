import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/gps_data.dart';
import '../constants.dart';

class LocationLogger {
  final Map<String, List<Map<String, dynamic>>> _logs = {};
  final Box<String> _logBox = Hive.box(logPrefix);
  final Box<String> _nameBox = Hive.box(namePrefix);
  final Box<String> _accelBox = Hive.box(accelPrefix);

  void startNewLog(String logId) {
    _logs[logId] = [];
  }

  Future<void> appendToLog(String logId, dynamic data) async {
    if (!_logs.containsKey(logId)) {
      startNewLog(logId);
    }

    if (data is Map<String, dynamic>) {
      _logs[logId]!.add(data); // single value
    } else if (data is List<Map<String, dynamic>>) {
      _logs[logId]!.addAll(data); // list of values
    } else {
      throw ArgumentError('Data must be a Map or List of Maps');
    }
    saveLog(logId);
  }

  Future<void> saveLog(String logId) async {
    final logData = _logs[logId];
    if (logData != null) {
      await _logBox.put(logId, jsonEncode(logData));
    }
  }

  Future<void> saveAccel(String logId, List<Map<String, double>> accelBuffer) async {
    if (accelBuffer.isNotEmpty) {
      await _accelBox.put(logId, jsonEncode(accelBuffer));
    }
  }

  Future<List<dynamic>> loadAccel(String logId) async {
    final raw = _accelBox.get(logId);
    if (raw == null) return [];
    return jsonDecode(raw) as List<dynamic>;
  }

  Future<Map<String, dynamic>> loadLog(String logId) async {
    final raw = _logBox.get(logId);
    if (raw == null) return {};
    final data = jsonDecode(raw);
    if (data == null) return {};
    final decoded = (data as List).cast<Map<String, dynamic>>();
    final smoothedLogs = applySlidingSmoothing(decoded, windowSize: 5);
    final gpsData = smoothedLogs.map((e) => GpsData.fromJson(e)).toList();
    final logName = _nameBox.get(logId);
    return {FieldNames.name: logName, FieldNames.entries: gpsData};
  }

  List<Map<String, dynamic>> applySlidingSmoothing(
    List<Map<String, dynamic>> logData, {
    int windowSize = 3,
  }) {
    if (windowSize % 2 == 0) {
      windowSize = windowSize + 1; // force windowSize to be odd
    }

    final int halfWindow = windowSize ~/ 2;

    return List.generate(logData.length, (i) {
      double sum = 0;
      double sumSpm = 0;
      int count = 0;

      for (int offset = -halfWindow; offset <= halfWindow; offset++) {
        final idx = (i + offset).clamp(0, logData.length - 1);
        sum += logData[idx]['smoothed'] as double;
        sumSpm += logData[idx]['spm'] as double;
        count++;
      }

      final avg = sum / count;
      final avgSpm = sumSpm / count;

      return {...logData[i], 'smoothed': avg, 'spm': avgSpm};
    });
  }

  Future<Map<String, Map<String, dynamic>>> loadAllLogs() async {
    final logs = <String, Map<String, dynamic>>{};
    for (final key in _logBox.keys) {
      logs[key] = await loadLog(key);
    }
    return logs;
  }

  Future<void> clearLog(String logId) async {
    await _logBox.delete(logId);
    await _nameBox.delete(logId);
    await _accelBox.delete(logId);
  }

  Future<void> clearAllLogs() async {
    await _logBox.clear();
    await _nameBox.clear();
    await _accelBox.clear();
  }

  Future<void> saveLogName(String logId, String name) async {
    await _nameBox.put(logId, name);
  }

  Future<String?> getLogName(String logId) async {
    return _nameBox.get(logId);
  }

  Future<String?> exportLogsToCsv(Set<String> selectedLogs) async {
    List<List<String>> csvData = [];
    List<List<String>> accelCsvData = [];

    for (final logId in selectedLogs) {
      final loaded = await loadLog(logId);
      final gpsEntries = loaded[FieldNames.entries] as List<GpsData>?;
      final logName = loaded[FieldNames.name] as String?;
      final accelData = await loadAccel(logId);

      if (gpsEntries == null || gpsEntries.isEmpty) continue;

      // Add headers
      csvData.add([FieldNames.name, ...GpsData.csvHeaders()]);
      accelCsvData.add(['t', 'x', 'y', 'z']);

      // Add data rows
      for (final entry in gpsEntries) {
        csvData.add([logName ?? '', ...entry.toCsvRow(logId)]);
      }
      for (final entry in accelData) {
        accelCsvData.add([
          entry['t'].toString(),
          entry['x'].toString(),
          entry['y'].toString(),
          entry['z'].toString(),
        ]);
      }

      // Blank line between logs
      csvData.add([]);
      accelCsvData.add([]);
    }

    if (csvData.isEmpty) {
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'selected_logs_$now.csv';
    final csvString = const ListToCsvConverter().convert(csvData);

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save selected logs as CSV',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csvString)),
    );

    if (accelCsvData.isNotEmpty) {
      final accelFileName = 'selected_accel_logs_$now.csv';
      final accelCsvString = const ListToCsvConverter().convert(accelCsvData);

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save selected accel logs as CSV',
        fileName: accelFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(accelCsvString)),
      );
    }

    return result;
  }
}
