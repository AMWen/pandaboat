import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../data/constants.dart';
import '../data/models/gps_data.dart';
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

  Future<void> downloadSelectedLogs() async {
    final prefs = await SharedPreferences.getInstance();
    List<List<String>> csvData = [];

    for (final logId in selectedLogs) {
      final raw = prefs.getString('log_$logId');
      if (raw == null) continue;

      final decoded = jsonDecode(raw) as List<dynamic>;

      // Add headers
      csvData.add(["logId", "t", "speed", "calculatedSpeed", "smoothed", "lat", "lon", "distance", "spm"]);

      // Add data rows
      for (final entry in decoded) {
        csvData.add([
          logId,
          "${entry['t']}",
          "${entry['speed']}",
          "${entry['calculatedSpeed']}",
          "${entry['smoothed']}",
          "${entry['lat']}",
          "${entry['lon']}",
          "${entry['distance']}",
          "${entry['spm']}",
        ]);
      }

      // Blank line between logs
      csvData.add([]);
    }

    if (mounted && csvData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No valid GPS data found to export.')));
      return;
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

    if (result == null) {
      return; // User cancelled
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logs saved to $result')));
    }
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
    final gpsData = decoded.map((e) => GpsData.fromJson(e)).toList();

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
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Logs', style: TextStyles.dialogTitle),
            content: Text('Are you sure you want to delete $logCount log(s)?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyles.buttonText),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: TextStyles.buttonText),
              ),
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

  void toggleSelectAll() {
    setState(() {
      final allLogIds = logs.entries.map((entry) => entry.key).toSet();
      final areAllSelected = allLogIds.every((id) => selectedLogs.contains(id));

      if (areAllSelected) {
        selectedLogs.clear();
      } else {
        selectedLogs = {...allLogIds}; // Select all
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Past Logs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: selectedLogs.isEmpty ? null : downloadSelectedLogs,
            tooltip: 'Download selected logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed:
                selectedLogs.isEmpty
                    ? null
                    : () async {
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
                // "Select All" checkbox row
                [
                  ListTile(
                    key: ValueKey('selectAll'),
                    minTileHeight: 10,
                    contentPadding: EdgeInsets.only(top: 8),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: toggleSelectAll,
                          child: SizedBox(
                            height: 24,
                            width: 50,
                            child: Row(
                              children: [
                                Checkbox(
                                  value: logs.entries.every(
                                    (entry) => selectedLogs.contains(entry.key),
                                  ),
                                  onChanged: (bool? value) {
                                    toggleSelectAll();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 160, child: Text('Date', style: TextStyles.labelText)),
                        SizedBox(width: 8),
                        SizedBox(width: 75, child: Text('Duration', style: TextStyles.labelText)),
                        SizedBox(width: 8),
                        SizedBox(width: 75, child: Text('Distance', style: TextStyles.labelText)),
                        SizedBox(width: 8),
                      ],
                    ),
                  ),
                  ...logs.entries.map((entry) {
                    final logId = entry.key;
                    final entries = entry.value;
                    return GestureDetector(
                      onTap: () => openLog(logId),
                      child: ListTile(
                        minTileHeight: 10,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (selectedLogs.contains(logId)) {
                                    selectedLogs.remove(logId);
                                  } else {
                                    selectedLogs.add(logId);
                                  }
                                });
                              },
                              child: SizedBox(
                                height: 24,
                                width: 50,
                                child: Checkbox(
                                  value: selectedLogs.contains(logId), // If item is selected
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        selectedLogs.add(logId);
                                      } else {
                                        selectedLogs.remove(logId);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 160,
                              child: Text(formatLogId(logId), style: TextStyles.normalText),
                            ),
                            SizedBox(width: 8),
                            SizedBox(
                              width: 75,
                              child: Text(
                                _formatDuration(entries.isNotEmpty ? entries.last['t'] : null),
                                style: TextStyles.normalText,
                              ),
                            ),
                            SizedBox(width: 8),
                            SizedBox(
                              width: 75,
                              child: Text(
                                _formatDistance(
                                  entries.isNotEmpty ? entries.last['distance'] : null,
                                ),
                                style: TextStyles.normalText,
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
    );
  }
}
