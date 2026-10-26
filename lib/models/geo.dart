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

/// The camera centre and zoom that show all of [pts] in a [width] x [height]
/// map view, inside the part left clear by [top], [bottom] and [side] pixels
/// (panels drawn over the map). Web Mercator with 512 px tiles, like MapLibre.
({LatLng center, double zoom}) fitCamera(
  List<LatLng> pts,
  double width,
  double height, {
  double top = 0,
  double bottom = 0,
  double side = 0,
  double minZoom = 3,
  double maxZoom = 16,
}) {
  // World coordinates from 0 to 1: x eastwards, y southwards.
  double wx(LatLng p) => (p.longitude + 180) / 360;
  double wy(LatLng p) {
    final s = math.sin(p.latitude * math.pi / 180);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, wx(p));
    maxX = math.max(maxX, wx(p));
    minY = math.min(minY, wy(p));
    maxY = math.max(maxY, wy(p));
  }
  final clearW = math.max(1.0, width - 2 * side);
  final clearH = math.max(1.0, height - top - bottom);
  final spanX = math.max(maxX - minX, 1e-12) * 512;
  final spanY = math.max(maxY - minY, 1e-12) * 512;
  final zoom = (math.log(math.min(clearW / spanX, clearH / spanY)) / math.ln2)
      .clamp(minZoom, maxZoom);
  // The clear area's middle is (bottom - top) / 2 px above the view's middle,
  // so the camera aims that far below the middle of the points.
  final scale = 512 * math.pow(2, zoom);
  final cx = (minX + maxX) / 2;
  final cy = (minY + maxY) / 2 + (bottom - top) / 2 / scale;
  final lat = math.atan(_sinh(math.pi * (1 - 2 * cy))) * 180 / math.pi;
  return (center: LatLng(lat, cx * 360 - 180), zoom: zoom.toDouble());
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// A navigation arrow [lengthM] long, centred on [at] and pointing to
/// [bearingDeg], as a closed polygon ring for the map.
List<LatLng> arrowPolygon(LatLng at, double bearingDeg, {double lengthM = 10}) {
  const mLat = 110540.0;
  final mLng = 111320.0 * math.cos(at.latitude * math.pi / 180);
  final b = bearingDeg * math.pi / 180;
  final h = lengthM / 2;
  // Tip, right wing, notch, left wing, back to the tip. Metres, x right, y ahead.
  final shape = [(0.0, h), (0.75 * h, -h), (0.0, -0.45 * h), (-0.75 * h, -h), (0.0, h)];
  return [
    for (final (x, y) in shape)
      LatLng(
        at.latitude + (-x * math.sin(b) + y * math.cos(b)) / mLat,
        at.longitude + (x * math.cos(b) + y * math.sin(b)) / mLng,
      ),
  ];
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
///
/// With [headingDeg] (direction of travel), segments pointing more than 90° away
/// from it are skipped: after a U-turn the route comes back on the other
/// carriageway a few metres away, and a fix must not jump onto that leg. If no
/// segment qualifies (driving the route backwards) the heading is ignored.
RouteProjection projectOnRoute(
  LatLng p,
  List<LatLng> pts,
  List<double> cum, {
  int fromSeg = 0,
  int? toSeg,
  double? headingDeg,
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
    if (headingDeg != null && len2 > 0) {
      final segDeg = math.atan2(dx, dy) * 180 / math.pi;
      final diff = (segDeg - headingDeg).abs() % 360;
      if (math.min(diff, 360 - diff) > 90) continue;
    }
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
  return best ??
      projectOnRoute(p, pts, cum, fromSeg: fromSeg, toSeg: toSeg);
}
