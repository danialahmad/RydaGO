import 'dart:math' as math;

import 'package:flutter_tts/flutter_tts.dart';

import '../app/strings.dart';
import '../models/report.dart';
import '../models/route.dart';
import '../state/navigation.dart';

/// Something that can say a sentence out loud. Swapped for a fake in tests.
abstract class Speaker {
  /// [locale] is a BCP-47 tag such as "en-US" or "ms-MY".
  Future<void> speak(String text, [String locale = 'en-US']);
  Future<void> stop();
}

/// Text-to-speech through the device (or browser) voice, in the app language when the device has that voice.
class TtsSpeaker implements Speaker {
  FlutterTts? _tts;
  String? _locale;

  Future<FlutterTts> _engine(String locale) async {
    final tts = _tts ??= FlutterTts();
    if (_locale != locale) {
      _locale = locale;
      try {
        await tts.setLanguage(
          locale,
        ); // falls back to the default voice if missing
        await tts.setSpeechRate(0.5);
      } catch (_) {
        // Voice settings are best effort.
      }
    }
    return tts;
  }

  @override
  Future<void> speak(String text, [String locale = 'en-US']) async {
    try {
      final tts = await _engine(locale);
      await tts.stop();
      await tts.speak(text);
    } catch (_) {
      // No speech engine here (some desktops, unit tests): stay silent.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

/// Decides *when* to speak during navigation, without speaking itself.
///
/// For each maneuver it announces once from far away ("In 500 meters, ...") and
/// once when close, plus re-routing and arrival. Feed it every [NavState] in order.
class VoicePlanner {
  static const farM = 500.0;
  static const nearM = 150.0;

  /// How far ahead a report is announced.
  static const alertM = 600.0;

  int? _maneuver; // index of the maneuver we are announcing
  int _stage = 0; // 0 = nothing said yet, 1 = far said, 2 = near said
  bool _arrivedSaid = false;
  bool _reroutingSaid = false;
  final _alerted = <int>{}; // report ids already announced on this trip
  bool _speedingSaid = false;

  void reset() {
    _maneuver = null;
    _stage = 0;
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
    final idx = s.route.maneuvers.indexOf(m);
    if (idx != _maneuver) {
      _maneuver = idx;
      _stage = 0;
    }
    final d = s.distToUpcomingM;
    if (d <= nearM) {
      if (_stage >= 2) return null;
      _stage = 2;
      return m.text;
    }
    if (d <= farM) {
      if (_stage >= 1) return null;
      _stage = 1;
      final rounded = (d / 50).round() * 50;
      return strings.inDistance(rounded, _lowerFirst(m.text));
    }
    return null;
  }

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}
