import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:waze_revamp/main.dart';

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
        Maneuver('Mulakan perjalanan di Jalan A', 1, 0.55, 0),
        Maneuver('Belok kanan menuju Jalan B', 10, 0.55, 5),
        Maneuver('Anda telah sampai', 4, 0, 10),
      ],
    );

UserLoc fix(double lat, double lng, {double? speed, double accuracy = 5}) =>
    UserLoc(LocStatus.active, LatLng(lat, lng), speed, 90, accuracy);

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

void main() {
  group('geometry helpers', () {
    test('haversineM is about 111 m for 0.001 degrees of longitude near the equator', () {
      final d = haversineM(const LatLng(3.0, 101.0), const LatLng(3.0, 101.001));
      expect(d, closeTo(111, 2));
    });

    test('routeCumulative starts at 0 and grows along the route', () {
      final cum = routeCumulative(straightRoute().points);
      expect(cum.first, 0);
      expect(cum.length, 11);
      expect(cum.last, closeTo(1110, 15));
      for (var i = 1; i < cum.length; i++) {
        expect(cum[i], greaterThan(cum[i - 1]));
      }
    });
  });

  group('NavState', () {
    NavState at(double along, {bool arrived = false}) {
      final r = straightRoute();
      return NavState(
        route: r,
        cum: routeCumulative(r.points),
        alongM: along,
        pos: r.points.first,
        arrived: arrived,
      );
    }

    test('upcoming is the next maneuver still ahead and counts down to it', () {
      final s = at(300);
      expect(s.upcoming!.text, 'Belok kanan menuju Jalan B');
      expect(s.distToUpcomingM, closeTo(555 - 300, 15));
      expect(at(700).upcoming!.text, 'Anda telah sampai');
    });

    test('remaining minutes shrink with progress and are 0 once arrived', () {
      expect(at(0).remainingMin, 5);
      expect(at(555).remainingMin, 3); // half way: 2.5 min rounds up
      expect(at(1000).remainingMin, 1);
      expect(at(1110, arrived: true).remainingMin, 0);
    });
  });

  group('GPS-driven navigation', () {
    test('progress follows the GPS fixes along the route', () {
      final (container, loc) = startNav(straightRoute());
      loc.emit(fix(3.0, 101.003)); // 3 points along
      final nav = container.read(navProvider)!;
      expect(nav.alongM, closeTo(333, 10));
      expect(nav.upcoming!.text, 'Belok kanan menuju Jalan B');
      expect(nav.arrived, isFalse);
      expect(nav.rerouting, isFalse);
    });

    test('a fix close to the route is snapped onto it', () {
      final (container, loc) = startNav(straightRoute());
      loc.emit(fix(3.0002, 101.004)); // ~22 m north of the line
      final nav = container.read(navProvider)!;
      expect(nav.offRouteM, closeTo(22, 3));
      expect(nav.pos.latitude, closeTo(3.0, 1e-6)); // snapped back to the line
    });

    test('a fix far from the route is shown where it really is, and flagged off-route', () {
      final (container, loc) = startNav(straightRoute());
      final routeBefore = container.read(navProvider)!.route;
      loc.emit(fix(3.003, 101.004)); // ~330 m north
      final nav = container.read(navProvider)!;
      expect(nav.offRouteM, greaterThan(300));
      expect(nav.pos.latitude, closeTo(3.003, 1e-9));
      // Re-routing is held back for a few seconds after navigation starts, so
      // the route in use has not been swapped.
      expect(nav.rerouting, isFalse);
      expect(identical(nav.route, routeBefore), isTrue);
    });

    test('arrives when the fix is within 30 m of the end of the route', () {
      final (container, loc) = startNav(straightRoute());
      loc.emit(fix(3.0, 101.00985)); // ~17 m before the last point
      final nav = container.read(navProvider)!;
      expect(nav.arrived, isTrue);
      expect(nav.alongM, nav.totalM);
      expect(nav.upcoming!.text, 'Anda telah sampai');
    });

    test('later fixes are ignored once arrived', () {
      final (container, loc) = startNav(straightRoute());
      loc.emit(fix(3.0, 101.0099));
      loc.emit(fix(3.0, 101.002));
      expect(container.read(navProvider)!.arrived, isTrue);
    });

    test('fixes less precise than 100 m are ignored', () {
      final (container, loc) = startNav(straightRoute());
      loc.emit(fix(3.0, 101.003));
      final before = container.read(navProvider)!;
      loc.emit(fix(3.0, 101.008, accuracy: 500));
      expect(container.read(navProvider)!.alongM, before.alongM);
    });

    test('GPS speed (m/s) is reported in km/h, and unknown speed stays null', () {
      final (container, loc) = startNav(straightRoute());
      loc.emit(fix(3.0, 101.002, speed: 10));
      expect(container.read(navProvider)!.speedKmh, closeTo(36, 0.01));
      loc.emit(fix(3.0, 101.003));
      expect(container.read(navProvider)!.speedKmh, isNull);
    });

    test('stop clears the navigation state', () {
      final (container, _) = startNav(straightRoute());
      container.read(navProvider.notifier).stop();
      expect(container.read(navProvider), isNull);
    });
  });

  group('models and the backend contract', () {
    test('ReportType names are exactly the types the API accepts', () {
      expect(
        ReportType.values.map((t) => t.name).toSet(),
        {'police', 'accident', 'jam', 'hazard', 'camera', 'closed'},
      );
    });

    test('Place survives a JSON round trip (used for recent destinations)', () {
      const p = Place('Batu Caves', 'Selayang, Selangor', Icons.place, LatLng(3.2379, 101.684));
      final back = Place.fromJson(p.toJson());
      expect(back.name, p.name);
      expect(back.area, p.area);
      expect(back.pos.latitude, p.pos.latitude);
      expect(back.pos.longitude, p.pos.longitude);
    });

    test('UserLoc falls back to the sample position until there is a real fix', () {
      const waiting = UserLoc(LocStatus.denied);
      expect(waiting.isReal, isFalse);
      expect(waiting.pos, kCenter);
      final live = fix(5.4, 100.3);
      expect(live.isReal, isTrue);
      expect(live.pos, const LatLng(5.4, 100.3));
    });
  });
}
