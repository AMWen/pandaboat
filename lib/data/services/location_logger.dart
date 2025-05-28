import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pandaboat/data/constants.dart';
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
      prefs.setString('${logPrefix}_$logId', jsonEncode(logData));
    }
  }

  Future<void> saveAccel(
    String logId,
    List<Map<String, double>> accelBuffer,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    if (accelBuffer.isNotEmpty) {
      prefs.setString('${accelPrefix}_$logId', jsonEncode(accelBuffer));
    }
  }

  Future<List<dynamic>> loadAccel(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('${accelPrefix}_$logId');
    if (data == null) return [];

    final decoded = jsonDecode(data) as List<dynamic>;
    return decoded;
  }

  Future<Map<String, dynamic>> loadLog(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('${logPrefix}_$logId');
    if (data == null) return {};

    final decoded = jsonDecode(data) as List<dynamic>;
    final gpsData = decoded.map((e) => GpsData.fromJson(e)).toList();
    final logName = await getLogName(logId);
    final log = {FieldNames.name: logName, FieldNames.entries: gpsData};
    return log;
  }

  Future<Map<String, Map<String, dynamic>>> loadAllLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys().where((k) => k.startsWith('${logPrefix}_'));

    Map<String, Map<String, dynamic>> logs = {};
    for (final key in allKeys) {
      final logId = key.substring(4);
      logs[logId] = await loadLog(logId);
    }
    return logs;
  }

  Future<void> clearLog(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${logPrefix}_$logId');
    await prefs.remove('${namePrefix}_$logId');
    await prefs.remove('${accelPrefix}_$logId');
    _logs.remove(logId);
  }

  Future<void> clearAllLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove =
        prefs
            .getKeys()
            .where(
              (k) =>
                  k.startsWith('${logPrefix}_') ||
                  k.startsWith('${namePrefix}_') ||
                  k.startsWith('${accelPrefix}_'),
            )
            .toList();
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    _logs.clear();
  }

  Future<void> saveLogName(String logId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${namePrefix}_$logId', name);
  }

  Future<String?> getLogName(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${namePrefix}_$logId');
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
