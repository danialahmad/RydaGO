import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/geo.dart';
import '../models/route.dart';
import 'navigation.dart';
import 'user_loc.dart';

// Demo mode: drive the route without moving, through the normal GPS pipeline.
const kDemoSpeedMps = 50 / 3.6; // reported speed (~50 km/h)
const kDemoSpeedUp = 10.0; // how much faster than real time the demo moves

class DemoNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(userLocProvider.notifier).setDemo(on);
    ref.read(recenterProvider.notifier).bump();
  }
}

final demoProvider = NotifierProvider<DemoNotifier, bool>(DemoNotifier.new);

/// While demo mode and navigation are both on, injects a fix every 500 ms that
/// moves along the route being followed. Nothing here talks to NavNotifier
/// directly: navigation just sees GPS fixes, exactly like a real drive.
class DemoDriver extends Notifier<void> {
  Timer? _timer;
  RouteOption? _route;
  List<double> _cum = const [];
  double _along = 0;
  LatLng? _detour; // while set, hold this off-route spot until we are re-routed

  @override
  void build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(navProvider, (_, nav) {
      if (nav == null) {
        _stop();
      } else if (ref.read(demoProvider) && _timer == null) {
        _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
      }
    });
    ref.listen(demoProvider, (_, on) {
      if (!on) _stop();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _route = null;
    _detour = null;
  }

  /// Jumps ~270 m off the route to show re-routing.
  void detour() {
    final nav = ref.read(navProvider);
    if (nav == null || nav.arrived || !ref.read(demoProvider)) return;
    final p = LatLng(nav.pos.latitude + 0.0025, nav.pos.longitude + 0.0004);
    _detour = p;
    ref.read(userLocProvider.notifier).inject(p, speed: kDemoSpeedMps, heading: 90);
  }

  void _tick() {
    final nav = ref.read(navProvider);
    if (nav == null || nav.arrived || !ref.read(demoProvider)) return;
    final user = ref.read(userLocProvider.notifier);

    if (!identical(nav.route, _route)) {
      // First tick, or we were re-routed: start from the beginning of this route.
      _route = nav.route;
      _cum = routeCumulative(nav.route.points);
      _along = 0;
      _detour = null;
    }
    final detour = _detour;
    if (detour != null) {
      user.inject(detour, speed: kDemoSpeedMps, heading: 90);
      return;
    }

    final pts = nav.route.points;
    _along = math.min(_cum.last, _along + kDemoSpeedMps * 0.5 * kDemoSpeedUp);
    var i = 1;
    while (i < _cum.length - 1 && _cum[i] < _along) {
      i++;
    }
    final seg = _cum[i] - _cum[i - 1];
    final t = seg <= 0 ? 0.0 : ((_along - _cum[i - 1]) / seg).clamp(0.0, 1.0);
    final a = pts[i - 1], b = pts[i];
    final pos = LatLng(a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t);
    final dLng = (b.longitude - a.longitude) * math.cos(a.latitude * math.pi / 180);
    final heading =
        (math.atan2(dLng, b.latitude - a.latitude) * 180 / math.pi + 360) % 360;
    user.inject(pos, speed: kDemoSpeedMps, heading: heading);
  }
}

final demoDriverProvider = NotifierProvider<DemoDriver, void>(DemoDriver.new);
