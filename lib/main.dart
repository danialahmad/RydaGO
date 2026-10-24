import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const ProviderScope(child: WazeRevampApp()));

const kBlue = Color(0xFF33CCFF);
const kDark = Color(0xFF1B2430);

DateTime kLastNavEvent = DateTime.fromMillisecondsSinceEpoch(0);

class NavTimeObserver extends NavigatorObserver {
  void _mark() => kLastNavEvent = DateTime.now();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _mark();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _mark();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _mark();
}

class WazeRevampApp extends StatelessWidget {
  const WazeRevampApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Waze Revamp',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: kBlue, useMaterial3: true),
        navigatorObservers: [NavTimeObserver()],
        home: const MapScreen(),
      );
}

enum ReportType {
  police('Polis', Icons.local_police, Colors.indigo),
  accident('Kemalangan', Icons.car_crash, Colors.red),
  jam('Jam', Icons.traffic, Colors.orange),
  hazard('Bahaya', Icons.warning_amber, Colors.amber),
  camera('Kamera', Icons.videocam, Colors.purple),
  closed('Jalan Tutup', Icons.block, Colors.black87);

  const ReportType(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

const kApiUrl =
    String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8081');

const kMapStyle = 'https://tiles.openfreemap.org/styles/liberty';

// Fallback position (KLCC) used until the first real GPS fix, or when location
// is denied or unavailable, so the app stays usable.
const kCenter = LatLng(3.1579, 101.7116);

enum LocStatus { starting, active, denied, unavailable }

class UserLoc {
  const UserLoc(this.status, [this.fix, this.speed, this.heading, this.accuracy]);
  final LocStatus status;
  final LatLng? fix; // last real GPS fix, if any
  final double? speed; // m/s, null if the device cannot tell
  final double? heading; // degrees from north, null if unknown
  final double? accuracy; // metres

  LatLng get pos => fix ?? kCenter;
  bool get isReal => fix != null;
}

class UserLocNotifier extends Notifier<UserLoc> {
  StreamSubscription<Position>? _sub;

  @override
  UserLoc build() {
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(start);
    return const UserLoc(LocStatus.starting);
  }

  bool _demo = false;

  /// Demo mode swaps the device GPS for fixes injected by [DemoDriver], so the
  /// rest of the app (navigation, re-routing, HUD) runs the same code path.
  Future<void> setDemo(bool on) async {
    _demo = on;
    await _sub?.cancel();
    _sub = null;
    if (on) {
      state = const UserLoc(LocStatus.active, kCenter, 0, 0, 5);
    } else {
      state = const UserLoc(LocStatus.starting); // no fix until the real GPS answers
      await start();
    }
  }

  void inject(LatLng p, {double speed = 0, double? heading}) {
    if (!_demo) return;
    state = UserLoc(LocStatus.active, p, speed, heading, 5);
  }

  /// (Re)starts location tracking and asks for permission if needed.
  Future<void> start() async {
    if (_demo) return;
    await _sub?.cancel();
    _sub = null;
    state = UserLoc(LocStatus.starting, state.fix);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = UserLoc(LocStatus.unavailable, state.fix);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        state = UserLoc(LocStatus.denied, state.fix);
        return;
      }
      if (_demo) return; // demo was switched on while we waited for permission
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(
        (p) => state = UserLoc(
          LocStatus.active,
          LatLng(p.latitude, p.longitude),
          p.speed,
          p.heading,
          p.accuracy,
        ),
        onError: (_) => state = UserLoc(LocStatus.unavailable, state.fix),
      );
    } catch (_) {
      state = UserLoc(LocStatus.unavailable, state.fix);
    }
  }
}

final userLocProvider =
    NotifierProvider<UserLocNotifier, UserLoc>(UserLocNotifier.new);

class Report {
  Report(this.type, this.lat, this.lng);
  final ReportType type;
  final double lat;
  final double lng;

  LatLng get pos => LatLng(lat, lng);
}

/// Where the next report will be placed. Null = at the user.
/// Bumped by the "my location" button; the map listens and re-centres.
class RecenterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final recenterProvider = NotifierProvider<RecenterNotifier, int>(RecenterNotifier.new);

class ReportLocationNotifier extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  void set(LatLng? p) => state = p;
}

final reportLocationProvider =
    NotifierProvider<ReportLocationNotifier, LatLng?>(ReportLocationNotifier.new);

class ReportsApi {
  Future<List<Report>> nearby(LatLng around) async {
    final res = await http.get(Uri.parse(
        '$kApiUrl/reports?lat=${around.latitude}&lng=${around.longitude}&radius=20000'));
    if (res.statusCode != 200) throw Exception('GET /reports ${res.statusCode}');
    return [
      for (final j in jsonDecode(res.body) as List)
        Report(
          ReportType.values.byName(j['type'] as String),
          (j['lat'] as num).toDouble(),
          (j['lng'] as num).toDouble(),
        ),
    ];
  }

  Future<Report> create(ReportType t, String token, double lat, double lng) async {
    final res = await http.post(
      Uri.parse('$kApiUrl/reports'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'type': t.name, 'lat': lat, 'lng': lng}),
    );
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode != 201) throw Exception('POST /reports ${res.statusCode}');
    return Report(t, lat, lng);
  }
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

enum AddResult { ok, unauthorized, failed }

class Auth {
  const Auth(this.token, this.email);
  final String token;
  final String email;
}

