import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
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
    );

UserLoc fix(double lat, double lng, {double? speed, double accuracy = 5}) =>
    UserLoc(LocStatus.active, LatLng(lat, lng), speed, 90, accuracy);

/// A NavState at [alongM] metres along [route], for tests that only need the model.
NavState navAt(RouteOption route, double alongM,
    {bool arrived = false, bool rerouting = false}) {
  return NavState(
    route: route,
    cum: routeCumulativeFor(route),
    alongM: alongM,
    pos: route.points.first,
    arrived: arrived,
    rerouting: rerouting,
  );
}

List<double> routeCumulativeFor(RouteOption r) {
  // Same maths the app uses, via a throwaway navigation start.
  final loc = FakeUserLoc();
  final container = ProviderContainer(overrides: [userLocProvider.overrideWith(() => loc)]);
  addTearDown(container.dispose);
  container.read(navProvider.notifier).start(r);
  return container.read(navProvider)!.cum;
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
