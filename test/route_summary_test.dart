import 'package:flutter_test/flutter_test.dart';
import 'package:rydago/models/report.dart';
import 'package:rydago/models/route.dart';
import 'package:rydago/models/route_summary.dart';

import 'helpers.dart';

void main() {
  alternativeTests();
  test('reportsOnRoute counts reports on the road by type and ignores nearby roads', () {
    final route = straightRoute(); // runs east along lat 3.0 from lng 101.0
    final reports = [
      Report(ReportType.camera, 3.0, 101.003, id: 1),
      Report(ReportType.camera, 3.0001, 101.006, id: 2), // ~11 m off: still on it
      Report(ReportType.police, 3.0, 101.008, id: 3),
      Report(ReportType.jam, 3.002, 101.004, id: 4), // 220 m north: another road
    ];
    final counts = reportsOnRoute(route, reports);
    expect(counts, {ReportType.camera: 2, ReportType.police: 1});
  });

  test('an empty list, or a route too short to measure, gives no counts', () {
    expect(reportsOnRoute(straightRoute(), const []), isEmpty);
  });
}

void alternativeTests() {
  Report at(ReportType t, String? sub, double lng, {double lat = 3.0}) =>
      Report(t, lat, lng, subtype: sub);

  group('report delays', () {
    test('only jams, crashes and closures cost time', () {
      expect(reportDelayMin(at(ReportType.jam, 'standstill', 101.0)), 10);
      expect(reportDelayMin(at(ReportType.jam, null, 101.0)), 3);
      expect(reportDelayMin(at(ReportType.accident, 'major', 101.0)), 12);
      expect(reportDelayMin(at(ReportType.closed, 'road', 101.0)), 25);
      expect(reportDelayMin(at(ReportType.closed, 'lane', 101.0)), 3);
      expect(reportDelayMin(at(ReportType.police, 'hidden', 101.0)), 0);
      expect(reportDelayMin(at(ReportType.camera, 'speed', 101.0)), 0);
    });

    test('routeDelayMin sums separate jams, counts a cluster once, skips what is behind us', () {
      final route = straightRoute(); // ~1.1 km east
      final jams = [
        at(ReportType.jam, 'heavy', 101.002), // ~220 m
        at(ReportType.jam, 'standstill', 101.003), // 111 m later: same jam, the worst counts
        at(ReportType.accident, 'minor', 101.008), // ~890 m: a separate one
        at(ReportType.jam, 'heavy', 101.003, lat: 3.002), // another road
      ];
      expect(routeDelayMin(route, jams), 10 + 4);
      expect(routeDelayMin(route, jams, fromM: 500), 4); // the first jam is behind us
      expect(routeDelayMin(route, const []), 0);
    });

    test('delay is capped', () {
      final route = straightRoute();
      final closures = [
        for (var i = 0; i < 6; i++) at(ReportType.closed, 'road', 101.001 + i * 0.0015),
      ];
      expect(routeDelayMin(route, closures), kMaxDelayMin);
    });
  });

  group('pickBetterRoute', () {
    RouteChoice choice(int min, double km, String via, {int delay = 0}) => RouteChoice(
          RouteOption('x', min, km, '', straightRoute().points, const [], via: via),
          delay,
        );

    test('suggests a route that saves enough, the best one if several', () {
      final pick = pickBetterRoute(
        currentMin: 20,
        currentDelayMin: 10,
        remainingKm: 12,
        via: 'E1',
        candidates: [choice(26, 15, 'Jalan A'), choice(24, 14, 'Jalan B'), choice(19, 12.2, 'E1')],
      );
      expect(pick?.route.via, 'Jalan B'); // 24 beats 30; the E1 one is the same road
    });

    test('says nothing when the saving is under the threshold', () {
      expect(
        pickBetterRoute(
          currentMin: 20,
          currentDelayMin: 0,
          remainingKm: 12,
          via: 'E1',
          candidates: [choice(18, 13, 'Jalan A')], // saves 2 min
        ),
        isNull,
      );
    });

    test('a candidate with its own delays is judged on the total', () {
      expect(
        pickBetterRoute(
          currentMin: 20,
          currentDelayMin: 6,
          remainingKm: 12,
          via: 'E1',
          candidates: [choice(18, 13, 'Jalan A', delay: 10)], // 28 vs 26
        ),
        isNull,
      );
    });
  });

  group('StuckDetector', () {
    test('needs a full minute of crawling, and a faster speed resets it', () {
      var now = DateTime(2026, 1, 1, 12);
      final d = StuckDetector(clock: () => now);
      expect(d.update(3), isFalse);
      now = now.add(const Duration(seconds: 59));
      expect(d.update(2), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(d.update(0), isTrue);
      expect(d.update(null), isTrue); // unknown speed does not end it
      expect(d.update(30), isFalse); // moving again
      now = now.add(const Duration(seconds: 30));
      expect(d.update(1), isFalse); // the clock starts over
    });
  });
}