class AuthNotifier extends Notifier<Auth?> {
  @override
  Auth? build() {
    Future.microtask(_restore);
    return null;
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString('token');
      final e = p.getString('email');
      if (t != null && e != null && state == null) state = Auth(t, e);
    } catch (_) {
      // Storage unavailable: the user just logs in again.
    }
  }

  /// Returns an error message to show, or null on success.
  Future<String?> submit(
      {required bool register,
      required String email,
      required String password}) async {
    try {
      final res = await http.post(
        Uri.parse('$kApiUrl/auth/${register ? 'register' : 'login'}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 && res.statusCode != 201) {
        return body['error'] as String? ?? 'Ralat (${res.statusCode})';
      }
      final auth = Auth(body['token'] as String, body['email'] as String);
      state = auth;
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('token', auth.token);
        await p.setString('email', auth.email);
      } catch (_) {}
      return null;
    } catch (_) {
      return 'Server tak dapat dihubungi';
    }
  }

  Future<void> logout() async {
    state = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('token');
      await p.remove('email');
    } catch (_) {}
  }
}

final authProvider = NotifierProvider<AuthNotifier, Auth?>(AuthNotifier.new);

class ReportsNotifier extends Notifier<List<Report>> {
  final _api = ReportsApi();

  @override
  List<Report> build() {
    Future.microtask(refresh);
    final timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    ref.onDispose(timer.cancel);
    // The first real fix moves us away from the fallback: reload around it.
    ref.listen(userLocProvider, (prev, next) {
      if (prev?.isReal != next.isReal) refresh();
    });
    return const [];
  }

  Future<void> refresh() async {
    try {
      state = await _api.nearby(ref.read(userLocProvider).pos);
    } catch (_) {
      // Keep whatever we had; the next refresh will retry.
    }
  }

  Future<AddResult> add(ReportType t) async {
    final token = ref.read(authProvider)?.token;
    if (token == null) return AddResult.unauthorized;
    final at = ref.read(reportLocationProvider) ?? ref.read(userLocProvider).pos;
    try {
      final r = await _api.create(t, token, at.latitude, at.longitude);
      state = [...state, r];
      ref.read(reportLocationProvider.notifier).set(null);
      return AddResult.ok;
    } on UnauthorizedException {
      return AddResult.unauthorized;
    } catch (_) {
      return AddResult.failed;
    }
  }
}

final reportsProvider =
    NotifierProvider<ReportsNotifier, List<Report>>(ReportsNotifier.new);

class NavigatingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final navigatingProvider =
    NotifierProvider<NavigatingNotifier, bool>(NavigatingNotifier.new);

class Place {
  const Place(this.name, this.area, this.icon, this.pos);
  final String name;
  final String area;
  final IconData icon;
  final LatLng pos;

  Map<String, dynamic> toJson() => {
        'name': name,
        'area': area,
        'lat': pos.latitude,
        'lng': pos.longitude,
      };

  static Place fromJson(Map<String, dynamic> j) => Place(
        j['name'] as String,
        j['area'] as String,
        Icons.history,
        LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      );
}

IconData _iconFor(String category, String type) {
  if (category == 'aeroway') return Icons.flight;
  if (category == 'railway' || category == 'public_transport') return Icons.train;
  if (category == 'shop' || type == 'mall' || type == 'marketplace') {
    return Icons.shopping_bag;
  }
  if (category == 'tourism') return Icons.landscape;
  if (category == 'highway') return Icons.add_road;
  if (category == 'place' || category == 'boundary') return Icons.location_city;
  switch (type) {
    case 'restaurant':
    case 'cafe':
    case 'fast_food':
      return Icons.restaurant;
    case 'fuel':
      return Icons.local_gas_station;
    case 'school':
    case 'university':
    case 'college':
      return Icons.school;
    case 'hospital':
    case 'clinic':
      return Icons.local_hospital;
    case 'place_of_worship':
      return Icons.mosque;
    case 'parking':
      return Icons.local_parking;
  }
  return Icons.place;
}

/// Address search through our API (Nominatim), biased towards the user.
Future<List<Place>> searchPlaces(String q, LatLng near) async {
  final uri = Uri.parse('$kApiUrl/places').replace(queryParameters: {
    'q': q,
    'lat': '${near.latitude}',
    'lng': '${near.longitude}',
  });
  final res = await http.get(uri);
  if (res.statusCode != 200) throw Exception('GET /places ${res.statusCode}');
  return [
    for (final j in jsonDecode(res.body) as List)
      Place(
        j['name'] as String,
        j['area'] as String,
        _iconFor(j['category'] as String, j['type'] as String),
        LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      ),
  ];
}

/// Last few destinations, kept on the device.
class RecentsNotifier extends Notifier<List<Place>> {
  @override
  List<Place> build() {
    Future.microtask(_load);
    return const [];
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('recents');
      if (raw == null) return;
      state = [
        for (final j in jsonDecode(raw) as List)
          Place.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      // Missing or corrupt storage: start with no recents.
    }
  }

  Future<void> add(Place p) async {
    bool same(Place o) =>
        o.name == p.name &&
        (o.pos.latitude - p.pos.latitude).abs() < 0.0005 &&
        (o.pos.longitude - p.pos.longitude).abs() < 0.0005;
    state = [p, ...state.where((o) => !same(o))].take(5).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'recents', jsonEncode([for (final r in state) r.toJson()]));
    } catch (_) {}
  }
}

final recentsProvider =
    NotifierProvider<RecentsNotifier, List<Place>>(RecentsNotifier.new);

