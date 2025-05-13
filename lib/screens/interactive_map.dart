import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/constants.dart';
import '../utils/line_chart.dart';
import '../utils/time_format.dart';

class InteractiveMap extends StatelessWidget {
  final List<Map<String, dynamic>> gpsData;

  const InteractiveMap({super.key, required this.gpsData});

  @override
  Widget build(BuildContext context) {
    final speeds = gpsData.map((e) => e['speed'] as double).toList();
    final minSpeed = speeds.reduce((a, b) => a < b ? a : b);
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);
    final List<Map<String, dynamic>> tabsList = [
      {
        'name': 'Interactive Map',
        'icon': Icon(Icons.map),
        'tab': _buildMap(context, minSpeed, maxSpeed),
      },
      {
        'name': 'Speed vs Distance',
        'icon': Icon(Icons.show_chart),
        'tab': buildSimpleLineChart(
          xData: getData('distance'),
          yData: getData('speed'),
          xLabel: "Distance (m)",
          yLabel: "Speed (km/hr)",
        ),
      },
      {
        'name': 'SPM vs Distance',
        'icon': Icon(Icons.fast_forward),
        'tab': buildSimpleLineChart(
          xData: getData('distance'),
          yData: getData('spm'),
          xLabel: "Distance (m)",
          yLabel: "SPM",
          color: Colors.lightGreen,
        ),
      },
      {
        'name': 'Speed and SPM vs Distance',
        'icon': Icon(Icons.group),
        'tab': buildSimpleLineChart(
          xData: gpsData.map((e) => e['distance'] as double).toList(),
          yData: gpsData.map((e) => e['speed'] as double).toList(),
          yData2: gpsData.map((e) => e['spm'] as double? ?? 0).toList(),
          xLabel: "Distance (m)",
          yLabel: "Speed (km/hr)",
          yLabel2: "SPM",
        ),
      },
      {
        'name': 'Speed vs Time',
        'icon': Icon(Icons.timer),
        'tab': buildSimpleLineChart(
          xData: gpsData.map((e) => (e['t'] as int).toDouble() / 1000).toList(),
          yData: gpsData.map((e) => e['speed'] as double).toList(),
          xLabel: "Time (s)",
          yLabel: "Speed (km/hr)",
        ),
      },
    ];
    final List<Widget> tabWidgets =
        tabsList.map<Widget>((entry) => entry['tab'] as Widget).toList();

    return DefaultTabController(
      length: tabsList.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Log Analysis"),
          bottom: TabBar(
            labelColor: secondaryColor, // Icon color when selected
            unselectedLabelColor: dullColor, // Icon color when not selected
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

  List<double> getData(String value) {
    return gpsData.map((e) => e[value] as double? ?? 0).toList();
  }

  Widget _buildMap(BuildContext context, double minSpeed, double maxSpeed) {
    final polylinePoints = gpsData.map((point) => LatLng(point['lat'], point['lon'])).toList();

    return FlutterMap(
      options: MapOptions(initialCenter: polylinePoints.first, initialZoom: 18.0),
      children: [
        TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),

        PolylineLayer(
          polylines: [
            Polyline(points: polylinePoints, strokeWidth: 4.0, color: Colors.blue.withOpacity(0.6)),
          ],
        ),

        MarkerLayer(
          markers:
              gpsData.asMap().entries.map((entry) {
                final index = entry.key;
                final point = entry.value;
                final speed = point['speed'];
                final distance = point['distance'];
                final elapsed = Duration(milliseconds: point['t']);
                final latLng = LatLng(point['lat'], point['lon']);

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
                            : (index == gpsData.length - 1
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
              }).toList(),
        ),
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
