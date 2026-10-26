import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/strings.dart';
import '../models/route.dart';
import '../models/route_summary.dart';
import '../services/api.dart';
import 'navigation.dart';
import 'reports.dart';
import 'settings.dart';
import 'trip.dart';
import 'voice.dart';

/// Fetches routes from a position to the destination. The real one asks the API;
/// tests swap in a fake.
typedef RouteFetcher = Future<List<RouteOption>> Function(
  LatLng from,
  LatLng to,
  AppLang lang, {
  bool avoidHighways,
});

final routeFetcherProvider = Provider<RouteFetcher>((ref) => Api.routes);

/// The clock the detour check runs on; tests move it forward by hand.
final altClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// How often a drive is checked for a better way, and how soon after the car has
/// been crawling for a minute (traffic is where a detour pays off most).
const kAltCheckEvery = Duration(seconds: 45);
const kAltCheckWhenStuck = Duration(seconds: 30);

/// A suggestion left unanswered this long goes away by itself.
const kSuggestionLife = Duration(seconds: 30);

/// After "No", stay quiet this long.
const kDeclineQuiet = Duration(minutes: 10);

/// Extra minutes assumed on the current road when the car is stuck on it.
const kStuckPenaltyMin = 5;

class AltState {
  const AltState({
    this.options = const [],
    this.loading = false,
    this.suggestion,
    this.currentDelayMin = 0,
    this.stuck = false,
  });

  /// Routes from where we are now, best first, for the routes sheet.
  final List<RouteChoice> options;
  final bool loading;

  /// A route worth switching to, waiting for the driver's Yes or No.
  final RouteChoice? suggestion;

  /// Minutes the current route is expected to lose to reports (and standing still).
  final int currentDelayMin;
  final bool stuck;

  AltState copyWith({
    List<RouteChoice>? options,
    bool? loading,
    RouteChoice? Function()? suggestion,
    int? currentDelayMin,
    bool? stuck,
  }) =>
      AltState(
        options: options ?? this.options,
        loading: loading ?? this.loading,
        suggestion: suggestion != null ? suggestion() : this.suggestion,
        currentDelayMin: currentDelayMin ?? this.currentDelayMin,
        stuck: stuck ?? this.stuck,
      );
}

/// While driving, looks for a quicker way now and then and asks the driver to take
/// it, and serves the list of other routes the driver can open from the bottom bar.
/// Valhalla knows no live traffic, so "quicker" counts the delay community reports
/// (jams, crashes, closures) add on each road, plus a standstill on the current one.
class AlternativesNotifier extends Notifier<AltState> {
  late final _stuck = StuckDetector(clock: _now);
  late DateTime _lastCheck = _now();
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _now() => ref.read(altClockProvider)();
  bool _busy = false;
  Timer? _expiry;

  @override
  AltState build() {
    ref.onDispose(() => _expiry?.cancel());
    ref.listen(navProvider, (prev, next) {
      if (next == null || next.arrived) {
        _stuck.reset();
        _expiry?.cancel();
        if (state.suggestion != null || state.options.isNotEmpty) {
          state = const AltState();
        }
        return;
      }
      if (prev == null) {
        _lastCheck = _now(); // a fresh drive: first look after a while
        _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);
      }
      final stuck = _stuck.update(next.speedKmh);
      if (stuck != state.stuck) state = state.copyWith(stuck: stuck);
      _maybeCheck(stuck);
    });
    return const AltState();
  }

  void _maybeCheck(bool stuck) {
    final nav = ref.read(navProvider);
    if (nav == null || nav.arrived || nav.rerouting || _busy) return;
    if (state.suggestion != null) return; // one question at a time
    final now = _now();
    if (now.isBefore(_quietUntil)) return;
    final every = stuck ? kAltCheckWhenStuck : kAltCheckEvery;
    if (now.difference(_lastCheck) < every) return;
    _lastCheck = now;
    _check(suggest: true);
  }

  /// Fetches routes from the current position. With [suggest], also decides
  /// whether one deserves a Yes/No question.
  Future<void> _check({required bool suggest}) async {
    final nav = ref.read(navProvider);
    final dest = ref.read(destinationProvider);
    if (nav == null || dest == null || _busy) return;
    _busy = true;
    state = state.copyWith(loading: true);
    try {
      final settings = ref.read(settingsProvider);
      final routes = await ref.read(routeFetcherProvider)(
        nav.pos,
        dest.pos,
        settings.lang,
        avoidHighways: settings.avoidHighways,
      );
      final now = ref.read(navProvider);
      if (now == null || now.arrived) return;
      final reports = ref.read(reportsProvider);
      final choices = [
        for (final r in routes) RouteChoice(r, routeDelayMin(r, reports)),
      ]..sort((a, b) => a.totalMin.compareTo(b.totalMin));
      final stuck = _stuck.update(null);
      final delay = routeDelayMin(now.route, reports, fromM: now.alongM) +
          (stuck ? kStuckPenaltyMin : 0);
      final better = suggest
          ? pickBetterRoute(
              currentMin: now.remainingMin,
              currentDelayMin: delay,
              remainingKm: now.remainingM / 1000,
              via: now.route.via,
              candidates: choices,
            )
          : null;
      state = state.copyWith(
        options: choices,
        loading: false,
        currentDelayMin: delay,
        suggestion: better != null ? () => better : null,
      );
      if (better != null) _announce(better, now.remainingMin + delay);
    } catch (_) {
      state = state.copyWith(loading: false); // offline or routing down: try later
    } finally {
      _busy = false;
    }
  }

  void _announce(RouteChoice better, int currentTotalMin) {
    _expiry?.cancel();
    _expiry = Timer(kSuggestionLife, () {
      if (state.suggestion != null) decline(quietFor: const Duration(minutes: 5));
    });
    final settings = ref.read(settingsProvider);
    if (settings.voiceOn) {
      final saving = currentTotalMin - better.totalMin;
      ref.read(speakerProvider).speak(
            S(settings.lang).betterRouteVoice(saving),
            settings.lang.ttsLocale,
          );
    }
  }

  /// Loads the routes for the sheet opened from the bottom bar.
  Future<void> refreshOptions() => _check(suggest: false);

  /// Takes a route (the suggested one, or one picked from the sheet).
  void accept(RouteChoice choice) {
    _expiry?.cancel();
    ref.read(navProvider.notifier).switchTo(choice.route);
    _stuck.reset();
    _lastCheck = _now();
    state = const AltState();
  }

  /// "No": keep the current route and stay quiet for a while.
  void decline({Duration quietFor = kDeclineQuiet}) {
    _expiry?.cancel();
    _quietUntil = _now().add(quietFor);
    state = state.copyWith(suggestion: () => null);
  }
}

final alternativesProvider =
    NotifierProvider<AlternativesNotifier, AltState>(AlternativesNotifier.new);
