import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:waze_revamp/models/geo.dart';
import 'package:waze_revamp/state/navigation.dart';

import 'helpers.dart';

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
    test('upcoming is the next maneuver still ahead and counts down to it', () {
      final r = straightRoute();
      final s = navAt(r, 300);
      expect(s.upcoming!.text, 'Belok kanan menuju Jalan B');
      expect(s.distToUpcomingM, closeTo(555 - 300, 15));
      expect(navAt(r, 700).upcoming!.text, 'Anda telah sampai');
    });

    test('"then" is the maneuver right after the next one, when it follows closely', () {
      final r = straightRoute();
      // From 400 m the next turn is at ~555 m and the arrival 555 m later: too far for "then".
      expect(navAt(r, 400).then, isNull);
      // Past the turn the arrival is the next maneuver and nothing follows it.
      expect(navAt(r, 700).then, isNull);
    });

    test('remaining minutes shrink with progress and are 0 once arrived', () {
      final r = straightRoute();
      expect(navAt(r, 0).remainingMin, 5);
      expect(navAt(r, 555).remainingMin, 3); // half way: 2.5 min rounds up
      expect(navAt(r, 1000).remainingMin, 1);
      expect(navAt(r, 1110, arrived: true).remainingMin, 0);
    });

    test('progress runs from 0 to 1', () {
      final r = straightRoute();
      expect(navAt(r, 0).progress, 0);
      expect(navAt(r, 555).progress, closeTo(0.5, 0.02));
      expect(navAt(r, 5000).progress, 1); // clamped
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
}
