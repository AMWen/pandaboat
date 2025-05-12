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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
        'tab': _buildLineChart(
          xData: getData('distance'),
          yData: getData('speed'),
          xLabel: "Distance (m)",
          yLabel: "Speed (km/hr)",
          isDarkMode: isDarkMode,
        ),
      },
      {
        'name': 'SPM vs Distance',
        'icon': Icon(Icons.fast_forward),
        'tab': _buildLineChart(
          xData: getData('distance'),
          yData: getData('spm'),
          xLabel: "Distance (m)",
          yLabel: "SPM",
          isDarkMode: isDarkMode,
        ),
      },
      {
        'name': 'Speed and SPM vs Distance',
        'icon': Icon(Icons.group),
        'tab': _buildDualAxisChart(
          xData: gpsData.map((e) => e['distance'] as double).toList(),
          yData1: gpsData.map((e) => e['speed'] as double).toList(),
          yData2: gpsData.map((e) => e['spm'] as double? ?? 0).toList(),
          xLabel: "Distance (m)",
          yLabel1: "Speed (km/hr)",
          yLabel2: "SPM",
          isDarkMode: isDarkMode,
        ),
      },
      {
        'name': 'Speed vs Time',
        'icon': Icon(Icons.timer),
        'tab': _buildLineChart(
          xData: gpsData.map((e) => (e['t'] as int).toDouble() / 1000).toList(),
          yData: gpsData.map((e) => e['speed'] as double).toList(),
          xLabel: "Time (s)",
          yLabel: "Speed (km/hr)",
          isDarkMode: isDarkMode,
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
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(gpsData.first['lat'], gpsData.first['lon']),
        initialZoom: 14.0,
        onTap: (_, __) => Navigator.of(context).maybePop(),
      ),
      children: [
        TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
        MarkerLayer(
          markers:
              gpsData.map((point) {
                final lat = point['lat'];
                final lon = point['lon'];
                final speed = point['speed'];
                final distance = point['distance'];
                final elapsed = Duration(milliseconds: point['t']);

                return Marker(
                  point: LatLng(lat, lon),
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
                              ),
                            ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _getColorForSpeed(speed, minSpeed, maxSpeed),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildLineChart({
    required List<double> xData,
    required List<double> yData,
    required String xLabel,
    required String yLabel,
    required bool isDarkMode,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(yLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(child: buildSimpleLineChart(xData: xData, yData: yData, isDarkMode: isDarkMode)),
          const SizedBox(height: 8),
          Center(child: Text(xLabel, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildDualAxisChart({
    required List<double> xData,
    required List<double> yData1,
    required List<double> yData2,
    required String xLabel,
    required String yLabel1,
    required String yLabel2,
    required bool isDarkMode,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(yLabel1, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(yLabel2, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: buildSimpleLineChart(
              xData: xData,
              yData: yData1,
              yData2: yData2,
              isDarkMode: isDarkMode,
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(xLabel, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
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
