import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';

import '../app/strings.dart';
import '../models/report.dart';
import '../models/route.dart';
import '../state/navigation.dart';

/// Something that can say a sentence out loud. Swapped for a fake in tests.
abstract class Speaker {
  /// Says [text] after whatever is still being said. [locale] is a BCP-47 tag
  /// such as "en-US" or "ms-MY".
  Future<void> speak(String text, [String locale = 'en-US']);

  /// Goes quiet and drops anything still waiting.
  Future<void> stop();
}

/// Says sentences one after another instead of cutting the current one off.
/// A drive often produces the next sentence while the last is still playing (a
/// turn, then a report ahead); interrupting it made the guidance sound chopped,
/// and on web a speak right after a stop is silently dropped.
class SpeechQueue {
  SpeechQueue(this._say, this._hush);

  /// Speaks one sentence and completes once it has been said.
  final Future<void> Function(String text, String locale) _say;
  final Future<void> Function() _hush;

  /// Sentences queued behind more than this are stale by the time they'd play.
  static const maxPending = 2;

  final _pending = Queue<(String, String)>();
  bool _busy = false;
  int _generation = 0; // bumped by stop() so a loop still waiting gives up

  /// The engine may never report that it finished (web, after an error), so a
  /// sentence is given up on after roughly the time it takes to say it.
  static Duration timeoutFor(String text) =>
      Duration(milliseconds: 3000 + text.length * 100);

  void add(String text, String locale) {
    _pending.add((text, locale));
    while (_pending.length > maxPending) {
      _pending.removeFirst();
    }
    if (!_busy) _run();
  }

  Future<void> _run() async {
    _busy = true;
    final generation = _generation;
    while (_pending.isNotEmpty && generation == _generation) {
      final (text, locale) = _pending.removeFirst();
      try {
        await _say(text, locale).timeout(timeoutFor(text));
      } catch (_) {
        // Timed out or failed: move on to the next sentence.
      }
    }
    if (generation == _generation) _busy = false;
  }

  Future<void> stop() async {
    _generation++;
    _pending.clear();
    _busy = false;
    await _hush();
  }
}

/// Text-to-speech through the device (or browser) voice, in the app language when the device has that voice.
class TtsSpeaker implements Speaker {
  FlutterTts? _tts;
  String? _locale;
  late final _queue = SpeechQueue(_say, () async => _tts?.stop());

  Future<FlutterTts> _engine(String locale) async {
    var tts = _tts;
    if (tts == null) {
      tts = _tts = FlutterTts();
      // speak() then completes when the sentence ends, which the queue waits on.
      await tts.awaitSpeakCompletion(true);
    }
    if (_locale != locale) {
      _locale = locale;
      try {
        await tts.setLanguage(
          locale,
        ); // falls back to the default voice if missing
        // flutter_tts doubles the rate on Android (0.5 = normal) but hands it
        // to the browser as is, where 1.0 is normal and 0.5 drags.
        await tts.setSpeechRate(kIsWeb ? 1.0 : 0.5);
      } catch (_) {
        // Voice settings are best effort.
      }
    }
    return tts;
  }

  Future<void> _say(String text, String locale) async {
    try {
      final tts = await _engine(locale);
      await tts.speak(text);
    } catch (_) {
      // No speech engine here (some desktops, unit tests): stay silent.
    }
  }

  @override
  Future<void> speak(String text, [String locale = 'en-US']) async =>
      _queue.add(text, locale);

  @override
  Future<void> stop() async {
    try {
      await _queue.stop();
    } catch (_) {}
  }
}

