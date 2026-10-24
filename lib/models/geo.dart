import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

/// Great-circle distance in metres.
double haversineM(LatLng a, LatLng b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Metres from the start of [pts] to each point.
List<double> routeCumulative(List<LatLng> pts) {
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last + haversineM(pts[i - 1], pts[i]));
  }
  return cum;
}
