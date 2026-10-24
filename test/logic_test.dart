import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waze_revamp/app/config.dart';
import 'package:waze_revamp/app/format.dart';
import 'package:waze_revamp/models/place.dart';
import 'package:waze_revamp/models/report.dart';
import 'package:waze_revamp/models/route.dart';
import 'package:waze_revamp/models/user_loc.dart';
import 'package:waze_revamp/services/voice.dart';
import 'package:waze_revamp/state/saved_places.dart';

import 'helpers.dart';

void main() {
  group('formatting', () {
    test('formatDistance: metres to the nearest 10 below 1 km, km with one decimal above', () {
      expect(formatDistance(0), '0 m');
      expect(formatDistance(347), '350 m');
      expect(formatDistance(999), '1000 m'); // still the metres branch
      expect(formatDistance(1000), '1.0 km');
      expect(formatDistance(12340), '12.3 km');
    });

    test('formatDuration', () {
      expect(formatDuration(1), '1 min');
      expect(formatDuration(59), '59 min');
      expect(formatDuration(60), '1 j');
      expect(formatDuration(135), '2 j 15 min');
    });

    test('formatClock uses a 12-hour clock with PG (pagi) and PTG (petang)', () {
      expect(formatClock(DateTime(2026, 1, 1, 0, 5)), '12:05 PG');
      expect(formatClock(DateTime(2026, 1, 1, 9, 30)), '9:30 PG');
      expect(formatClock(DateTime(2026, 1, 1, 12, 0)), '12:00 PTG');
      expect(formatClock(DateTime(2026, 1, 1, 15, 22)), '3:22 PTG');
    });
  });

  group('VoicePlanner', () {
    test('announces each turn once from far away and once when close', () {
      final r = straightRoute();
      final p = VoicePlanner();
      // At the very start the first maneuver is "close": say it.
      expect(p.next(navAt(r, 0)), 'Mulakan perjalanan di Jalan A');
      expect(p.next(navAt(r, 5)), isNull); // nothing new
      // 455 m before the turn: far announcement, distance rounded to 50 m.
      expect(p.next(navAt(r, 100)), 'Dalam 450 meter, belok kanan menuju Jalan B');
      expect(p.next(navAt(r, 150)), isNull); // already said
      // Within 150 m: the short form.
      expect(p.next(navAt(r, 450)), 'Belok kanan menuju Jalan B');
      expect(p.next(navAt(r, 500)), isNull);
    });

    test('says nothing about the arrival maneuver itself, only the arrival', () {
      final r = straightRoute();
      final p = VoicePlanner();
      p.next(navAt(r, 0));
      p.next(navAt(r, 450)); // turn announced
      expect(p.next(navAt(r, 1050)), isNull); // last maneuver is the arrival: stay quiet
      expect(p.next(navAt(r, 1110, arrived: true)), 'Anda telah sampai di destinasi');
      expect(p.next(navAt(r, 1110, arrived: true)), isNull);
    });

    test('announces re-routing once per re-route', () {
      final r = straightRoute();
      final p = VoicePlanner();
      expect(p.next(navAt(r, 0, rerouting: true)), 'Mengira semula laluan');
      expect(p.next(navAt(r, 0, rerouting: true)), isNull);
      p.next(navAt(r, 0)); // re-route finished
      expect(p.next(navAt(r, 0, rerouting: true)), 'Mengira semula laluan');
    });

    test('reset starts a fresh trip', () {
      final r = straightRoute();
      final p = VoicePlanner();
      expect(p.next(navAt(r, 0)), isNotNull);
      p.reset();
      expect(p.next(navAt(r, 0)), 'Mulakan perjalanan di Jalan A');
    });
  });

  group('report types (contract with backend/main.go reportSubtypes)', () {
    // Keep identical to reportSubtypes in backend/main.go and the table in docs/API.md.
    const expected = {
      'police': ['visible', 'hidden', 'other_side'],
      'accident': ['minor', 'major', 'other_side'],
      'jam': ['moderate', 'heavy', 'standstill'],
      'hazard': ['object', 'pothole', 'stopped_vehicle', 'construction', 'broken_light', 'weather'],
      'camera': ['speed', 'red_light'],
      'closed': ['road', 'lane'],
    };

    test('every type and subtype key matches what the API accepts', () {
      expect(ReportType.values.map((t) => t.name).toSet(), expected.keys.toSet());
      for (final t in ReportType.values) {
        expect(t.subtypes.map((s) => s.key).toList(), expected[t.name], reason: t.name);
      }
    });

    test('Report.fromJson reads a subtype and builds a readable title', () {
      final r = Report.fromJson(
          {'id': 1, 'type': 'police', 'subtype': 'hidden', 'lat': 3.1, 'lng': 101.7});
      expect(r.type, ReportType.police);
      expect(r.subtype, 'hidden');
      expect(r.title, 'Polis · Tersembunyi');
      expect(r.pos, const LatLng(3.1, 101.7));
    });

    test('a report without a subtype (or an unknown one) falls back to the type label', () {
      expect(Report.fromJson({'type': 'jam', 'lat': 1.0, 'lng': 2.0}).title, 'Kesesakan');
      expect(
          Report.fromJson({'type': 'jam', 'subtype': 'nonsense', 'lat': 1.0, 'lng': 2.0}).title,
          'Kesesakan');
    });
  });

  group('API models', () {
    test('RouteOption.fromJson reads points, maneuvers, street and via', () {
      final r = RouteOption.fromJson({
        'label': 'Terpantas',
        'note': 'Laluan terpantas',
        'via': 'E12',
        'minutes': 6,
        'km': 4.9,
        'points': [
          [3.1579, 101.7116],
          [3.16, 101.72],
        ],
        'maneuvers': [
          {'text': 'Mulakan perjalanan di Lorong Kuda', 'street': 'Lorong Kuda', 'type': 1, 'km': 0.4, 'index': 0},
          {'text': 'Anda telah sampai', 'type': 4, 'km': 0, 'index': 1},
        ],
      });
      expect(r.via, 'E12');
      expect(r.points.last, const LatLng(3.16, 101.72));
      expect(r.maneuvers[0].street, 'Lorong Kuda');
      expect(r.maneuvers[1].street, ''); // missing street becomes empty, not null
    });

    test('Place.fromApi picks an icon from the Nominatim category', () {
      final p = Place.fromApi({
        'name': 'KLIA', 'area': 'Sepang', 'lat': 2.74, 'lng': 101.7,
        'category': 'aeroway', 'type': 'aerodrome',
      });
      expect(p.icon, Icons.flight);
      expect(p.pos.latitude, 2.74);
    });

    test('Place.isSameAs ignores tiny coordinate differences but not different names', () {
      const a = Place('Pasar', 'KL', Icons.place, LatLng(3.1000, 101.7000));
      expect(a.isSameAs(const Place('Pasar', 'KL', Icons.place, LatLng(3.1002, 101.7001))), isTrue);
      expect(a.isSameAs(const Place('Pasar', 'KL', Icons.place, LatLng(3.2, 101.7))), isFalse);
      expect(a.isSameAs(const Place('Kedai', 'KL', Icons.place, LatLng(3.1, 101.7))), isFalse);
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

  group('saved places and recents', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    const home = Place('Rumah Ali', 'Cheras', Icons.place, LatLng(3.08, 101.74));
    const cafe = Place('Kafe Ros', 'Bangsar', Icons.place, LatLng(3.13, 101.67));

    test('home and work are set and cleared independently', () {
      final c = container();
      final n = c.read(savedPlacesProvider.notifier);
      n.setHome(home);
      n.setWork(cafe);
      expect(c.read(savedPlacesProvider).home!.name, 'Rumah Ali');
      n.setHome(null);
      expect(c.read(savedPlacesProvider).home, isNull);
      expect(c.read(savedPlacesProvider).work!.name, 'Kafe Ros');
    });

    test('toggleFavorite adds a place, then removes it', () {
      final c = container();
      final n = c.read(savedPlacesProvider.notifier);
      n.toggleFavorite(cafe);
      expect(c.read(savedPlacesProvider).isFavorite(cafe), isTrue);
      n.toggleFavorite(cafe);
      expect(c.read(savedPlacesProvider).favorites, isEmpty);
    });

    test('saved places survive being written and read back as JSON', () {
      const saved = SavedPlaces(home: home, favorites: [cafe]);
      final back = SavedPlaces.fromJson(saved.toJson());
      expect(back.home!.name, 'Rumah Ali');
      expect(back.work, isNull);
      expect(back.favorites.single.name, 'Kafe Ros');
    });

    test('recents keep the newest first, drop duplicates, and cap at 8', () async {
      final c = container();
      final n = c.read(recentsProvider.notifier);
      for (var i = 0; i < 10; i++) {
        await n.add(Place('Tempat $i', '', Icons.place, LatLng(3.0 + i * 0.01, 101.0)));
      }
      final list = c.read(recentsProvider);
      expect(list.length, 8);
      expect(list.first.name, 'Tempat 9');
      await n.add(Place('Tempat 5', '', Icons.place, const LatLng(3.05, 101.0))); // same place again
      expect(c.read(recentsProvider).first.name, 'Tempat 5');
      expect(c.read(recentsProvider).where((p) => p.name == 'Tempat 5').length, 1);
    });
  });
}
