import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/geo.dart';
import '../models/report.dart';
import '../models/route.dart';
import '../models/user_loc.dart';
import '../services/api.dart';
import 'settings.dart';
import 'trip.dart';
import 'user_loc.dart';

// Navigation thresholds (metres unless noted).
const kOffRouteM = 50.0; // further than this from the route counts as off it
const kHardOffRouteM = 120.0; // so far off that we re-route straight away
const kArriveM = 30.0;
const kMaxAccuracyM = 100.0; // ignore fixes less precise than this
const kRerouteCooldown = Duration(seconds: 8);
const kReportOnRouteM =
    60.0; // a report this close to the route line counts as "on our road"
const kLimitCarryM = 400.0; // keep showing the last known speed limit this far

/// Where we are on the active route, derived from the latest GPS fix.
class NavState {
  const NavState({
    required this.route,
    required this.cum,
    required this.alongM,
    required this.pos,
    this.seg = 0,
    this.arrived = false,
    this.rerouting = false,
    this.offRouteM = 0,
    this.speedKmh,
    this.heading,
  });

  final RouteOption route; // the route being followed (changes on re-route)
  final List<double> cum; // metres from the start to each route point
  final double alongM; // progress along the route
  final LatLng pos; // snapped to the route when close to it, else the raw fix
  final int seg; // index of the route segment we are on
  final bool arrived;
  final bool rerouting;
  final double offRouteM; // distance from the route line
  final double? speedKmh;
  final double? heading;

  double get totalM => cum.last;
  double get remainingM => math.max(0, totalM - alongM);
  int get remainingMin => arrived || totalM <= 0
      ? 0
      : math.max(1, (route.minutes * remainingM / totalM).ceil());

  /// 0..1 share of the route already driven.
  double get progress => totalM <= 0 ? 0 : (alongM / totalM).clamp(0.0, 1.0);

  /// The next maneuver still ahead of us (the last one once we are close to it).
  Maneuver? get upcoming {
    for (final m in route.maneuvers) {
      if (cum[m.index] >= alongM) return m;
    }
    return route.maneuvers.isEmpty ? null : route.maneuvers.last;
  }

  double get distToUpcomingM {
    final m = upcoming;
    return m == null ? 0 : math.max(0, cum[m.index] - alongM);
  }

  /// The maneuver right after [upcoming] if it follows within 500 m ("then ..."),
  /// so the banner can warn about a quick second turn.
  Maneuver? get then {
    final m = upcoming;
    if (m == null) return null;
    final i = route.maneuvers.indexOf(m);
    if (i < 0 || i + 1 >= route.maneuvers.length) return null;
    final following = route.maneuvers[i + 1];
    return cum[following.index] - cum[m.index] <= 500 ? following : null;
  }

  /// The posted speed limit here, or null when OpenStreetMap does not know it.
  /// The last known limit is carried forward for [kLimitCarryM] so the sign does
  /// not flicker off on a short unmapped stretch of the same road.
  int? get speedLimitKmh {
    SpeedLimit? last;
    for (final l in route.limits) {
      if (l.from > seg) break;
      last = l;
    }
    if (last == null) return null;
    if (seg <= last.to) return last.kmh;
    return cum[seg] - cum[last.to] <= kLimitCarryM ? last.kmh : null;
  }

  /// True when the speed is over the limit by more than [toleranceKmh].
  bool isSpeeding(int toleranceKmh) {
    final limit = speedLimitKmh, speed = speedKmh;
    return limit != null && speed != null && speed > limit + toleranceKmh;
  }

  /// Reports that lie on the route within [withinM] ahead of us, nearest first.
  /// With [passedM] > 0, reports we just drove past are included as well.
  List<ReportAhead> reportsAhead(
    Iterable<Report> reports, {
    double withinM = 800,
    double passedM = 0,
  }) {
    final out = <ReportAhead>[];
    for (final r in reports) {
      // Cheap straight-line rejection before projecting onto the route.
      if (haversineM(pos, r.pos) > withinM + passedM + 100) continue;
      final p = projectOnRoute(
        r.pos,
        route.points,
        cum,
        fromSeg: seg - 5,
        toSeg: seg + 200,
      );
      if (p.distM > kReportOnRouteM) continue;
      final ahead = p.alongM - alongM;
      if (ahead < -passedM || ahead > withinM) continue;
      out.add(ReportAhead(r, ahead));
    }
    out.sort((a, b) => a.aheadM.compareTo(b.aheadM));
    return out;
  }

  NavState copyWith({
    double? alongM,
    LatLng? pos,
    int? seg,
    bool? arrived,
    bool? rerouting,
    double? offRouteM,
    double? speedKmh,
    double? heading,
  }) => NavState(
    route: route,
    cum: cum,
    alongM: alongM ?? this.alongM,
    pos: pos ?? this.pos,
    seg: seg ?? this.seg,
    arrived: arrived ?? this.arrived,
    rerouting: rerouting ?? this.rerouting,
    offRouteM: offRouteM ?? this.offRouteM,
    speedKmh: speedKmh,
    heading: heading,
  );
}

