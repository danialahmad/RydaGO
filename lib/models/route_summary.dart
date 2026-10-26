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
