import 'package:intl/intl.dart';

String formatLogId(String isoLogId) {
  try {
    final dt = DateTime.parse(isoLogId);
    final formatter = DateFormat('M/d/yy h:mm a');
    return formatter.format(dt);
  } catch (_) {
    return isoLogId; // fallback if parsing fails
  }
}

String formatTime(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (hours > 0) {
    return "$hours:$minutes:$seconds";
  } else {
    return "$minutes:$seconds";
  }
}
