import 'package:flutter/material.dart';
import '../data/constants.dart';
import '../data/models/gps_data.dart';
import '../data/services/location_logger.dart';
import '../screens/log_visualization_screen.dart';
import '../utils/time_format.dart';

class LogTab extends StatefulWidget {
  final bool isRecording;
  final String? currentLogId;
  final PageController pageController;

  const LogTab({
    super.key,
    this.isRecording = false,
    this.currentLogId,
    required this.pageController,
  });

  @override
  LogTabState createState() => LogTabState();
}

class LogTabState extends State<LogTab> {
  final logger = LocationLogger();
  Map<String, Map<String, dynamic>> logs = {};
  Set<String> selectedLogs = {};
  String searchQuery = '';
  final TextEditingController searchController = TextEditingController();
  bool _hasNavigatedToLiveLog = false;

  @override
  void initState() {
    super.initState();
    // Only load logs if not recording
    if (!widget.isRecording) {
      loadLogs();
    }
  }

  @override
  void didUpdateWidget(LogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset navigation flag when recording state changes
    if (widget.isRecording != oldWidget.isRecording) {
      _hasNavigatedToLiveLog = false;
    }
    // Reload logs when recording stops
    if (!widget.isRecording && oldWidget.isRecording) {
      loadLogs();
    }
  }

  Future<void> openLiveLog(String logId) async {
    final loaded = await logger.loadLog(logId);
    final gpsData = loaded[FieldNames.entries] as List<GpsData>? ?? [];

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LogVisualizationScreen(
              logIds: [logId],
              currentIndex: 0,
              initialGpsData: gpsData,
              isLiveRecording: true,
            ),
      ),
    );

    // After visualization screen is popped, navigate back to Live tab
    if (mounted && widget.isRecording) {
      widget.pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> downloadSelectedLogs() async {
    final result = await logger.exportLogsToCsv(selectedLogs);

    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Canceled or no valid GPS data found to export.')));
    } else {
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
    final loaded = await logger.loadLog(key);
    final gpsData = loaded[FieldNames.entries];

    final logIds = logs.keys.toList();
    final currentIndex = logIds.indexOf(key);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LogVisualizationScreen(
              logIds: logIds,
              currentIndex: currentIndex,
              initialGpsData: gpsData,
            ),
      ),
    );

    loadLogs(); // Reload logs for any updates
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
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyles.buttonText),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      final filteredLogIds = _getFilteredLogs().map((entry) => entry.key).toSet();
      final areAllSelected = filteredLogIds.every((id) => selectedLogs.contains(id));

      if (areAllSelected) {
        selectedLogs.removeAll(filteredLogIds);
      } else {
        selectedLogs.addAll(filteredLogIds); // Select all filtered
      }
    });
  }

  List<MapEntry<String, Map<String, dynamic>>> _getFilteredLogs() {
    if (searchQuery.isEmpty) {
      return logs.entries.toList();
    }

    return logs.entries.where((entry) {
      final logId = entry.key;
      final logInfo = entry.value;
      final logName = (logInfo[FieldNames.name] as String?) ?? '';

      final queryLower = searchQuery.toLowerCase();
      return logName.toLowerCase().contains(queryLower) ||
          formatLogId(logId).toLowerCase().contains(queryLower);
    }).toList();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If recording, navigate to live log visualization once
    if (widget.isRecording && widget.currentLogId != null && !_hasNavigatedToLiveLog) {
      _hasNavigatedToLiveLog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          openLiveLog(widget.currentLogId!);
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filteredLogs = _getFilteredLogs();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Past Logs"),
        actions: [
          SizedBox(
            width: 34,
            child: IconButton(
              icon: const Icon(Icons.download),
              onPressed: selectedLogs.isEmpty ? null : downloadSelectedLogs,
              tooltip: 'Download selected logs',
            ),
          ),
          SizedBox(
            width: 34,
            child: IconButton(
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
          ),
          SizedBox(width: 12),
        ],
      ),
      body:
          logs.isEmpty
              ? const Center(child: Text('No logs found.'))
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name or date...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon:
                            searchQuery.isNotEmpty
                                ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      searchController.clear();
                                      searchQuery = '';
                                    });
                                  },
                                )
                                : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchQuery = value;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child:
                        filteredLogs.isEmpty
                            ? const Center(child: Text('No matching logs found.'))
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
                                                value:
                                                    filteredLogs.isNotEmpty &&
                                                    filteredLogs.every(
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
                                      SizedBox(
                                        width: 150,
                                        child: Text('Date', style: TextStyles.labelText),
                                      ),
                                      SizedBox(width: 4),
                                      SizedBox(
                                        width: 75,
                                        child: Text('Duration', style: TextStyles.labelText),
                                      ),
                                      SizedBox(width: 4),
                                      SizedBox(
                                        width: 75,
                                        child: Text('Distance', style: TextStyles.labelText),
                                      ),
                                      SizedBox(width: 4),
                                    ],
                                  ),
                                ),
                                ...filteredLogs.map((entry) {
                                  final logId = entry.key;
                                  final logInfo = entry.value;
                                  final gpsEntries = logInfo[FieldNames.entries] as List<GpsData>;
                                  final logName = logInfo[FieldNames.name] as String?;

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
                                                value: selectedLogs.contains(
                                                  logId,
                                                ), // If item is selected
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
                                            width: 150,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  formatLogId(logId),
                                                  style: TextStyles.normalText,
                                                ),
                                                if (logName != null && logName.trim().isNotEmpty)
                                                  Text(
                                                    logName,
                                                    style: Theme.of(context).textTheme.bodySmall,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          SizedBox(
                                            width: 75,
                                            child: Text(
                                              _formatDuration(
                                                gpsEntries.isNotEmpty ? gpsEntries.last.t : null,
                                              ),
                                              style: TextStyles.normalText,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          SizedBox(
                                            width: 75,
                                            child: Text(
                                              _formatDistance(
                                                gpsEntries.isNotEmpty
                                                    ? gpsEntries.last.distance
                                                    : null,
                                              ),
                                              style: TextStyles.normalText,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                  ),
                ],
              ),
    );
  }
}