/// A report lying on the road ahead, and how far along the route it is from us
/// (negative = just passed).
class ReportAhead {
  const ReportAhead(this.report, this.aheadM);
  final Report report;
  final double aheadM;
}

/// Turns GPS fixes into navigation state: progress along the route, snapping,
/// arrival, and re-routing when the driver leaves the route.
class NavNotifier extends Notifier<NavState?> {
  int _offCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  NavState? build() {
    ref.listen(userLocProvider, (_, loc) => _onFix(loc));
    return null;
  }

  void start(RouteOption r) {
    _offCount = 0;
    _lastReroute = DateTime.now();
    state = NavState(
      route: r,
      cum: routeCumulative(r.points),
      alongM: 0,
      pos: r.points.first,
    );
    _onFix(ref.read(userLocProvider));
  }

  void stop() => state = null;

  void _onFix(UserLoc loc) {
    final s = state;
    if (s == null || s.arrived || !loc.isReal) return;
    if ((loc.accuracy ?? 0) > kMaxAccuracyM) return;

    final p = _project(loc.pos, s);
    final onRoute = p.distM <= kOffRouteM;
    final speed = loc.speed;
    final next = s.copyWith(
      alongM: p.alongM,
      seg: p.seg,
      pos: onRoute ? p.snapped : loc.pos,
      offRouteM: p.distM,
      speedKmh: speed == null || speed < 0 ? null : speed * 3.6,
      heading: loc.heading != null && loc.heading! >= 0 ? loc.heading : null,
    );

    final dest = ref.read(destinationProvider);
    final atDestination =
        dest != null && haversineM(loc.pos, dest.pos) <= kArriveM;
    if (atDestination ||
        (next.remainingM <= kArriveM && p.distM <= kOffRouteM)) {
      state = next.copyWith(alongM: s.totalM, arrived: true);
      return;
    }

    state = next;
    _offCount = onRoute ? 0 : _offCount + 1;
    final cooledDown =
        DateTime.now().difference(_lastReroute) > kRerouteCooldown;
    if (!s.rerouting &&
        cooledDown &&
        (p.distM > kHardOffRouteM || _offCount >= 3)) {
      _reroute(loc.pos);
    }
  }

  /// Asks the API for a fresh route from where we are now, keeping the same
  /// route type (fastest / no toll / shortest) the user picked.
  Future<void> _reroute(LatLng from) async {
    final dest = ref.read(destinationProvider);
    final before = state;
    if (dest == null || before == null) return;
    state = before.copyWith(
      rerouting: true,
      speedKmh: before.speedKmh,
      heading: before.heading,
    );
    _lastReroute = DateTime.now();
    try {
      final routes = await Api.routes(
        from,
        dest.pos,
        ref.read(settingsProvider).lang,
      );
      final current = state;
      if (current == null || current.arrived || routes.isEmpty) return;
      final r = routes.firstWhere(
        (r) => before.route.id.isEmpty
            ? r.label == before.route.label
            : r.id == before.route.id,
        orElse: () => routes.first,
      );
      _offCount = 0;
      state = NavState(
        route: r,
        cum: routeCumulative(r.points),
        alongM: 0,
        pos: from,
        speedKmh: current.speedKmh,
        heading: current.heading,
      );
    } catch (_) {
      // Routing unavailable: keep the old route and try again after the cooldown.
      final current = state;
      if (current != null) {
        state = current.copyWith(
          rerouting: false,
          speedKmh: current.speedKmh,
          heading: current.heading,
        );
      }
    }
  }

  /// Projects [p] onto the route polyline. Looks near the current segment first
  /// so routes that cross themselves do not make progress jump around.
  RouteProjection _project(LatLng p, NavState s) {
    final pts = s.route.points;
    final near = projectOnRoute(
      p,
      pts,
      s.cum,
      fromSeg: s.seg - 3,
      toSeg: s.seg + 60,
    );
    if (near.distM <= kOffRouteM) return near;
    final all = projectOnRoute(p, pts, s.cum);
    return all.distM < near.distM ? all : near;
  }
}

final navProvider = NotifierProvider<NavNotifier, NavState?>(NavNotifier.new);

/// Starts turn-by-turn navigation on the selected route. Returns false when
/// there is no real GPS fix yet, because navigation follows the device.
bool startNavigation(WidgetRef ref) {
  if (!ref.read(userLocProvider).isReal) return false;
  final routes = ref.read(routesProvider).value ?? const <RouteOption>[];
  if (routes.isEmpty) return false;
  final r =
      routes[clampRouteIndex(ref.read(routeIndexProvider), routes.length)];
  ref.read(navProvider.notifier).start(r);
  ref.read(navigatingProvider.notifier).set(true);
  return true;
}

void stopNavigation(WidgetRef ref) {
  ref.read(navProvider.notifier).stop();
  ref.read(navigatingProvider.notifier).set(false);
}
