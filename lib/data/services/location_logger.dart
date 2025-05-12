import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocationLogger {
  Map<String, List<Map<String, dynamic>>> _logs = {};

  void startNewLog(String logId) {
    _logs[logId] = [];
  }

  void appendToLog(String logId, Map<String, dynamic> data) {
    if (!_logs.containsKey(logId)) {
      _logs[logId] = [];
    }
    _logs[logId]!.add(data);
  }

  Future<void> saveLog(String logId) async {
    final prefs = await SharedPreferences.getInstance();
    final logData = _logs[logId];
    if (logData != null) {
      prefs.setString('log_$logId', jsonEncode(logData));
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadAllLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys().where((k) => k.startsWith('log_'));

    Map<String, List<Map<String, dynamic>>> logs = {};
    for (final key in allKeys) {
      final data = prefs.getString(key);
      if (data != null) {
        final decoded = jsonDecode(data) as List<dynamic>;
        logs[key.substring(4)] = decoded.cast<Map<String, dynamic>>();
      }
    }
    return logs;
  }
}
