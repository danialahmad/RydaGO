import 'dart:math' as math;

import 'package:flutter_tts/flutter_tts.dart';

import '../models/report.dart';
import '../models/route.dart';
import '../state/navigation.dart';

/// Something that can say a sentence out loud. Swapped for a fake in tests.
abstract class Speaker {
  Future<void> speak(String text);
  Future<void> stop();
}

/// Text-to-speech through the device (or browser) voice, in Malay when available.
class TtsSpeaker implements Speaker {
  FlutterTts? _tts;
  bool _ready = false;

  Future<FlutterTts> _engine() async {
    final tts = _tts ??= FlutterTts();
    if (!_ready) {
      _ready = true;
      try {
        await tts.setLanguage('ms-MY'); // falls back to the default voice if missing
        await tts.setSpeechRate(0.5);
      } catch (_) {
        // Voice settings are best effort.
      }
    }
    return tts;
  }

  @override
  Future<void> speak(String text) async {
    try {
      final tts = await _engine();
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
/// For each maneuver it announces once from far away ("Dalam 500 meter, ...") and
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

  /// Announces a report on the road ahead, once per report: "Polis tersembunyi di
  /// hadapan, 400 meter". Reports off the route (other side of the road) are skipped.
  String? nextAlert(NavState s, List<Report> reports) {
    if (s.arrived || s.rerouting) return null;
    for (final a in s.reportsAhead(reports, withinM: alertM)) {
      if (a.aheadM < 20) continue; // practically on top of it already
      if (_alerted.add(a.report.id)) {
        final rounded = math.max(50, (a.aheadM / 50).round() * 50);
        return '${a.report.spokenName} di hadapan, $rounded meter';
      }
    }
    return null;
  }

  /// Warns once when over the limit (by more than [toleranceKmh]), and again only
  /// after the driver has been back at or under the limit. Null tolerance = off.
  String? speeding(NavState s, int? toleranceKmh) {
    if (toleranceKmh == null || s.arrived) {
      _speedingSaid = false;
      return null;
    }
    if (s.isSpeeding(toleranceKmh)) {
      if (_speedingSaid) return null;
      _speedingSaid = true;
      return 'Anda melebihi had laju, ${s.speedLimitKmh} kilometer sejam';
    }
    final limit = s.speedLimitKmh, speed = s.speedKmh;
    if (limit == null || speed == null || speed <= limit) _speedingSaid = false;
    return null;
  }

  /// What to say for this state, or null for silence.
  String? next(NavState s) {
    if (s.arrived) {
      if (_arrivedSaid) return null;
      _arrivedSaid = true;
      return 'Anda telah sampai di destinasi';
    }
    if (s.rerouting) {
      if (_reroutingSaid) return null;
      _reroutingSaid = true;
      return 'Mengira semula laluan';
    }
    _reroutingSaid = false;

    final Maneuver? m = s.upcoming;
    if (m == null) return null;
    if (m.type >= 4 && m.type <= 6) return null; // arrival is announced via s.arrived
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
      return 'Dalam $rounded meter, ${_lowerFirst(m.text)}';
    }
    return null;
  }

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}