class Maneuver {
  const Maneuver(this.text, this.type, this.km, this.index);
  final String text;
  final int type; // Valhalla maneuver type, mapped to an icon in the UI
  final double km;
  final int index; // index into RouteOption.points where this step begins
}

class RouteOption {
  const RouteOption(this.label, this.minutes, this.km, this.note, this.points,
      this.maneuvers);
  final String label;
  final int minutes;
  final double km;
  final String note;
  final List<LatLng> points;
  final List<Maneuver> maneuvers;
}

Future<List<RouteOption>> fetchRoutes(LatLng from, Place dest) async {
  final res = await http.get(Uri.parse(
      '$kApiUrl/route?from=${from.latitude},${from.longitude}'
      '&to=${dest.pos.latitude},${dest.pos.longitude}'));
  if (res.statusCode != 200) throw Exception('GET /route ${res.statusCode}');
  return [
    for (final j in jsonDecode(res.body) as List)
      RouteOption(
        j['label'] as String,
        j['minutes'] as int,
        (j['km'] as num).toDouble(),
        j['note'] as String,
        [
          for (final p in j['points'] as List)
            LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        [
          for (final m in j['maneuvers'] as List)
            Maneuver(
              m['text'] as String,
              m['type'] as int,
              (m['km'] as num).toDouble(),
              m['index'] as int,
            ),
        ],
      ),
  ];
}

/// Real routes from the backend (Valhalla). Empty while no destination is set.
final routesProvider = FutureProvider<List<RouteOption>>((ref) async {
  final dest = ref.watch(destinationProvider);
  // read, not watch: GPS updates must not refetch the routes mid-trip.
  return dest == null
      ? const []
      : fetchRoutes(ref.read(userLocProvider).pos, dest);
});

// Navigation thresholds (metres unless noted).
const kOffRouteM = 50.0; // further than this from the route counts as off it
const kHardOffRouteM = 120.0; // so far off that we re-route straight away
const kArriveM = 30.0;
const kMaxAccuracyM = 100.0; // ignore fixes less precise than this
const kRerouteCooldown = Duration(seconds: 8);

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

  NavState copyWith({
    double? alongM,
    LatLng? pos,
    int? seg,
    bool? arrived,
    bool? rerouting,
    double? offRouteM,
    double? speedKmh,
    double? heading,
  }) =>
      NavState(
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

class _Projection {
  const _Projection(this.seg, this.alongM, this.distM, this.snapped);
  final int seg;
  final double alongM;
  final double distM;
  final LatLng snapped;
}

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
        route: r, cum: routeCumulative(r.points), alongM: 0, pos: r.points.first);
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
    final atDestination = dest != null && haversineM(loc.pos, dest.pos) <= kArriveM;
    if (atDestination || (next.remainingM <= kArriveM && p.distM <= kOffRouteM)) {
      state = next.copyWith(alongM: s.totalM, arrived: true);
      return;
    }

    state = next;
    _offCount = onRoute ? 0 : _offCount + 1;
    final cooledDown = DateTime.now().difference(_lastReroute) > kRerouteCooldown;
    if (!s.rerouting && cooledDown && (p.distM > kHardOffRouteM || _offCount >= 3)) {
      _reroute(loc.pos);
    }
  }

  /// Asks the API for a fresh route from where we are now, keeping the same
  /// route type (fastest / no toll / shortest) the user picked.
  Future<void> _reroute(LatLng from) async {
    final dest = ref.read(destinationProvider);
    final before = state;
    if (dest == null || before == null) return;
    state = before.copyWith(rerouting: true, speedKmh: before.speedKmh, heading: before.heading);
    _lastReroute = DateTime.now();
    try {
      final routes = await fetchRoutes(from, dest);
      final current = state;
      if (current == null || current.arrived || routes.isEmpty) return;
      final r = routes.firstWhere((r) => r.label == before.route.label,
          orElse: () => routes.first);
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
            rerouting: false, speedKmh: current.speedKmh, heading: current.heading);
      }
    }
  }

  /// Projects [p] onto the route polyline. Looks near the current segment first
  /// so routes that cross themselves do not make progress jump around.
  _Projection _project(LatLng p, NavState s) {
    final pts = s.route.points;
    final cum = s.cum;
    final mLat = 110540.0;
    final mLng = 111320.0 * math.cos(p.latitude * math.pi / 180);

    _Projection scan(int from, int to) {
      _Projection? best;
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
          best = _Projection(
            i,
            cum[i] + t * (cum[i + 1] - cum[i]),
            d,
            LatLng(p.latitude + cy / mLat, p.longitude + cx / mLng),
          );
        }
      }
      return best!;
    }

    final last = pts.length - 2; // index of the last segment
    final near = scan(math.max(0, s.seg - 3), math.min(last, s.seg + 60));
    if (near.distM <= kOffRouteM) return near;
    final all = scan(0, last);
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
  final r = routes[math.min(ref.read(routeIndexProvider), routes.length - 1)];
  ref.read(navProvider.notifier).start(r);
  ref.read(navigatingProvider.notifier).set(true);
  return true;
}

void stopNavigation(WidgetRef ref) {
  ref.read(navProvider.notifier).stop();
  ref.read(navigatingProvider.notifier).set(false);
}

// ---- Demo mode: drive the route without moving, via the normal GPS pipeline ----

const kDemoSpeedMps = 50 / 3.6; // reported speed (~50 km/h)
const kDemoSpeedUp = 10.0; // how much faster than real time the demo moves

class DemoNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(userLocProvider.notifier).setDemo(on);
    ref.read(recenterProvider.notifier).bump();
  }
}

final demoProvider = NotifierProvider<DemoNotifier, bool>(DemoNotifier.new);

/// While demo mode and navigation are both on, injects a fix every 500 ms that
/// moves along the route being followed. Nothing here talks to NavNotifier
/// directly: navigation just sees GPS fixes, exactly like a real drive.
class DemoDriver extends Notifier<void> {
  Timer? _timer;
  RouteOption? _route;
  List<double> _cum = const [];
  double _along = 0;
  LatLng? _detour; // while set, hold this off-route spot until we are re-routed

  @override
  void build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(navProvider, (_, nav) {
      if (nav == null) {
        _stop();
      } else if (ref.read(demoProvider) && _timer == null) {
        _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
      }
    });
    ref.listen(demoProvider, (_, on) {
      if (!on) _stop();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _route = null;
    _detour = null;
  }

  /// Jumps ~270 m off the route to show re-routing.
  void detour() {
    final nav = ref.read(navProvider);
    if (nav == null || nav.arrived || !ref.read(demoProvider)) return;
    final p = LatLng(nav.pos.latitude + 0.0025, nav.pos.longitude + 0.0004);
    _detour = p;
    ref.read(userLocProvider.notifier).inject(p, speed: kDemoSpeedMps, heading: 90);
  }

  void _tick() {
    final nav = ref.read(navProvider);
    if (nav == null || nav.arrived || !ref.read(demoProvider)) return;
    final user = ref.read(userLocProvider.notifier);

    if (!identical(nav.route, _route)) {
      // First tick, or we were re-routed: start from the beginning of this route.
      _route = nav.route;
      _cum = routeCumulative(nav.route.points);
      _along = 0;
      _detour = null;
    }
    final detour = _detour;
    if (detour != null) {
      user.inject(detour, speed: kDemoSpeedMps, heading: 90);
      return;
    }

    final pts = nav.route.points;
    _along = math.min(_cum.last, _along + kDemoSpeedMps * 0.5 * kDemoSpeedUp);
    var i = 1;
    while (i < _cum.length - 1 && _cum[i] < _along) {
      i++;
    }
    final seg = _cum[i] - _cum[i - 1];
    final t = seg <= 0 ? 0.0 : ((_along - _cum[i - 1]) / seg).clamp(0.0, 1.0);
    final a = pts[i - 1], b = pts[i];
    final pos = LatLng(a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t);
    final dLng = (b.longitude - a.longitude) * math.cos(a.latitude * math.pi / 180);
    final heading =
        (math.atan2(dLng, b.latitude - a.latitude) * 180 / math.pi + 360) % 360;
    user.inject(pos, speed: kDemoSpeedMps, heading: heading);
  }
}

final demoDriverProvider = NotifierProvider<DemoDriver, void>(DemoDriver.new);

class DestinationNotifier extends Notifier<Place?> {
  @override
  Place? build() => null;

  void set(Place? p) => state = p;
}

final destinationProvider =
    NotifierProvider<DestinationNotifier, Place?>(DestinationNotifier.new);

class RouteIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int i) => state = i;
}

