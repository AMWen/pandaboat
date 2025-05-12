import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/constants.dart';
import '../data/services/location_logger.dart';
import '../screens/interactive_map.dart';
import '../utils/time_format.dart';

class LogTab extends StatefulWidget {
  const LogTab({super.key});

  @override
  LogTabState createState() => LogTabState();
}

class LogTabState extends State<LogTab> {
  final logger = LocationLogger();
  Map<String, List<Map<String, dynamic>>> logs = {};
  Set<String> selectedLogs = {};

  @override
  void initState() {
    super.initState();
    loadLogs();
  }

  Future<void> loadLogs() async {
    final loaded = await logger.loadAllLogs();

    setState(() {
      logs = Map.fromEntries(loaded.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
      selectedLogs.clear();
    });
  }

  Future<void> openLog(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('log_$key');
    if (raw == null) return;

    final decoded = jsonDecode(raw) as List;
    final gpsData =
        decoded.map((e) {
          return {
            't': e['t'],
            'speed': e['speed'],
            'lat': e['lat'],
            'lon': e['lon'],
            'distance': e['distance'],
            'spm': e['spm'],
          };
        }).toList();

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => InteractiveMap(gpsData: gpsData)));
  }

  Future<void> deleteSelectedLogs() async {
    for (final logId in selectedLogs) {
      await logger.clearLog(logId);
    }
    await loadLogs(); // Reload logs after deletion
  }

  Future<bool?> showDeleteLogsDialog(BuildContext context, int logCount) {
    if (logCount == 0) {
      return Future.value(false);
    }
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Logs', style: TextStyles.dialogTitle),
            content: Text('Are you sure you want to delete $logCount log(s)?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
    );
  }

  String _formatDuration(int? elapsedTime) {
    if (elapsedTime == null) return '';
    final elapsed = Duration(milliseconds: elapsedTime);
    return formatTime(elapsed);
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    return "${distance.toStringAsFixed(0)} m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Past Logs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDeleteLogsDialog(context, selectedLogs.length);
              if (confirm == true) {
                await deleteSelectedLogs();
              }
            },
          ),
        ],
      ),
      body:
          logs.isEmpty
              ? const Center(child: Text('No logs found.'))
              : ListView(
                children:
                    logs.entries.map((entry) {
                      final logId = entry.key;
                      final entries = entry.value;
                      return GestureDetector(
                        onTap: () {
                          print('Clicked');
                          openLog(logId); // Open the log in InteractiveMap when tapped
                        },
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(formatLogId(logId)),
                              Text(_formatDuration(entries.isNotEmpty ? entries.last['t'] : null)),
                              Text(
                                _formatDistance(
                                  entries.isNotEmpty ? entries.last['distance'] : null,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text("${entries.length} points"),
                        ),
                      );
                    }).toList(), // Convert the mapped iterable back to a List of widgets
              ),
    );
  }
}
