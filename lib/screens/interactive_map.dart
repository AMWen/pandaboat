import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/models/gps_data.dart';
import '../data/constants.dart';
import '../data/services/location_logger.dart';
import '../utils/line_chart.dart';
import '../utils/time_format.dart';

class InteractiveMap extends StatefulWidget {
  final String logId;
  final List<GpsData> gpsData;

  const InteractiveMap({super.key, required this.logId, required this.gpsData});

  @override
  State<InteractiveMap> createState() => InteractiveMapState();
}

class InteractiveMapState extends State<InteractiveMap> {
  String? logName;
  late List<GpsData> gpsData;
  late String logId;
  final logger = LocationLogger();

  @override
  void initState() {
    super.initState();
    _loadLogName();
    gpsData = widget.gpsData;
    logId = widget.logId;
  }

  Future<void> _loadLogName() async {
    final name = await logger.getLogName(widget.logId);
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
            title: const Text('Edit Log Name'),
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

    if (newName != null && newName.isNotEmpty) {
      await logger.saveLogName(widget.logId, newName);
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
    final List<Map<String, dynamic>> tabsList = [
      {
        'name': 'Interactive Map',
        'icon': Icon(Icons.map),
        'tab': _buildMap(context, minSpeed, maxSpeed),
      },
      {
        'name': 'Speed and SPM vs Distance',
        'icon': Icon(Icons.multiline_chart),
        'tab': InteractiveLineChart(
          xData: extractField(gpsData, (e) => e.distance),
          yData: extractField(gpsData, (e) => e.calculatedSpeed),
          yData2: extractField(gpsData, (e) => e.spm),
          xLabel: "Distance (m)",
          yLabel: "Speed (km/hr)",
          yLabel2: "SPM",
        ),
      },
      {
        'name': 'Smoothed Speed and SPM vs Distance',
        'icon': Row(children: [Icon(Icons.multiline_chart), Icon(Icons.iron)]),
        'tab': InteractiveLineChart(
          xData: extractField(gpsData, (e) => e.distance),
          yData: extractField(gpsData, (e) => e.smoothedCalculated),
          yData2: extractField(gpsData, (e) => e.spm),
          xLabel: "Distance (m)",
          yLabel: "Speed (km/hr)",
          yLabel2: "SPM",
        ),
      },
      {
        'name': 'Speed and SPM vs Time',
        'icon': Icon(Icons.timer),
        'tab': InteractiveLineChart(
          xData: extractField(gpsData, (e) => e.t.toDouble() / 1000),
          yData: extractField(gpsData, (e) => e.calculatedSpeed),
          yData2: extractField(gpsData, (e) => e.spm),
          xLabel: "Time (s)",
          yLabel: "Speed (km/hr)",
          yLabel2: "SPM",
        ),
      },
      {
        'name': 'Smoothed Speed and SPM vs Time',
        'icon': Row(children: [Icon(Icons.timer), Icon(Icons.iron)]),
        'tab': InteractiveLineChart(
          xData: extractField(gpsData, (e) => e.t.toDouble() / 1000),
          yData: extractField(gpsData, (e) => e.smoothedCalculated),
          yData2: extractField(gpsData, (e) => e.spm),
          xLabel: "Time (s)",
          yLabel: "Speed (km/hr)",
          yLabel2: "SPM",
        ),
      },
    ];
    final List<Widget> tabWidgets =
        tabsList.map<Widget>((entry) => entry['tab'] as Widget).toList();

    return DefaultTabController(
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
                  (logName?.length ?? 0) < 25 && !logName!.contains('\n')
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.titleMedium,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: "Delete this log",
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: const Text("Delete Log"),
                        content: const Text("Are you sure you want to delete this log?"),
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text("Cancel"),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text("Delete"),
                          ),
                        ],
                      ),
                );

                if (confirm == true) {
                  final logger = LocationLogger();
                  await logger.clearLog(logId);
                  if (context.mounted) {
                    Navigator.pop(context, 'deleted'); // Return with a signal
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
                      (entry) => Tab(icon: Tooltip(message: entry['name'], child: entry['icon'])),
                    )
                    .toList(),
          ),
        ),
        body: TabBarView(children: tabWidgets),
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
