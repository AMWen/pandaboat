import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class ExportService {
  Future<String> exportToCSV() async {
    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList('gps_log') ?? [];
    final decoded = logs.map((e) => jsonDecode(e)).toList();

    final buffer = StringBuffer();
    buffer.writeln('timestamp,latitude,longitude,speed');
    for (final log in decoded) {
      buffer.writeln('${log["timestamp"]},${log["lat"]},${log["lon"]},${log["speed"]}');
    }

    final directory = await getExternalStorageDirectory();
    final file = File('${directory!.path}/pandaboat_logs.csv');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  Future<String> exportToGPX() async {
    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList('gps_log') ?? [];
    final decoded = logs.map((e) => jsonDecode(e)).toList();

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="Pandaboat" xmlns="http://www.topografix.com/GPX/1/1">');
    buffer.writeln('<trk><name>Pandaboat Log</name><trkseg>');

    for (final log in decoded) {
      buffer.writeln('<trkpt lat="${log["lat"]}" lon="${log["lon"]}"><time>${log["timestamp"]}</time></trkpt>');
    }

    buffer.writeln('</trkseg></trk></gpx>');

    final directory = await getExternalStorageDirectory();
    final file = File('${directory!.path}/pandaboat_log.gpx');
    await file.writeAsString(buffer.toString());
    return file.path;
  }
}
