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