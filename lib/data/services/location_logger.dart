import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gps_data.dart';

class LocationLogger {
  final Map<String, List<Map<String, dynamic>>> _logs = {};

  void startNewLog(String logId) {
    _logs[logId] = [];
  }

  void appendToLog(String logId, dynamic data) {
    if (!_logs.containsKey(logId)) {
      startNewLog(logId);
    }

    if (data is Map<String, dynamic>) {
      _logs[logId]!.add(data);
    } else if (data is List<Map<String, dynamic>>) {
      _logs[logId]!.addAll(data);
    } else {
      throw ArgumentError('Data must be a Map or List of Maps');
    }
    saveLog(logId);
  }

  Future<void> saveLog(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    final logData = _logs[logId];
    if (logData != null) {
      prefs.setString('log_$logId', jsonEncode(logData));
    }
  }

  Future<Map<String, dynamic>> loadLog(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('log_$logId');
    if (data == null) return {};

    final decoded = jsonDecode(data) as List<dynamic>;
    final gpsData = decoded.map((e) => GpsData.fromJson(e)).toList();
    final name = await getLogName(logId);
    final log = {'name': name, 'entries': gpsData};
    return log;
  }

  Future<Map<String, Map<String, dynamic>>> loadAllLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys().where((k) => k.startsWith('log_'));

    Map<String, Map<String, dynamic>> logs = {};
    for (final key in allKeys) {
      final logId = key.substring(4);
      logs[logId] = await loadLog(logId);
    }
    return logs;
  }

  Future<void> clearLog(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('log_$logId');
    await prefs.remove('name_$logId');
    _logs.remove(logId);
  }

  Future<void> clearAllLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove =
        prefs.getKeys().where((k) => k.startsWith('log_') || k.startsWith('name_')).toList();
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    _logs.clear();
  }

  Future<void> saveLogName(String logId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name_$logId', name);
  }

  Future<String?> getLogName(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('name_$logId');
  }

  Future<String?> exportLogsToCsv(Set<String> selectedLogs) async {
    List<List<String>> csvData = [];

    for (final logId in selectedLogs) {
      final loaded = await loadLog(logId);
      final gpsEntries = loaded['entries'] as List<GpsData>?;
      final logName = loaded['name'] as String?;

      if (gpsEntries == null || gpsEntries.isEmpty) continue;

      // Add headers
      csvData.add(['name', ...GpsData.csvHeaders()]);

      // Add data rows
      for (final entry in gpsEntries) {
        csvData.add([logName ?? '', ...entry.toCsvRow(logId)]);
      }

      // Blank line between logs
      csvData.add([]);
    }

    if (csvData.isEmpty) {
      return null;
    }

    final csvString = const ListToCsvConverter().convert(csvData);
    final fileName = 'selected_logs_${DateTime.now().millisecondsSinceEpoch}.csv';

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save selected logs as CSV',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csvString)),
    );

    return result;
  }
}
