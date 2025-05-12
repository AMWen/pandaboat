import 'package:flutter/material.dart';
import '../data/services/location_logger.dart';

class LogTab extends StatefulWidget {
  const LogTab({super.key});

  @override
  LogTabState createState() => LogTabState();
}

class LogTabState extends State<LogTab> {
  final logger = LocationLogger();
  Map<String, List<Map<String, dynamic>>> logs = {};

  @override
  void initState() {
    super.initState();
    loadLogs();
  }

  Future<void> loadLogs() async {
    final loaded = await logger.loadAllLogs();
    setState(() {
      logs = loaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Past Logs")),
      body: ListView(
        children: logs.entries.map((entry) {
          final logId = entry.key;
          final entries = entry.value;
          return ListTile(
            title: Text("Log $logId"),
            subtitle: Text("${entries.length} points"),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text("Log $logId"),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        return Text("t=${e['t']}ms, lat=${e['lat']}, lon=${e['lon']}, v=${e['speed'].toStringAsFixed(1)}");
                      },
                    ),
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}
