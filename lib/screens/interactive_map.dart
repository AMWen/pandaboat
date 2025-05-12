import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/time_format.dart';

class InteractiveMap extends StatelessWidget {
  final List<Map<String, dynamic>> gpsData;

  const InteractiveMap({super.key, required this.gpsData});

  @override
  Widget build(BuildContext context) {
    final speeds = gpsData.map((e) => e['speed'] as double).toList();
    final minSpeed = speeds.reduce((a, b) => a < b ? a : b);
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text("Interactive GPS Map")),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(gpsData.first['lat'], gpsData.first['lon']),
          initialZoom: 14.0,
          onTap: (_, __) => Navigator.of(context).maybePop(),
        ),
        children: [
          TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
          MarkerLayer(
            markers: gpsData.map((point) {
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
                      builder: (_) => AlertDialog(
                        title: const Text('GPS Point Info'),
                        content: Text(
                          'Time: ${formatTime(elapsed)}\n'
                          'Distance: ${distance.toStringAsFixed(0)} m\n'
                          'Speed: ${speed.toStringAsFixed(1)} km/hr\n'
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
      ),
    );
  }

  // Gradient color based on normalized speed
  Color _getColorForSpeed(double speed, double minSpeed, double maxSpeed) {
    if (maxSpeed == minSpeed) return Colors.green; // avoid divide-by-zero

    double t = (speed - minSpeed) / (maxSpeed - minSpeed); // normalize to [0, 1]

    // Use a 3-color gradient: green → yellow → red
    if (t < 0.5) {
      return Color.lerp(Colors.green, Colors.yellow, t * 2)!; // 0.0–0.5 → green→yellow
    } else {
      return Color.lerp(Colors.yellow, Colors.red, (t - 0.5) * 2)!; // 0.5–1.0 → yellow→red
    }
  }
}
