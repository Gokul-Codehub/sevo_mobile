import 'package:intl/intl.dart';

/// Indian date format used everywhere the customer sees a date: DD-MM-YYYY.
/// (API requests still send ISO `yyyy-MM-dd`; that is a wire format, not UI.)
final DateFormat _dmy = DateFormat('dd-MM-yyyy');
final DateFormat _dmyTime = DateFormat('dd-MM-yyyy, h:mm a');

String formatDmy(DateTime d) => _dmy.format(d);

String formatDmyTime(DateTime d) => _dmyTime.format(d);

/// Turns a server date string ("2026-10-23" or an ISO timestamp) into
/// DD-MM-YYYY. Anything that is not a parseable date is returned unchanged.
String formatDateString(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return raw;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return raw;
  return _dmy.format(parsed);
}
