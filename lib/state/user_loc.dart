import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/config.dart';
import '../models/user_loc.dart';

/// Tracks the device GPS. In demo mode it ignores the GPS and accepts fixes from
/// the demo driver instead, so everything downstream runs the same code.
class UserLocNotifier extends Notifier<UserLoc> {
  StreamSubscription<Position>? _sub;
  bool _demo = false;

  @override
  UserLoc build() {
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(start);
    return const UserLoc(LocStatus.starting);
  }

  /// Demo mode swaps the device GPS for fixes injected by `DemoDriver`.
  Future<void> setDemo(bool on) async {
    _demo = on;
    await _sub?.cancel();
    _sub = null;
    if (on) {
      state = const UserLoc(LocStatus.active, kCenter, 0, 0, 5);
    } else {
      state = const UserLoc(LocStatus.starting); // no fix until the real GPS answers
      await start();
    }
  }

  /// Demo mode only: pretend the device reported this position.
  void inject(LatLng p, {double speed = 0, double? heading}) {
    if (!_demo) return;
    state = UserLoc(LocStatus.active, p, speed, heading, 5);
  }

  /// (Re)starts location tracking and asks for permission if needed.
  Future<void> start() async {
    if (_demo) return;
    await _sub?.cancel();
    _sub = null;
    state = UserLoc(LocStatus.starting, state.fix);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = UserLoc(LocStatus.unavailable, state.fix);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        state = UserLoc(LocStatus.denied, state.fix);
        return;
      }
      if (_demo) return; // demo was switched on while we waited for permission
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(
        (p) => state = UserLoc(
          LocStatus.active,
          LatLng(p.latitude, p.longitude),
          p.speed,
          p.heading,
          p.accuracy,
        ),
        onError: (_) => state = UserLoc(LocStatus.unavailable, state.fix),
      );
    } catch (_) {
      state = UserLoc(LocStatus.unavailable, state.fix);
    }
  }
}

final userLocProvider =
    NotifierProvider<UserLocNotifier, UserLoc>(UserLocNotifier.new);

/// Bumped by the "my location" button; the map listens and re-centres.
class RecenterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final recenterProvider = NotifierProvider<RecenterNotifier, int>(RecenterNotifier.new);