final routeIndexProvider =
    NotifierProvider<RouteIndexNotifier, int>(RouteIndexNotifier.new);

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigating = ref.watch(navigatingProvider);
    ref.watch(demoDriverProvider); // keeps the demo driver alive
    final dest = ref.watch(destinationProvider);
    final pickedLocation = ref.watch(reportLocationProvider);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: RealMap()),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: navigating
                    ? const _TurnBanner()
                    : _SearchBar(
                        label: dest?.name ?? 'Nak pergi mana?',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SearchScreen()),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: dest != null && !navigating ? 400 : 200,
            child: FloatingActionButton(
              heroTag: 'report',
              backgroundColor: kBlue,
              onPressed: () {
                if (ref.read(authProvider) == null) {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LoginScreen()));
                } else {
                  _showReportSheet(context, ref);
                }
              },
              child: const Icon(Icons.add_alert, color: Colors.white),
            ),
          ),
          if (!navigating)
            Positioned(
              right: 12,
              bottom: (dest != null ? 400 : 200) + 72,
              child: FloatingActionButton.small(
                heroTag: 'locate',
                backgroundColor: Colors.white,
                tooltip: 'Lokasi saya',
                onPressed: () {
                  final loc = ref.read(userLocProvider);
                  if (loc.status == LocStatus.denied ||
                      loc.status == LocStatus.unavailable) {
                    // Ask again: the user may have allowed location since.
                    ref.read(userLocProvider.notifier).start();
                  }
                  ref.read(recenterProvider.notifier).bump();
                },
                child: const Icon(Icons.my_location, color: kBlue),
              ),
            ),
          if (!navigating)
            const Positioned(left: 12, top: 96, child: SafeArea(child: _AccountButton())),
          if (!navigating)
            const Positioned(left: 12, top: 156, child: SafeArea(child: _LocStatusChip())),
          if (!navigating && pickedLocation != null)
            Positioned(
              right: 12,
              top: 96,
              child: SafeArea(
                child: InputChip(
                  avatar: const Icon(Icons.place, color: Colors.deepPurple),
                  label: const Text('Report di lokasi dipilih'),
                  backgroundColor: Colors.white,
                  onDeleted: () =>
                      ref.read(reportLocationProvider.notifier).set(null),
                ),
              ),
            ),
          if (navigating) ...[
            const Positioned(left: 12, bottom: 130, child: _SpeedHud()),
            const Positioned(
                left: 12, right: 12, top: 130, child: _HazardAlert()),
          ],
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: navigating
                ? const _EtaCard()
                : dest == null
                    ? const _HomeCard()
                    : const _RouteOptionsCard(),
          ),
        ],
      ),
    );
  }

  void _showReportSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 20,
          children: [
            for (final t in ReportType.values)
              InkWell(
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);
                  nav.pop();
                  final res = await ref.read(reportsProvider.notifier).add(t);
                  switch (res) {
                    case AddResult.ok:
                      messenger.showSnackBar(SnackBar(
                          content: Text('Report ${t.label} dihantar')));
                    case AddResult.unauthorized:
                      await ref.read(authProvider.notifier).logout();
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Sesi tamat. Sila log masuk semula.')));
                      nav.push(MaterialPageRoute(
                          builder: (_) => const LoginScreen()));
                    case AddResult.failed:
                      messenger.showSnackBar(const SnackBar(
                          content: Text(
                              'Gagal hantar report. Server tak dapat dihubungi.')));
                  }
                },
                child: SizedBox(
                  width: 90,
                  child: Column(children: [
                    CircleAvatar(
                        radius: 28,
                        backgroundColor: t.color,
                        child: Icon(t.icon, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(t.label),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(children: [
              const Icon(Icons.search),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
              const Icon(Icons.mic),
            ]),
          ),
        ),
      );
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  String _query = '';
  List<Place> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0; // lets us drop responses that arrive out of order

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    final seq = ++_seq;
    if (q.length < 2) {
      setState(() {
        _query = q;
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await searchPlaces(q, ref.read(userLocProvider).pos);
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = r;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = const [];
          _loading = false;
          _error = 'Carian tak dapat dihubungi. Cuba lagi sebentar.';
        });
      }
    });
  }

  void _pick(Place p) {
    ref.read(recentsProvider.notifier).add(p);
    ref.read(destinationProvider.notifier).set(p);
    ref.read(routeIndexProvider.notifier).set(0);
    Navigator.of(context).pop();
  }

  Widget _tile(Place p, {bool recent = false}) => ListTile(
        leading: CircleAvatar(child: Icon(recent ? Icons.history : p.icon)),
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: p.area.isEmpty
            ? null
            : Text(p.area, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _pick(p),
      );

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(recentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
              hintText: 'Cari alamat atau tempat', border: InputBorder.none),
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (_query.length < 2) ...[
            if (recents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Taip nama tempat, jalan atau alamat.'),
              )
            else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Terbaru',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final p in recents) _tile(p, recent: true),
            ],
          ] else if (_results.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Tiada hasil dijumpai')),
            )
          else
            for (final p in _results) _tile(p),
        ],
      ),
    );
  }
}

IconData _maneuverIcon(int type) {
  switch (type) {
    case 1:
    case 2:
    case 3:
      return Icons.navigation;
    case 4:
    case 5:
    case 6:
      return Icons.flag;
    case 9:
      return Icons.turn_slight_right;
    case 10:
      return Icons.turn_right;
    case 11:
      return Icons.turn_sharp_right;
    case 12:
      return Icons.u_turn_right;
    case 13:
      return Icons.u_turn_left;
    case 14:
      return Icons.turn_sharp_left;
    case 15:
      return Icons.turn_left;
    case 16:
      return Icons.turn_slight_left;
    case 18:
    case 20:
    case 23:
      return Icons.fork_right;
    case 19:
    case 21:
    case 24:
      return Icons.fork_left;
    case 25:
      return Icons.merge;
    case 26:
    case 27:
      return Icons.roundabout_right;
  }
  return Icons.straight;
}

String _formatDist(double m) {
  if (m < 1000) return '${(m / 10).round() * 10} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

class _TurnBanner extends ConsumerWidget {
  const _TurnBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navProvider);
    final m = nav?.upcoming;
    if (nav == null || m == null) return const SizedBox.shrink();
    final rerouting = nav.rerouting;
    return Material(
      color: kDark,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(rerouting ? Icons.sync : _maneuverIcon(m.type),
              color: Colors.white, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rerouting)
                  const Text('Mengira semula laluan...',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold))
                else ...[
                  if (!nav.arrived)
                    Text(_formatDist(nav.distToUpcomingM),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                  Text(m.text,
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: nav.arrived ? 18 : 14)),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Says why the blue dot is not on the user's real position.
class _LocStatusChip extends ConsumerWidget {
  const _LocStatusChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(userLocProvider);
    if (ref.watch(demoProvider)) {
      return Material(
        elevation: 2,
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.science, size: 16, color: Colors.black54),
            SizedBox(width: 6),
            Text('Mod demo: lokasi dan pemanduan palsu',
                style: TextStyle(fontSize: 12)),
          ]),
        ),
      );
    }
    if (loc.isReal) return const SizedBox.shrink();
    final text = switch (loc.status) {
      LocStatus.starting => 'Mencari lokasi anda...',
      LocStatus.denied => 'Lokasi tak dibenarkan. Guna lokasi contoh (KLCC)',
      LocStatus.unavailable => 'GPS tak tersedia. Guna lokasi contoh (KLCC)',
      LocStatus.active => 'Menunggu isyarat GPS...',
    };
    return Material(
      elevation: 2,
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            loc.status == LocStatus.starting
                ? Icons.gps_not_fixed
                : Icons.location_off,
            size: 16,
            color: Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: auth == null ? Colors.white : kBlue,
      child: IconButton(
        tooltip: auth == null ? 'Log masuk' : auth.email,
        icon: Icon(Icons.person, color: auth == null ? Colors.black54 : Colors.white),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _AccountDialog(),
        ),
      ),
    );
  }
}

