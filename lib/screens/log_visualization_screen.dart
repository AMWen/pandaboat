import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/models/gps_data.dart';
import '../data/constants.dart';
import '../data/services/location_logger.dart';
import '../utils/line_chart.dart';
import '../utils/time_format.dart';

class LogVisualizationScreen extends StatefulWidget {
  final List<String> logIds;
  final int currentIndex;
  final List<GpsData> initialGpsData;
  final String? logId;

  const LogVisualizationScreen({
    super.key,
    required this.logIds,
    required this.currentIndex,
    required this.initialGpsData,
    this.logId,
  });

  @override
  LogVisualizationScreenState createState() => LogVisualizationScreenState();
}

class LogVisualizationScreenState extends State<LogVisualizationScreen> {
  late List<String> logIds;
  late int currentIndex;
  List<GpsData> gpsData = [];
  late String logId;

  String? logName;
  final logger = LocationLogger();

  bool _useInstantValues = true; // false = calculated
  bool _useSmoothing = true;

  @override
  void initState() {
    super.initState();
    setState(() {
      logIds = widget.logIds;
      currentIndex = widget.currentIndex;
      gpsData = widget.initialGpsData;
      logId = logIds[currentIndex];
    });
    _loadLogName();
    super.initState();
  }

  Future<void> loadLog(int index) async {
    final loaded = await logger.loadLog(logIds[index]);

    setState(() {
      currentIndex = index;
      gpsData = loaded[FieldNames.entries];
      logName = loaded[FieldNames.name];
      logId = logIds[index];
    });
  }

  void onSwipeLeft() {
    if (currentIndex < widget.logIds.length - 1) {
      loadLog(currentIndex + 1);
    } else if (currentIndex == widget.logIds.length - 1) {
      loadLog(0);
    }
  }

  void onSwipeRight() {
    if (currentIndex > 0) {
      loadLog(currentIndex - 1);
    } else if (currentIndex == 0) {
      loadLog(widget.logIds.length - 1);
    }
  }

  Future<void> _loadLogName() async {
    final name = await logger.getLogName(logId);
    setState(() {
      logName = name;
    });
  }

