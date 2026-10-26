import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:rydago/app/strings.dart';
import 'package:rydago/models/place.dart';
import 'package:rydago/models/report.dart';
import 'package:rydago/models/route.dart';
import 'package:rydago/services/voice.dart';
import 'package:rydago/state/alternatives.dart';
import 'package:rydago/state/navigation.dart';
import 'package:rydago/state/reports.dart';
import 'package:rydago/state/trip.dart';
import 'package:rydago/state/user_loc.dart';
import 'package:rydago/state/voice.dart';
import 'package:flutter/material.dart' show Icons;

import 'helpers.dart';

class _FakeReports extends ReportsNotifier {
  @override
  List<Report> build() => const []; // no timer, no network
}

class _FakeSpeaker implements Speaker {
  final said = <String>[];
  @override
  Future<void> speak(String text, [String locale = 'en-US']) async => said.add(text);
  @override
  Future<void> stop() async {}
}

/// A shortcut of 2 minutes and 2 km on another road, against the 5 minute,
/// 1.1 km "Jalan B" route the helpers build.
RouteOption _shortcut({int minutes = 2}) => RouteOption(
      'Alternative', minutes, 2.0, '',
      [for (var i = 0; i <= 10; i++) LatLng(3.0, 101.0 + i * 0.002)],
      const [], via: 'Jalan Alt', id: 'alt1',
    );

void main() {
  late DateTime now;
  late FakeUserLoc loc;
  late ProviderContainer container;
  late _FakeSpeaker speaker;
  late List<RouteOption> fetched;
  var fetches = 0;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    fetched = [_shortcut()];
    fetches = 0;
    speaker = _FakeSpeaker();
    loc = FakeUserLoc();
    container = ProviderContainer(overrides: [
      userLocProvider.overrideWith(() => loc),
      reportsProvider.overrideWith(_FakeReports.new),
      speakerProvider.overrideWithValue(speaker),
      altClockProvider.overrideWithValue(() => now),
      routeFetcherProvider.overrideWithValue((from, to, lang, {avoidHighways = false}) async {
        fetches++;
        return fetched;
      }),
    ]);
    addTearDown(container.dispose);
    container.read(destinationProvider.notifier)
        .set(Place('Batu Caves', '', Icons.place, const LatLng(3.0, 101.01)));
    container.read(alternativesProvider); // keeps it listening, like the map screen
    container.read(navProvider.notifier).start(straightRoute());
  });

  /// One GPS fix on the route latitude at longitude [lng], moving at [mps] m/s.
  Future<void> drive(double lng, double mps) async {
    loc.emit(fix(3.0, lng, speed: mps));
    await pumpEventQueue();
  }

  test('suggests a quicker route after the check interval, and Yes switches to it', () async {
    await drive(101.0005, 10);
    expect(container.read(alternativesProvider).suggestion, isNull, reason: 'too soon after the start');
    expect(fetches, 0);

    now = now.add(kAltCheckEvery + const Duration(seconds: 1));
    await drive(101.0006, 10);
    final alt = container.read(alternativesProvider);
    expect(fetches, 1);
    expect(alt.suggestion?.route.via, 'Jalan Alt');
    expect(speaker.said.single, const S(AppLang.en).betterRouteVoice(3));

    container.read(alternativesProvider.notifier).accept(alt.suggestion!);
    expect(container.read(navProvider)!.route.via, 'Jalan Alt');
    expect(container.read(alternativesProvider).suggestion, isNull);
  });

  test('No keeps the route and stays quiet for ten minutes', () async {
    now = now.add(kAltCheckEvery + const Duration(seconds: 1));
    await drive(101.0005, 10);
    expect(container.read(alternativesProvider).suggestion, isNotNull);

    container.read(alternativesProvider.notifier).decline();
    expect(container.read(navProvider)!.route.via, 'Jalan B');
    expect(container.read(alternativesProvider).suggestion, isNull);

    now = now.add(const Duration(minutes: 5));
    await drive(101.0006, 10);
    expect(container.read(alternativesProvider).suggestion, isNull, reason: 'still in the quiet period');

    now = now.add(const Duration(minutes: 6));
    await drive(101.0007, 10);
    expect(container.read(alternativesProvider).suggestion, isNotNull, reason: 'quiet period over');
  });

  test('does not suggest a route that saves too little or is the same road', () async {
    fetched = [_shortcut(minutes: 4)]; // saves 1 minute
    now = now.add(kAltCheckEvery + const Duration(seconds: 1));
    await drive(101.0005, 10);
    expect(fetches, 1);
    expect(container.read(alternativesProvider).suggestion, isNull);
    // ... but it is still offered in the routes sheet.
    expect(container.read(alternativesProvider).options, hasLength(1));
  });

  test('being stuck checks sooner and counts as delay on the current road', () async {
    await drive(101.0005, 0);
    now = now.add(const Duration(seconds: 61));
    await drive(101.0005, 0);
    expect(container.read(alternativesProvider).stuck, isTrue);
    // Stuck for a minute: the 30 s interval applies, not 45 s, and the standstill
    // adds minutes to the current route.
    expect(fetches, 1);
    expect(container.read(alternativesProvider).currentDelayMin, kStuckPenaltyMin);
  });

  test('everything is cleared when the drive ends', () async {
    now = now.add(kAltCheckEvery + const Duration(seconds: 1));
    await drive(101.0005, 10);
    expect(container.read(alternativesProvider).options, isNotEmpty);
    container.read(navProvider.notifier).stop();
    expect(container.read(alternativesProvider).options, isEmpty);
    expect(container.read(alternativesProvider).suggestion, isNull);
  });
}