class _AccountDialog extends ConsumerWidget {
  const _AccountDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final demo = ref.watch(demoProvider);
    return AlertDialog(
      title: const Text('Akaun'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(auth?.email ?? 'Belum log masuk'),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mod demo pemanduan'),
            subtitle: const Text(
                'Lokasi palsu bergerak di sepanjang laluan. GPS sebenar diabaikan.'),
            value: demo,
            onChanged: (v) => ref.read(demoProvider.notifier).set(v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        if (auth == null)
          FilledButton(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: const Text('Log masuk'),
          )
        else
          FilledButton(
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              Navigator.pop(context);
            },
            child: const Text('Log keluar'),
          ),
      ],
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(authProvider.notifier).submit(
          register: _register,
          email: _email.text.trim(),
          password: _password.text,
        );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_register ? 'Daftar akaun' : 'Log masuk')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Log masuk untuk hantar report jalan raya.',
                  style: TextStyle(fontSize: 15)),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                    labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Kata laluan',
                  helperText: _register ? 'Sekurang-kurangnya 8 aksara' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_register ? 'Daftar' : 'Log masuk'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _register = !_register;
                          _error = null;
                        }),
                child: Text(_register
                    ? 'Dah ada akaun? Log masuk'
                    : 'Belum ada akaun? Daftar'),
              ),
            ],
          ),
        ),
      );
}

class _SpeedHud extends ConsumerWidget {
  const _SpeedHud();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kmh = ref.watch(navProvider)?.speedKmh;
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: kDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Text(kmh == null ? '--' : '${kmh.round()}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        const Text('km/j',
            style: TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}

/// Warns about the nearest community report close to the simulated position.
class _HazardAlert extends ConsumerWidget {
  const _HazardAlert();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sim = ref.watch(navProvider);
    if (sim == null || sim.arrived) return const SizedBox.shrink();
    Report? nearest;
    var best = 800.0;
    for (final r in ref.watch(reportsProvider)) {
      final d = haversineM(sim.pos, r.pos);
      if (d < best) {
        best = d;
        nearest = r;
      }
    }
    if (nearest == null) return const SizedBox.shrink();
    return Material(
      color: kDark,
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Icon(nearest.type.icon, color: nearest.type.color == Colors.black87
              ? Colors.white
              : nearest.type.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${nearest.type.label} ${_formatDist(best)} berhampiran',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard();

  @override
  Widget build(BuildContext context) => const _Sheet(
        child: Row(children: [
          Icon(Icons.explore, color: kBlue, size: 32),
          SizedBox(width: 12),
          Expanded(
            child: Text('Tekan bar carian untuk pilih destinasi',
                style: TextStyle(fontSize: 16)),
          ),
        ]),
      );
}

class _RouteOptionsCard extends ConsumerWidget {
  const _RouteOptionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dest = ref.watch(destinationProvider)!;
    final async = ref.watch(routesProvider);
    final routes = async.isLoading ? const <RouteOption>[] : (async.value ?? const <RouteOption>[]);
    final selected = routes.isEmpty
        ? 0
        : math.min(ref.watch(routeIndexProvider), routes.length - 1);
    return _Sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${dest.name}, ${dest.area}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: () => ref.read(destinationProvider.notifier).set(null),
              icon: const Icon(Icons.close),
            ),
          ]),
          if (async.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Mencari laluan...'),
                ]),
              ),
            )
          else if (async.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                const Expanded(
                    child: Text('Laluan tak dapat dimuatkan. Server routing mungkin belum sedia.')),
                TextButton(
                  onPressed: () => ref.invalidate(routesProvider),
                  child: const Text('Cuba lagi'),
                ),
              ]),
            )
          else
            for (var i = 0; i < routes.length; i++)
              _RouteTile(
                route: routes[i],
                selected: i == selected,
                onTap: () => ref.read(routeIndexProvider.notifier).set(i),
              ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: routes.isEmpty
                  ? null
                  : () {
                      if (!startNavigation(ref)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Navigasi perlukan GPS. Benarkan akses lokasi dan cuba lagi.'),
                        ));
                      }
                    },
              icon: const Icon(Icons.navigation),
              label: const Text('Mula'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile(
      {required this.route, required this.selected, required this.onTap});
  final RouteOption route;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected ? kBlue : Colors.black12,
                  width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Text('${route.minutes} min',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(route.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${route.km} km · ${route.note}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: kBlue),
            ]),
          ),
        ),
      );
}

class _EtaCard extends ConsumerWidget {
  const _EtaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sim = ref.watch(navProvider);
    if (sim == null) return const SizedBox.shrink();
    final dest = ref.watch(destinationProvider);
    void finish() {
      stopNavigation(ref);
      ref.read(destinationProvider.notifier).set(null);
    }

