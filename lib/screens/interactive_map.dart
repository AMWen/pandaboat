import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class InteractiveMap extends StatelessWidget {
  final List<Map<String, dynamic>> gpsData;

  const InteractiveMap({super.key, required this.gpsData});

  @override
  Widget build(BuildContext context) {
    final startTime = gpsData.first['timestamp'] as DateTime;

    return Scaffold(
      appBar: AppBar(title: const Text("Interactive GPS Map")),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(gpsData.first['lat'], gpsData.first['lon']),
          initialZoom: 14.0,
          onTap: (_, __) => Navigator.of(context).maybePop(), // close dialogs
        ),
        children: [
          TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
          MarkerLayer(
            markers:
                gpsData.map((point) {
                  final lat = point['lat'];
                  final lon = point['lon'];
                  final speed = point['speed'];
                  final timestamp = point['timestamp'] as DateTime;
                  final msSinceStart = timestamp.difference(startTime).inMilliseconds;

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
                                title: const Text('GPS Point Info'),
                                content: Text(
                                  'Speed: ${speed.toStringAsFixed(1)} km/h\n'
                                  'Time: $msSinceStart ms',
                                ),
                              ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getColorForSpeed(speed),
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

  // Color gradient for speed
  Color _getColorForSpeed(double speed) {
    if (speed < 5) return Colors.green;
    if (speed < 10) return Colors.yellow;
    return Colors.red;
  }
}
