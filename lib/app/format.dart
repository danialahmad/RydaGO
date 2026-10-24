// Display formatting shared by the UI. Pure functions, covered by unit tests.
import 'strings.dart';

/// "350 m" below 1 km (rounded to 10 m), "1.2 km" above.
String formatDistance(double metres) {
  if (metres < 1000) return '${(metres / 10).round() * 10} m';
  return '${(metres / 1000).toStringAsFixed(1)} km';
}

/// "6 min" or "1 h 20 min" ("1 j 20 min" in Malay).
String formatDuration(int minutes, [S s = const S(AppLang.en)]) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h ${s.hourAbbr}' : '$h ${s.hourAbbr} $m min';
}

/// 12-hour clock: "3:22 PM" ("3:22 PTG" in Malay), "12:05 AM".
String formatClock(DateTime t, [S s = const S(AppLang.en)]) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? s.am : s.pm}';
}

/// "RM12.50"-style amount without the currency: "12.5" -> "12.50".
String formatRm(double rm) => rm.toStringAsFixed(2);