  Future<void> _editLogName() async {
    final controller = TextEditingController(text: logName ?? '');

    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit Log Name', style: TextStyles.dialogTitle),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Enter a name'),
              keyboardType: TextInputType.multiline,
              maxLines: null,
              autofocus: true,
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (newName != null) {
      await logger.saveLogName(logId, newName);
      setState(() {
        logName = newName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final speeds = extractField(gpsData, (e) => e.speed);
    final minSpeed = speeds.reduce((a, b) => a < b ? a : b);
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);

    String chartTitle(String base) => '${_useSmoothing ? "Smoothed " : ""}$base';
    List<Map<String, dynamic>> tabsList = [
      {
        FieldNames.name: 'Interactive Map',
        FieldNames.icon: Icon(Icons.map),
        FieldNames.tab: _buildMap(context, minSpeed, maxSpeed),
      },
      {
        FieldNames.name: chartTitle('Speed and SPM vs Distance'),
        FieldNames.icon: Icon(Icons.route),
        FieldNames.tab: InteractiveLineChart(
          xData: extractField(gpsData, (e) => e.distance),
          yData: extractField(
            gpsData,
            (e) =>
                _useSmoothing
                    ? (_useInstantValues ? e.smoothed : e.smoothedCalculated)
                    : (_useInstantValues ? e.speed : e.calculatedSpeed),
          ),
          yData2: extractField(gpsData, (e) => e.spm),
          xLabel: "Distance (m)",
          yLabel: "Speed (km/hr)",
          yLabel2: "SPM",
        ),
      },
      {
        FieldNames.name: chartTitle('Speed and SPM vs Time'),
        FieldNames.icon: Icon(Icons.timer),
        FieldNames.tab: InteractiveLineChart(
          xData: extractField(gpsData, (e) => e.t.toDouble() / 1000),
          yData: extractField(
            gpsData,
            (e) =>
                _useSmoothing
                    ? (_useInstantValues ? e.smoothed : e.smoothedCalculated)
                    : (_useInstantValues ? e.speed : e.calculatedSpeed),
          ),
          yData2: extractField(gpsData, (e) => e.spm),
          xLabel: "Time (s)",
          yLabel: "Speed (km/hr)",
          yLabel2: "SPM",
        ),
      },
      {
        FieldNames.name: chartTitle('Distance vs Time'),
        FieldNames.icon: Icon(Icons.moving),
        FieldNames.tab: InteractiveLineChart(
          xData: extractField(gpsData, (e) => e.t.toDouble() / 1000),
          yData: extractField(gpsData, (e) => e.distance),
          xLabel: "Time (s)",
          yLabel: "Distance (m)",
        ),
      },
    ];
    final List<Widget> tabWidgets =
        tabsList.map<Widget>((entry) => entry['tab'] as Widget).toList();

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;

        if (details.primaryVelocity! < 0) {
          onSwipeLeft();
        } else if (details.primaryVelocity! > 0) {
          onSwipeRight();
        }
      },
      child: DefaultTabController(
        length: tabsList.length,
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: kToolbarHeight * 0.75,
            title: GestureDetector(
              onTap: _editLogName,
              child: Text(
                logName?.isNotEmpty == true ? logName! : 'Log Analysis',
                overflow: TextOverflow.visible,
                softWrap: true,
                style:
                    (logName?.length ?? 0) < 25 && (logName == null || !logName!.contains('\n'))
                        ? Theme.of(context).appBarTheme.titleTextStyle
                        : Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 16),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: "Download this log",
                onPressed: () async {
                  final result = await logger.exportLogsToCsv({logId});

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result == null
                              ? 'Canceled or no valid GPS data found to export.'
                              : 'Log saved to $result',
                        ),
                      ),
                    );
                  }
                },
              ),
              IconButton(
                icon: Icon(_useSmoothing ? Icons.iron : Icons.iron_outlined),
                tooltip: _useSmoothing ? 'Smoothed Data' : 'Raw Data',
                onPressed: () {
                  setState(() {
                    _useSmoothing = !_useSmoothing;
                  });
                },
              ),
              IconButton(
                icon: Icon(_useInstantValues ? Icons.flash_on : Icons.flash_off),
                tooltip: _useInstantValues ? 'Showing Instant Values' : 'Showing Calculated Values',
                onPressed: () {
                  setState(() {
                    _useInstantValues = !_useInstantValues;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: "Delete this log",
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder:
                        (ctx) => AlertDialog(
                          title: const Text("Delete Log", style: TextStyles.dialogTitle),
                          content: const Text("Are you sure you want to delete this log?"),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text("Cancel"),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                  );

                  if (confirm == true) {
                    await logger.clearLog(logId);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
              ),
            ],
            bottom: TabBar(
              dividerHeight: 0,
              labelColor: secondaryColor,
              unselectedLabelColor: dullColor,
              tabs:
                  tabsList
                      .map(
                        (entry) => Tab(
                          icon: Tooltip(
                            message: entry[FieldNames.name],
                            child: entry[FieldNames.icon],
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          body: TabBarView(children: tabWidgets),
        ),
      ),
    );
  }

  List<double> extractField(List<GpsData> data, double Function(GpsData) fieldSelector) {
    return data.where((e) => e.outlier == false).map(fieldSelector).toList();
  }

  Widget _buildMap(BuildContext context, double minSpeed, double maxSpeed) {
    // Filter out outliers first, then create the polyline and markers
    final filteredData = gpsData.where((point) => !point.outlier).toList();

    final polylinePoints = filteredData.map((point) => LatLng(point.lat, point.lon)).toList();

    final markers =
        filteredData.asMap().entries.map((entry) {
          final index = entry.key;
          final point = entry.value;
          final speed = point.speed;
          final distance = point.distance;
          final elapsed = Duration(milliseconds: point.t);
          final latLng = LatLng(point.lat, point.lon);

          return Marker(
            point: latLng,
            width: 20,
            height: 20,
            child: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder:
                      (_) => AlertDialog(
                        title: const Text('GPS Point Info', style: TextStyles.dialogTitle),
                        content: Text(
                          'Time: ${formatTime(elapsed)}\n'
                          'Distance: ${distance.toStringAsFixed(0)} m\n'
                          'Speed: ${speed.toStringAsFixed(1)} km/hr\n',
                          style: TextStyles.buttonText,
                        ),
                      ),
                );
              },
              child:
                  index == 0
                      ? Icon(Icons.home, color: primaryColor, size: 36)
                      : (index == filteredData.length - 1
                          ? Icon(Icons.sports_score, color: Colors.black, size: 36)
                          : Container(
                            decoration: BoxDecoration(
                              color: _getColorForSpeed(speed, minSpeed, maxSpeed),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26),
                            ),
                          )),
            ),
          );
        }).toList();

    return FlutterMap(
      options: MapOptions(initialCenter: polylinePoints.first, initialZoom: 18.0),
      children: [
        TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
        PolylineLayer(
          polylines: [
            Polyline(points: polylinePoints, strokeWidth: 4.0, color: Colors.blue.withAlpha(150)),
          ],
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Color _getColorForSpeed(double speed, double minSpeed, double maxSpeed) {
    if (maxSpeed == minSpeed) return Colors.green;

    double t = (speed - minSpeed) / (maxSpeed - minSpeed);

    if (t < 0.5) {
      return Color.lerp(Colors.green, Colors.yellow, t * 2)!;
    } else {
      return Color.lerp(Colors.yellow, Colors.red, (t - 0.5) * 2)!;
    }
  }
}