    return _Sheet(
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sim.arrived ? 'Anda telah sampai' : '${sim.remainingMin} min',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
              Text(
                sim.arrived
                    ? (dest?.name ?? '')
                    : sim.rerouting
                        ? 'Mengira semula laluan...'
                        : '${(sim.remainingM / 1000).toStringAsFixed(1)} km · ${sim.route.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (!sim.arrived && ref.watch(demoProvider))
          TextButton.icon(
            onPressed: ref.read(demoDriverProvider.notifier).detour,
            icon: const Icon(Icons.alt_route),
            label: const Text('Lencong'),
          ),
        if (sim.arrived)
          FilledButton(onPressed: finish, child: const Text('Selesai'))
        else
          IconButton.filledTonal(
            onPressed: finish,
            icon: const Icon(Icons.close),
          ),
      ]),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
        ),
        child: child,
      );
}

Future<Uint8List> _renderMarker(IconData icon, Color bg, {double px = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final centre = Offset(px / 2, px / 2);
  canvas.drawCircle(centre, px / 2, Paint()..color = Colors.white);
  canvas.drawCircle(centre, px / 2 - 6, Paint()..color = bg);
  final glyph = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: px * 0.52,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
  )..layout();
  glyph.paint(canvas, centre - Offset(glyph.width / 2, glyph.height / 2));
  final image = await recorder.endRecording().toImage(px.toInt(), px.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// OpenFreeMap vector map with our overlays (reports, user, destination,
/// routes) redrawn whenever the underlying state changes.
class RealMap extends ConsumerStatefulWidget {
  const RealMap({super.key});

  @override
  ConsumerState<RealMap> createState() => _RealMapState();
}

class _RealMapState extends ConsumerState<RealMap> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _syncing = false;
  bool _dirty = false;
  Circle? _userCircle;
  bool _centeredOnFix = false;
  bool _imagesReady = false;

  /// Draws each marker (white ring, coloured disc, white Material icon) into a
  /// PNG and registers it with the map so reports can be shown as symbols.
  Future<void> _registerImages(MapLibreMapController c) async {
    try {
      for (final t in ReportType.values) {
        await c.addImage('report-${t.name}', await _renderMarker(t.icon, t.color));
      }
      await c.addImage('marker-dest', await _renderMarker(Icons.flag, Colors.red));
      await c.addImage(
          'marker-picked', await _renderMarker(Icons.place, Colors.deepPurple));
      await c.setSymbolIconAllowOverlap(true);
      _imagesReady = true;
    } catch (_) {
      _imagesReady = false; // _draw falls back to circles
    }
  }

  Future<void> _sync() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _dirty = false;
        await _draw(c);
      } while (_dirty);
    } catch (_) {
      // Map was disposed mid-draw; nothing to do.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _draw(MapLibreMapController c) async {
    final reports = ref.read(reportsProvider);
    final picked = ref.read(reportLocationProvider);
    final dest = ref.read(destinationProvider);
    final routesAsync = ref.read(routesProvider);
    final routes = routesAsync.isLoading
        ? const <RouteOption>[]
        : (routesAsync.value ?? const <RouteOption>[]);
    final selected = routes.isEmpty
        ? 0
        : math.min(ref.read(routeIndexProvider), routes.length - 1);
    final navigating = ref.read(navigatingProvider);
    // While navigating we draw the route being followed, which changes on re-route.
    final navRoute = navigating ? ref.read(navProvider)?.route : null;

    await c.clearLines();
    await c.clearCircles();

    if (dest != null && (navRoute != null || routes.isNotEmpty)) {
      for (var i = 0; i < routes.length; i++) {
        if (i == selected || navigating) continue;
        await c.addLine(LineOptions(
          geometry: routes[i].points,
          lineColor: '#90A4AE',
          lineWidth: 5,
          lineOpacity: 0.9,
        ));
      }
      await c.addLine(LineOptions(
        geometry: (navRoute ?? routes[selected]).points,
        lineColor: _hex(kBlue),
        lineWidth: 7,
      ));
    }

    CircleOptions dot(LatLng p, Color color, double radius) => CircleOptions(
          geometry: p,
          circleColor: _hex(color),
          circleRadius: radius,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2.5,
        );

    final showPicked = picked != null && !navigating;
    if (_imagesReady) {
      await c.clearSymbols();
      await c.addSymbols([
        for (final r in reports)
          SymbolOptions(
              geometry: r.pos, iconImage: 'report-${r.type.name}', iconSize: 0.42),
        if (dest != null)
          SymbolOptions(geometry: dest.pos, iconImage: 'marker-dest', iconSize: 0.42),
        if (showPicked)
          SymbolOptions(geometry: picked, iconImage: 'marker-picked', iconSize: 0.5),
      ]);
    } else {
      // Icon images failed to build: fall back to plain coloured dots.
      await c.addCircles([
        for (final r in reports) dot(r.pos, r.type.color, 11),
        if (dest != null) dot(dest.pos, Colors.red, 10),
        if (showPicked) dot(picked, Colors.deepPurple, 12),
      ]);
    }
    // Kept as a handle so the simulated drive can move it without a full redraw.
    _userCircle =
        await c.addCircle(dot(_userPos, kBlue, 9));

    // The first GPS fix can arrive before the map is ready; centre once now.
    if (!_centeredOnFix &&
        ref.read(userLocProvider).isReal &&
        dest == null &&
        !navigating) {
      _centeredOnFix = true;
      await c.animateCamera(CameraUpdate.newLatLngZoom(_userPos, 14));
    }
  }

  /// The drive simulation overrides the real position while navigating.
  LatLng get _userPos =>
      ref.read(navProvider)?.pos ?? ref.read(userLocProvider).pos;

  Future<void> _onUserLoc(UserLoc? prev, UserLoc next) async {
    if (ref.read(navProvider) != null) return; // the simulation owns the dot
    final c = _controller, uc = _userCircle;
    if (c == null || uc == null) return;
    try {
      await c.updateCircle(uc, CircleOptions(geometry: next.pos));
      // First real fix: jump there once, unless the user is already planning.
      final firstFix = next.isReal && !_centeredOnFix;
      if (firstFix && ref.read(destinationProvider) == null) {
        _centeredOnFix = true;
        await c.animateCamera(CameraUpdate.newLatLngZoom(next.pos, 14));
      }
    } catch (_) {
      // Cosmetic; the next fix tries again.
    }
  }

  Future<void> _recenter() async {
    if (ref.read(navigatingProvider)) return;
    try {
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(_userPos, 15));
    } catch (_) {}
  }

  double _bearing = 0;

  /// Moves the blue dot and keeps the camera on it, turned to the direction of
  /// travel while we are actually moving (GPS heading is noise when standing still).
  Future<void> _follow(NavState n) async {
    final c = _controller;
    if (c == null) return;
    if ((n.speedKmh ?? 0) > 5 && n.heading != null) _bearing = n.heading!;
    try {
      final uc = _userCircle;
      if (uc != null) await c.updateCircle(uc, CircleOptions(geometry: n.pos));
      await c.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: n.pos, zoom: 16, bearing: _bearing)));
    } catch (_) {
      // Cosmetic; the next fix tries again.
    }
  }

  Future<void> _fitDestination(Place? dest) async {
    final c = _controller;
    if (c == null) return;
    if (dest == null) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(_userPos, 14));
      return;
    }
    // newLatLngBounds with padding behaves differently on web (padding is
    // scaled by the device pixel ratio), so compute centre and zoom ourselves.
    // The route should sit in the part of the screen the bottom sheet leaves free.
    double rad(double d) => d * math.pi / 180;
    final a = _userPos, b = dest.pos;
    final midLat = (a.latitude + b.latitude) / 2;
    final midLng = (a.longitude + b.longitude) / 2;
    final worldKm = 40075.0 * math.cos(rad(midLat));
    final dLatKm = (a.latitude - b.latitude).abs() * 111.0;
    final dLngKm = (a.longitude - b.longitude).abs() * 111.0 * math.cos(rad(midLat));
    final spanKm = math.max(math.max(dLatKm, dLngKm), 1.0);
    const fitPx = 280.0;
    final zoom = (math.log(worldKm * fitPx / (512 * spanKm)) / math.ln2)
        .clamp(3.0, 16.0);
    final kmPerPx = worldKm / (512 * math.pow(2, zoom));
    const sheetShiftPx = 150.0; // lift the route above the bottom sheet
    final centerLat = midLat - sheetShiftPx * kmPerPx / 111.0;
    try {
      await c.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(centerLat, midLng), zoom));
    } catch (_) {
      // Camera moves are cosmetic; ignore failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reportsProvider, (_, _) => _sync());
    ref.listen(reportLocationProvider, (_, _) => _sync());
    ref.listen(routeIndexProvider, (_, _) => _sync());
    ref.listen(routesProvider, (_, _) => _sync());
    ref.listen(navProvider, (prev, next) {
      if (next == null) return;
      // A re-route swaps the route object: redraw the blue line.
      if (!identical(prev?.route, next.route)) _sync();
      _follow(next);
    });
    ref.listen(userLocProvider, _onUserLoc);
    ref.listen(recenterProvider, (_, _) => _recenter());
    ref.listen(destinationProvider, (_, next) {
      _sync();
      _fitDestination(next);
    });
    ref.listen(navigatingProvider, (_, nav) {
      _sync();
      if (nav) {
        _controller?.animateCamera(CameraUpdate.newLatLngZoom(_userPos, 16));
      } else {
        _bearing = 0;
        _controller?.animateCamera(CameraUpdate.bearingTo(0));
        _fitDestination(ref.read(destinationProvider));
      }
    });

    // Only a pointer-down that really lands on the map reaches this Listener;
    // buttons and sheets above it absorb theirs. On web the browser's "click"
    // that follows a vanishing widget (e.g. closing a card) would otherwise hit
    // the map below and drop a ghost pin.
    return Listener(
      onPointerDown: (_) => _lastMapDown = DateTime.now(),
      child: _buildMap(),
    );
  }

  DateTime _lastMapDown = DateTime.fromMillisecondsSinceEpoch(0);

  Widget _buildMap() {
    return MapLibreMap(
      styleString: kMapStyle,
      initialCameraPosition: const CameraPosition(target: kCenter, zoom: 13),
      compassEnabled: false,
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: () async {
        final c = _controller;
        if (c != null) await _registerImages(c);
        _styleReady = true;
        _sync();
      },
      onMapClick: (_, latLng) {
        // On web, the browser "click" that follows closing a sheet, dialog or
        // page lands on the map underneath. Ignore clicks right after any
        // navigator event so dismissing UI never drops a pin.
        final now = DateTime.now();
        if (now.difference(kLastNavEvent) < const Duration(milliseconds: 600)) {
          return;
        }
        if (now.difference(_lastMapDown) > const Duration(milliseconds: 1500)) {
          return; // the press did not start on the map: a ghost click
        }
        if (!ref.read(navigatingProvider)) {
          ref.read(reportLocationProvider.notifier).set(latLng);
        }
      },
    );
  }
}
