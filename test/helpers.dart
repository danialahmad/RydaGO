import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:waze_revamp/models/geo.dart';
import 'package:waze_revamp/models/route.dart';
import 'package:waze_revamp/models/user_loc.dart';
import 'package:waze_revamp/state/navigation.dart';
import 'package:waze_revamp/state/user_loc.dart';

/// A location provider that never touches the geolocator plugin, so tests can
/// feed navigation exactly the GPS fixes they want.
class FakeUserLoc extends UserLocNotifier {
  @override
  UserLoc build() => const UserLoc(LocStatus.active, LatLng(3.0, 101.0), 0, 90, 5);

  void emit(UserLoc loc) => state = loc;
}

/// A straight, 11-point route running east along lat 3.0: ~111 m between points,
/// ~1.11 km in total, with a start, a turn halfway and an arrival.
RouteOption straightRoute() => RouteOption(
      'Terpantas',
      5,
      1.1,
      'Laluan terpantas',
      [for (var i = 0; i <= 10; i++) LatLng(3.0, 101.0 + i * 0.001)],
      const [
        Maneuver('Mulakan perjalanan di Jalan A', 1, 0.55, 0, street: 'Jalan A'),
        Maneuver('Belok kanan menuju Jalan B', 10, 0.55, 5, street: 'Jalan B'),
        Maneuver('Anda telah sampai', 4, 0, 10),
      ],
      via: 'Jalan B',
      // Known limit on the first 4 segments only (~0 to 444 m); the rest is unmapped.
      limits: const [SpeedLimit(0, 4, 60)],
    );

UserLoc fix(double lat, double lng, {double? speed, double accuracy = 5}) =>
    UserLoc(LocStatus.active, LatLng(lat, lng), speed, 90, accuracy);

/// A NavState at [alongM] metres along [route], for tests that only need the model.
/// The position and segment follow from [alongM] like they would on a real drive.
NavState navAt(RouteOption route, double alongM,
    {bool arrived = false, bool rerouting = false, double? speedKmh}) {
  final cum = routeCumulative(route.points);
  var seg = 0;
  while (seg < cum.length - 2 && cum[seg + 1] <= alongM) {
    seg++;
  }
  final a = route.points[seg], b = route.points[seg + 1];
  final t = ((alongM - cum[seg]) / (cum[seg + 1] - cum[seg])).clamp(0.0, 1.0);
  return NavState(
    route: route,
    cum: cum,
    alongM: alongM,
    pos: LatLng(a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t),
    seg: seg,
    arrived: arrived,
    rerouting: rerouting,
    speedKmh: speedKmh,
  );
}

/// Starts navigation on [route] with a container whose GPS we control.
(ProviderContainer, FakeUserLoc) startNav(RouteOption route) {
  final loc = FakeUserLoc();
  final container = ProviderContainer(
    overrides: [userLocProvider.overrideWith(() => loc)],
  );
  addTearDown(container.dispose);
  container.read(navProvider.notifier).start(route);
  return (container, loc);
}
