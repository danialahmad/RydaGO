// Display formatting shared by the UI. Pure functions, covered by unit tests.

/// "350 m" below 1 km (rounded to 10 m), "1.2 km" above.
String formatDistance(double metres) {
  if (metres < 1000) return '${(metres / 10).round() * 10} m';
  return '${(metres / 1000).toStringAsFixed(1)} km';
}

/// "6 min" or "1 j 20 min".
String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h j' : '$h j $m min';
}

/// 12-hour clock with Malay day-part: "3:22 PTG", "12:05 PG".
String formatClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'PG' : 'PTG'}';
}
