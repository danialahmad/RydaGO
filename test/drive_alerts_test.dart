import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:waze_revamp/models/geo.dart';
import 'package:waze_revamp/models/report.dart';
import 'package:waze_revamp/models/route.dart';
import 'package:waze_revamp/services/voice.dart';
import 'package:waze_revamp/state/settings.dart';

import 'helpers.dart';

/// A report [metres] east of the route start (on the road), [north] metres off it.
Report reportAt(int id, double metres, {double north = 0, ReportType type = ReportType.police, String? subtype, bool mine = false}) =>
    Report(type, 3.0 + north / 110540, 101.0 + metres / 111320 * 1.0,
        id: id, subtype: subtype, mine: mine);

void main() {
  group('projectOnRoute', () {
    final route = straightRoute();
    final cum = routeCumulative(route.points);

    test('a point beside the road lands on it, with the right distance', () {
      final p = projectOnRoute(const LatLng(3.0003, 101.0035), route.points, cum);
      expect(p.alongM, closeTo(389, 8)); // 0.0035 deg east of the start
      expect(p.distM, closeTo(33, 3)); // 0.0003 deg north
      expect(p.snapped.latitude, closeTo(3.0, 1e-6));
      expect(p.seg, 3);
    });

    test('the search window can exclude segments, so a self-crossing route cannot jump', () {
      const p = LatLng(3.0, 101.0095); // near the end of the route
      final everywhere = projectOnRoute(p, route.points, cum);
      final early = projectOnRoute(p, route.points, cum, fromSeg: 0, toSeg: 2);
      expect(everywhere.alongM, closeTo(1055, 10));
      expect(early.alongM, closeTo(cum[3], 1)); // clamped to the end of its window
    });

    test('points beyond the ends snap to the nearest end', () {
      expect(projectOnRoute(const LatLng(3.0, 100.99), route.points, cum).alongM, 0);
      expect(projectOnRoute(const LatLng(3.0, 101.02), route.points, cum).alongM, closeTo(cum.last, 0.01));
    });
  });

  group('speed limit', () {
    final route = straightRoute(); // 60 km/h known up to segment 4, then unmapped

    test('is the limit of the stretch we are on', () {
      expect(navAt(route, 100).speedLimitKmh, 60);
      expect(navAt(route, 420).speedLimitKmh, 60);
    });

    test('is carried forward a little past the end of a known stretch, then dropped', () {
      // Segment 6 starts ~222 m after the end of the known stretch: still shown.
      expect(navAt(route, 700).speedLimitKmh, 60);
      // Segment 9 starts ~555 m after it: too far to assume.
      expect(navAt(route, 1050).speedLimitKmh, isNull);
    });

    test('is unknown before the first known stretch and on routes with none', () {
      final late = RouteOption('x', 5, 1.1, '', straightRoute().points, const [],
          limits: const [SpeedLimit(6, 8, 50)]);
      expect(navAt(late, 100).speedLimitKmh, isNull);
      expect(navAt(late, 800).speedLimitKmh, 50);
      final none = RouteOption('x', 5, 1.1, '', straightRoute().points, const []);
      expect(navAt(none, 300).speedLimitKmh, isNull);
    });

    test('isSpeeding needs a known limit, a known speed, and to be over by more than the tolerance', () {
      final onLimit = navAt(route, 100, speedKmh: 60);
      expect(onLimit.isSpeeding(0), isFalse);
      expect(navAt(route, 100, speedKmh: 61).isSpeeding(0), isTrue);
      expect(navAt(route, 100, speedKmh: 65).isSpeeding(5), isFalse);
      expect(navAt(route, 100, speedKmh: 66).isSpeeding(5), isTrue);
      expect(navAt(route, 100).isSpeeding(0), isFalse); // speed unknown
      expect(navAt(route, 1050, speedKmh: 200).isSpeeding(0), isFalse); // limit unknown
    });

    test('SpeedAlert settings map to tolerances (off = never warn)', () {
      expect(SpeedAlert.off.toleranceKmh, isNull);
      expect(SpeedAlert.atLimit.toleranceKmh, 0);
      expect(SpeedAlert.plus5.toleranceKmh, 5);
      expect(SpeedAlert.plus10.toleranceKmh, 10);
    });
  });

  group('reports ahead', () {
    final route = straightRoute();

    test('finds reports on the road ahead, nearest first, with the distance to them', () {
      final s = navAt(route, 100);
      final ahead = s.reportsAhead([reportAt(2, 700), reportAt(1, 400)]);
      expect(ahead.map((a) => a.report.id), [1, 2]);
      expect(ahead[0].aheadM, closeTo(300, 10));
      expect(ahead[1].aheadM, closeTo(600, 10));
    });

    test('ignores reports on another road, behind us, or too far ahead', () {
      final s = navAt(route, 100);
      final reports = [
        reportAt(1, 600, north: 200), // 200 m off the route: another road
        reportAt(2, 50), // already behind
        reportAt(3, 1000), // ~900 m ahead: beyond the 800 m default
      ];
      expect(s.reportsAhead(reports), isEmpty);
      expect(s.reportsAhead(reports, withinM: 1000).map((a) => a.report.id), [3]);
    });

    test('a report a few metres off the line still counts as being on our road', () {
      expect(navAt(route, 100).reportsAhead([reportAt(1, 500, north: 25)]), hasLength(1));
    });

    test('passedM also returns reports we have just driven past (negative distance)', () {
      final s = navAt(route, 500);
      final r = reportAt(1, 440); // 60 m behind
      expect(s.reportsAhead([r]), isEmpty);
      final passed = s.reportsAhead([r], passedM: 120);
      expect(passed, hasLength(1));
      expect(passed.single.aheadM, closeTo(-60, 10));
    });
  });

  group('report model', () {
    test('reads votes, id and ownership, with safe defaults', () {
      final r = Report.fromJson({
        'id': 7, 'type': 'camera', 'subtype': 'speed', 'lat': 3.1, 'lng': 101.7,
        'up': 3, 'down': 1, 'mine': true,
      });
      expect((r.id, r.up, r.down, r.mine), (7, 3, 1, true));
      final bare = Report.fromJson({'type': 'jam', 'lat': 1.0, 'lng': 2.0});
      expect((bare.id, bare.up, bare.down, bare.mine), (0, 0, 0, false));
    });

    test('copyWith changes only the vote counts', () {
      final r = Report(ReportType.hazard, 3.0, 101.0, id: 4, subtype: 'pothole', mine: true);
      final c = r.copyWith(up: 2, down: 5);
      expect((c.id, c.subtype, c.mine, c.up, c.down), (4, 'pothole', true, 2, 5));
    });

    test('spokenName reads naturally in Malay', () {
      String say(ReportType t, String? sub) => Report(t, 0, 0, subtype: sub).spokenName;
      expect(say(ReportType.police, 'hidden'), 'Polis tersembunyi');
      expect(say(ReportType.jam, 'standstill'), 'Kesesakan terhenti');
      expect(say(ReportType.hazard, 'pothole'), 'Bahaya lubang');
      expect(say(ReportType.camera, 'speed'), 'Kamera kelajuan'); // not "Kamera kamera kelajuan"
      expect(say(ReportType.closed, null), 'Jalan tutup');
    });

    test('RouteOption.fromJson reads the speed limits', () {
      final r = RouteOption.fromJson({
        'label': 'Terpantas', 'note': '', 'minutes': 1, 'km': 1.0,
        'points': [[3.0, 101.0], [3.0, 101.001]],
        'maneuvers': <Map<String, dynamic>>[],
        'limits': [
          {'from': 0, 'to': 4, 'kmh': 60},
          {'from': 9, 'to': 12, 'kmh': 80},
        ],
      });
      expect(r.limits.map((l) => (l.from, l.to, l.kmh)), [(0, 4, 60), (9, 12, 80)]);
      // An older server without "limits" must still parse.
      final old = RouteOption.fromJson({
        'label': 'x', 'note': '', 'minutes': 1, 'km': 1.0,
        'points': [[3.0, 101.0], [3.0, 101.001]], 'maneuvers': <Map<String, dynamic>>[],
      });
      expect(old.limits, isEmpty);
    });
  });

  group('VoicePlanner: reports ahead', () {
    final route = straightRoute();

    test('announces a report once, when it comes within 600 m, rounded to 50 m', () {
      final p = VoicePlanner();
      final r = reportAt(1, 940, type: ReportType.police, subtype: 'hidden');
      expect(p.nextAlert(navAt(route, 100), [r]), isNull); // 840 m: too far
      expect(p.nextAlert(navAt(route, 360), [r]), 'Polis tersembunyi di hadapan, 600 meter');
      expect(p.nextAlert(navAt(route, 400), [r]), isNull); // already said
      expect(p.nextAlert(navAt(route, 700), [r]), isNull);
    });

    test('skips reports that are not on our road or are already under our wheels', () {
      final p = VoicePlanner();
      expect(p.nextAlert(navAt(route, 100), [reportAt(1, 400, north: 300)]), isNull);
      expect(p.nextAlert(navAt(route, 395), [reportAt(2, 400)]), isNull); // 5 m away
    });

    test('each report is announced separately, nearest first', () {
      final p = VoicePlanner();
      final near = reportAt(1, 300, type: ReportType.jam, subtype: 'heavy');
      final far = reportAt(2, 500, type: ReportType.hazard, subtype: 'pothole');
      expect(p.nextAlert(navAt(route, 100), [far, near]), 'Kesesakan teruk di hadapan, 200 meter');
      expect(p.nextAlert(navAt(route, 110), [far, near]), 'Bahaya lubang di hadapan, 400 meter');
      expect(p.nextAlert(navAt(route, 120), [far, near]), isNull);
    });

    test('stays quiet while re-routing or after arriving, and reset forgets what it said', () {
      final p = VoicePlanner();
      final r = reportAt(1, 300);
      expect(p.nextAlert(navAt(route, 100, rerouting: true), [r]), isNull);
      expect(p.nextAlert(navAt(route, 100, arrived: true), [r]), isNull);
      expect(p.nextAlert(navAt(route, 100), [r]), isNotNull);
      p.reset();
      expect(p.nextAlert(navAt(route, 100), [r]), isNotNull);
    });
  });

  group('VoicePlanner: speeding', () {
    final route = straightRoute();
    at(double speed) => navAt(route, 100, speedKmh: speed);

    test('warns once, and again only after dropping back to the limit', () {
      final p = VoicePlanner();
      expect(p.speeding(at(58), 5), isNull);
      expect(p.speeding(at(70), 5), 'Anda melebihi had laju, 60 kilometer sejam');
      expect(p.speeding(at(72), 5), isNull); // still speeding: do not nag
      expect(p.speeding(at(62), 5), isNull); // below limit+5 but above the limit: not re-armed
      expect(p.speeding(at(70), 5), isNull);
      expect(p.speeding(at(55), 5), isNull); // back under the limit: re-armed
      expect(p.speeding(at(70), 5), isNotNull);
    });

    test('is silent when switched off, when the limit is unknown, or after arriving', () {
      final p = VoicePlanner();
      expect(p.speeding(at(120), null), isNull);
      expect(p.speeding(navAt(route, 1050, speedKmh: 120), 5), isNull);
      expect(p.speeding(navAt(route, 100, speedKmh: 120, arrived: true), 5), isNull);
    });

    test('tolerance 0 warns as soon as the limit is passed', () {
      final p = VoicePlanner();
      expect(p.speeding(at(61), 0), isNotNull);
    });
  });
}
