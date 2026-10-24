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

/// Where a point lands on a route line.
class RouteProjection {
  const RouteProjection(this.seg, this.alongM, this.distM, this.snapped);

  final int seg; // index of the closest route segment
  final double alongM; // metres from the route start to the closest point
  final double distM; // how far the point is from the line
  final LatLng snapped; // the closest point on the line
}

/// Projects [p] onto the segments [fromSeg]..[toSeg] of the route (inclusive) and
/// returns the closest spot. Flat-earth maths in metres around [p]: plenty accurate
/// at the scale of a route and far cheaper than haversine per segment.
RouteProjection projectOnRoute(
  LatLng p,
  List<LatLng> pts,
  List<double> cum, {
  int fromSeg = 0,
  int? toSeg,
}) {
  const mLat = 110540.0;
  final mLng = 111320.0 * math.cos(p.latitude * math.pi / 180);
  final last = pts.length - 2; // index of the last segment
  final from = fromSeg.clamp(0, last);
  final to = (toSeg ?? last).clamp(from, last);

  RouteProjection? best;
  for (var i = from; i <= to; i++) {
    final ax = (pts[i].longitude - p.longitude) * mLng;
    final ay = (pts[i].latitude - p.latitude) * mLat;
    final bx = (pts[i + 1].longitude - p.longitude) * mLng;
    final by = (pts[i + 1].latitude - p.latitude) * mLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    final d = math.sqrt(cx * cx + cy * cy);
    if (best == null || d < best.distM) {
      best = RouteProjection(
        i,
        cum[i] + t * (cum[i + 1] - cum[i]),
        d,
        LatLng(p.latitude + cy / mLat, p.longitude + cx / mLng),
      );
    }
  }
  return best!;
}
