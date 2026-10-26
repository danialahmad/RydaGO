import 'geo.dart';
import 'report.dart';
import 'route.dart';

/// A report this close to the route line counts as being on our road.
const kRouteReportM = 60.0;

/// How many reports of each kind lie on [route] right now, for the summary shown
/// before the trip starts ("2 speed cameras, 1 accident"). Reports on other roads
/// that merely run nearby are not counted.
Map<ReportType, int> reportsOnRoute(RouteOption route, Iterable<Report> reports) {
  final counts = <ReportType, int>{};
  if (route.points.length < 2) return counts;
  final cum = routeCumulative(route.points);
  for (final r in reports) {
    if (projectOnRoute(r.pos, route.points, cum).distM <= kRouteReportM) {
      counts[r.type] = (counts[r.type] ?? 0) + 1;
    }
  }
  return counts;
}

/// Minutes a report is likely to cost a driver who passes it. Valhalla has no live
/// traffic, so community reports are the only sign of a jam, crash or closure.
/// Police, cameras and most hazards cost nothing.
int reportDelayMin(Report r) => switch ((r.type, r.subtype)) {
  (ReportType.jam, 'standstill') => 10,
  (ReportType.jam, 'heavy') => 6,
  (ReportType.jam, _) => 3,
  (ReportType.accident, 'major') => 12,
  (ReportType.accident, 'minor') => 4,
  (ReportType.accident, 'other_side') => 1,
  (ReportType.accident, _) => 4,
  (ReportType.closed, 'lane') => 3,
  (ReportType.closed, _) => 25,
  (ReportType.hazard, 'construction') => 2,
  _ => 0,
};

/// The most delay we add for one route, so a pile of reports cannot make a
/// perfectly good road look hopeless.
const kMaxDelayMin = 30;

/// Estimated minutes lost on [route] to reports lying on it from [fromM] metres
/// along it onwards. Several reports close together are usually the same jam, so
/// only the worst one within 300 m counts.
int routeDelayMin(
  RouteOption route,
  Iterable<Report> reports, {
  double fromM = 0,
}) {
  if (route.points.length < 2) return 0;
  final cum = routeCumulative(route.points);
  final hits = <(double, int)>[];
  for (final r in reports) {
    final d = reportDelayMin(r);
    if (d == 0) continue;
    final p = projectOnRoute(r.pos, route.points, cum);
    if (p.distM <= kRouteReportM && p.alongM >= fromM) hits.add((p.alongM, d));
  }
  hits.sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0;
  double? clusterEnd;
  var clusterMax = 0;
  for (final (along, delay) in hits) {
    if (clusterEnd == null || along > clusterEnd) {
      total += clusterMax;
      clusterMax = delay;
      clusterEnd = along + 300;
    } else if (delay > clusterMax) {
      clusterMax = delay;
    }
  }
  total += clusterMax;
  return total > kMaxDelayMin ? kMaxDelayMin : total;
}

/// A route found from where the driver is now, with the delay its reports add.
class RouteChoice {
  const RouteChoice(this.route, this.delayMin);
  final RouteOption route;
  final int delayMin;

  int get totalMin => route.minutes + delayMin;
}

/// Saving needed before a switch is worth suggesting, in minutes.
const kMinSavingMin = 3;

/// True if [candidate] is the road we are already driving, judged by length and
/// main road: switching to it would change nothing.
bool isSameRoad(
  RouteOption candidate, {
  required double remainingKm,
  required String via,
}) => (candidate.km - remainingKm).abs() < 0.4 && candidate.via == via;

/// The best route to suggest instead of the current one, or null.
/// [currentMin] is the time left on the current route and [currentDelayMin] the
/// delay its reports (and any standstill) add. A candidate must beat that total
/// by at least [kMinSavingMin], and must not just be the current road again.
RouteChoice? pickBetterRoute({
  required int currentMin,
  required int currentDelayMin,
  required double remainingKm,
  required String via,
  required Iterable<RouteChoice> candidates,
}) {
  final current = currentMin + currentDelayMin;
  RouteChoice? best;
  for (final c in candidates) {
    if (isSameRoad(c.route, remainingKm: remainingKm, via: via)) continue;
    if (current - c.totalMin < kMinSavingMin) continue;
    if (best == null || c.totalMin < best.totalMin) best = c;
  }
  return best;
}

/// Tells when the car has been (almost) standing still for long enough to call it
/// stuck in traffic. Feed it every GPS speed; the clock is injectable for tests.
class StuckDetector {
  StuckDetector({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Below this speed (km/h) the car counts as crawling.
  static const crawlKmh = 8.0;

  /// Crawling this long counts as stuck.
  static const stuckAfter = Duration(seconds: 60);

  DateTime? _since;

  bool get _stuck =>
      _since != null && _clock().difference(_since!) >= stuckAfter;

  /// True while the car has been crawling for [stuckAfter] or more. An unknown
  /// speed neither starts nor ends a crawl.
  bool update(double? speedKmh) {
    if (speedKmh == null) return _stuck;
    if (speedKmh >= crawlKmh) {
      _since = null;
      return false;
    }
    _since ??= _clock();
    return _stuck;
  }

  void reset() => _since = null;
}