/// Decides *when* to speak during navigation, without speaking itself.
///
/// For each maneuver it announces once from far away ("In 500 meters, ...") and
/// once when close, plus re-routing and arrival. Feed it every [NavState] in order.
class VoicePlanner {
  VoicePlanner({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const farM = 500.0;
  static const nearM = 150.0;

  /// The close announcement is skipped when the far one was this recent.
  static const nearAfterFar = Duration(seconds: 5);

  /// How far ahead a report is announced.
  static const alertM = 600.0;

  final DateTime Function() _clock;
  RouteOption? _route; // the route _maneuver indexes into
  int? _maneuver; // index of the maneuver we are announcing
  int _stage = 0; // 0 = nothing said yet, 1 = far said, 2 = near said
  DateTime? _farSaidAt;
  bool _arrivedSaid = false;
  bool _reroutingSaid = false;
  final _alerted = <int>{}; // report ids already announced on this trip
  bool _speedingSaid = false;

  void reset() {
    _route = null;
    _maneuver = null;
    _stage = 0;
    _farSaidAt = null;
    _arrivedSaid = false;
    _reroutingSaid = false;
    _alerted.clear();
    _speedingSaid = false;
  }

  /// Announces a report on the road ahead, once per report: "Police, hidden ahead,
  /// 400 meters". Reports off the route (other side of the road) are skipped.
  String? nextAlert(NavState s, List<Report> reports, S strings) {
    if (s.arrived || s.rerouting) return null;
    for (final a in s.reportsAhead(reports, withinM: alertM)) {
      if (a.aheadM < 20) continue; // practically on top of it already
      if (_alerted.add(a.report.id)) {
        final rounded = math.max(50, (a.aheadM / 50).round() * 50);
        return strings.reportAhead(a.report.spokenName(strings), rounded);
      }
    }
    return null;
  }

  /// Warns once when over the limit (by more than [toleranceKmh]), and again only
  /// after the driver has been back at or under the limit. Null tolerance = off.
  String? speeding(NavState s, int? toleranceKmh, S strings) {
    if (toleranceKmh == null || s.arrived) {
      _speedingSaid = false;
      return null;
    }
    if (s.isSpeeding(toleranceKmh)) {
      if (_speedingSaid) return null;
      _speedingSaid = true;
      return strings.speedingVoice(s.speedLimitKmh!);
    }
    final limit = s.speedLimitKmh, speed = s.speedKmh;
    if (limit == null || speed == null || speed <= limit) _speedingSaid = false;
    return null;
  }

  /// What to say for this state, or null for silence.
  String? next(NavState s, S strings) {
    if (s.arrived) {
      if (_arrivedSaid) return null;
      _arrivedSaid = true;
      return strings.arrivedVoice;
    }
    if (s.rerouting) {
      if (_reroutingSaid) return null;
      _reroutingSaid = true;
      return strings.reroutingVoice;
    }
    _reroutingSaid = false;

    final Maneuver? m = s.upcoming;
    if (m == null) return null;
    if (m.type >= 4 && m.type <= 6) {
      return null; // arrival is announced via s.arrived
    }
    if (!identical(s.route, _route)) {
      // New route (start or re-route): its maneuvers are numbered afresh.
      _route = s.route;
      _maneuver = null;
    }
    final idx = s.route.maneuvers.indexOf(m);
    final current = _maneuver;
    // GPS jitter just past a turn can put us back before it for a fix; going
    // back to that maneuver would announce it a second time.
    if (current != null && idx < current) return null;
    if (idx != current) {
      _maneuver = idx;
      _stage = 0;
    }
    final d = s.distToUpcomingM;
    if (d <= nearM) {
      if (_stage >= 2) return null;
      final farJustSaid = _stage == 1 &&
          _clock().difference(_farSaidAt!) < nearAfterFar;
      _stage = 2;
      // Fast driving, or a turn first seen close by: the far announcement has
      // only just played, and saying it again sounds like a repeat.
      return farJustSaid ? null : m.text;
    }
    if (d <= farM) {
      if (_stage >= 1) return null;
      _stage = 1;
      _farSaidAt = _clock();
      final rounded = (d / 50).round() * 50;
      return strings.inDistance(rounded, _lowerFirst(m.text));
    }
    return null;
  }

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}
