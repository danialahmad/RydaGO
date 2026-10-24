import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/config.dart';
import '../../app/theme.dart';
import '../../models/place.dart';
import '../../models/route.dart';
import '../../models/user_loc.dart';
import '../../state/navigation.dart';
import '../../state/reports.dart';
import '../../state/trip.dart';
import '../../state/user_loc.dart';
import 'marker_images.dart';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The OpenFreeMap map with our overlays (routes, reports, destination, the user's
/// dot) redrawn whenever the state behind them changes. It owns every camera move.
class MapView extends ConsumerStatefulWidget {
  const MapView({super.key});

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _imagesReady = false;
  bool _syncing = false;
  bool _dirty = false;
  Circle? _userDot;
  Circle? _userHalo;
  bool _centeredOnFix = false;
  double _bearing = 0;
  String? _initialStyle;
  bool? _appliedDark;

  /// The drive state owns the dot while navigating; otherwise the GPS does.
  LatLng get _userPos => ref.read(navProvider)?.pos ?? ref.read(userLocProvider).pos;

  // ---- drawing -----------------------------------------------------------------

  Future<void> _sync() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _dirty = false;
        await _draw(c);
      } while (_dirty);
    } catch (_) {
      // The map was disposed mid-draw; nothing to do.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _draw(MapLibreMapController c) async {
    final reports = ref.read(reportsProvider);
    final pin = ref.read(pinProvider);
    final dest = ref.read(destinationProvider);
    final routesAsync = ref.read(routesProvider);
    final routes = routesAsync.isLoading
        ? const <RouteOption>[]
        : (routesAsync.value ?? const <RouteOption>[]);
    final selected = clampRouteIndex(ref.read(routeIndexProvider), routes.length);
    final navigating = ref.read(navigatingProvider);
    // While navigating we draw the route being followed, which changes on re-route.
    final navRoute = navigating ? ref.read(navProvider)?.route : null;

    await c.clearLines();
    await c.clearCircles();
    if (_imagesReady) await c.clearSymbols();

    if (dest != null && (navRoute != null || routes.isNotEmpty)) {
      if (navRoute == null) {
        for (var i = 0; i < routes.length; i++) {
          if (i == selected) continue;
          await c.addLine(LineOptions(
              geometry: routes[i].points,
              lineColor: '#FFFFFF',
              lineWidth: 9,
              lineOpacity: 0.9));
          await c.addLine(LineOptions(
              geometry: routes[i].points, lineColor: '#9AA9B8', lineWidth: 5));
        }
      }
      final active = (navRoute ?? routes[selected]).points;
      await c.addLine(
          LineOptions(geometry: active, lineColor: '#FFFFFF', lineWidth: 13));
      await c.addLine(LineOptions(
          geometry: active, lineColor: _hex(AppColors.brand), lineWidth: 8));
    }

    if (_imagesReady) {
      await c.addSymbols([
        for (final r in reports)
          SymbolOptions(
              geometry: r.pos, iconImage: reportImageName(r.type), iconSize: 0.42),
        if (dest != null)
          SymbolOptions(
              geometry: dest.pos, iconImage: destinationImageName, iconSize: 0.46),
        if (pin != null && !navigating)
          SymbolOptions(geometry: pin, iconImage: pinImageName, iconSize: 0.5),
      ]);
    } else {
      // Icon images failed to build: fall back to plain coloured dots.
      await c.addCircles([
        for (final r in reports) _dot(r.pos, r.type.color, 11),
        if (dest != null) _dot(dest.pos, AppColors.danger, 10),
        if (pin != null && !navigating) _dot(pin, const Color(0xFF6C3FC5), 12),
      ]);
    }

    // Kept as handles so the drive can move the dot without a full redraw.
    final here = _userPos;
    _userHalo = await c.addCircle(CircleOptions(
      geometry: here,
      circleColor: _hex(AppColors.brand),
      circleRadius: 22,
      circleOpacity: 0.22,
    ));
    _userDot = await c.addCircle(_dot(here, AppColors.brand, 9, stroke: 3));

    // The first GPS fix can arrive before the map is ready; centre once now.
    if (!_centeredOnFix &&
        ref.read(userLocProvider).isReal &&
        dest == null &&
        !navigating) {
      _centeredOnFix = true;
      await c.animateCamera(CameraUpdate.newLatLngZoom(here, 14));
    }
  }

  CircleOptions _dot(LatLng p, Color color, double radius, {double stroke = 2.5}) =>
      CircleOptions(
        geometry: p,
        circleColor: _hex(color),
        circleRadius: radius,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: stroke,
      );

  Future<void> _registerImages(MapLibreMapController c) async {
    try {
      await registerMarkerImages(c);
      _imagesReady = true;
    } catch (_) {
      _imagesReady = false; // _draw falls back to circles
    }
  }

  // ---- camera ------------------------------------------------------------------

  /// Moves the dot and keeps the camera on it, turned to the direction of travel
  /// while we are actually moving (GPS heading is noise when standing still).
  Future<void> _follow(NavState n) async {
    final c = _controller;
    if (c == null) return;
    if ((n.speedKmh ?? 0) > 5 && n.heading != null) _bearing = n.heading!;
    try {
      final dot = _userDot, halo = _userHalo;
      if (dot != null) await c.updateCircle(dot, CircleOptions(geometry: n.pos));
      if (halo != null) await c.updateCircle(halo, CircleOptions(geometry: n.pos));
      await c.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: n.pos, zoom: 17, bearing: _bearing, tilt: 45)));
    } catch (_) {
      // Cosmetic; the next fix tries again.
    }
  }

  Future<void> _onUserLoc(UserLoc? prev, UserLoc next) async {
    if (ref.read(navProvider) != null) return; // the drive owns the dot
    final c = _controller;
    if (c == null) return;
    try {
      final dot = _userDot, halo = _userHalo;
      if (dot != null) await c.updateCircle(dot, CircleOptions(geometry: next.pos));
      if (halo != null) await c.updateCircle(halo, CircleOptions(geometry: next.pos));
      final firstFix = next.isReal && !_centeredOnFix;
      if (firstFix && ref.read(destinationProvider) == null) {
        _centeredOnFix = true;
        await c.animateCamera(CameraUpdate.newLatLngZoom(next.pos, 14));
      }
    } catch (_) {
      // Cosmetic; the next fix tries again.
    }
  }

  Future<void> _recenter() async {
    if (ref.read(navigatingProvider)) return;
    try {
      await _controller
          ?.animateCamera(CameraUpdate.newLatLngZoom(_userPos, 15.5));
    } catch (_) {}
  }

  /// Frames the user and the destination in the part of the screen the route
  /// sheet leaves free. newLatLngBounds pads differently on web (it scales by the
  /// device pixel ratio), so centre and zoom are computed here.
  Future<void> _fitDestination(Place? dest) async {
    final c = _controller;
    if (c == null) return;
    if (dest == null) {
      await c.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: _userPos, zoom: 14, bearing: 0, tilt: 0)));
      return;
    }
    double rad(double d) => d * math.pi / 180;
    final a = _userPos, b = dest.pos;
    final midLat = (a.latitude + b.latitude) / 2;
    final midLng = (a.longitude + b.longitude) / 2;
    final worldKm = 40075.0 * math.cos(rad(midLat));
    final dLatKm = (a.latitude - b.latitude).abs() * 111.0;
    final dLngKm = (a.longitude - b.longitude).abs() * 111.0 * math.cos(rad(midLat));
    final spanKm = math.max(math.max(dLatKm, dLngKm), 0.5);
    const fitPx = 260.0;
    final zoom =
        (math.log(worldKm * fitPx / (512 * spanKm)) / math.ln2).clamp(3.0, 16.0);
    final kmPerPx = worldKm / (512 * math.pow(2, zoom));
    const sheetShiftPx = 170.0; // lift the route above the bottom sheet
    final centerLat = midLat - sheetShiftPx * kmPerPx / 111.0;
    try {
      await c.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
          target: LatLng(centerLat, midLng), zoom: zoom, bearing: 0, tilt: 0)));
    } catch (_) {
      // Camera moves are cosmetic; ignore failures.
    }
  }

  // ---- widget ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(reportsProvider, (_, _) => _sync());
    ref.listen(pinProvider, (_, _) => _sync());
    ref.listen(routeIndexProvider, (_, _) => _sync());
    ref.listen(routesProvider, (_, _) => _sync());
    ref.listen(navProvider, (prev, next) {
      if (next == null) return;
      // A re-route swaps the route object: redraw the blue line.
      if (!identical(prev?.route, next.route)) _sync();
      _follow(next);
    });
    ref.listen(userLocProvider, _onUserLoc);
    ref.listen(recenterProvider, (_, _) => _recenter());
    ref.listen(destinationProvider, (_, next) {
      _sync();
      _fitDestination(next);
    });
    ref.listen(navigatingProvider, (_, nav) {
      _sync();
      if (nav) {
        _controller?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
            target: _userPos, zoom: 17, bearing: _bearing, tilt: 45)));
      } else {
        _bearing = 0;
        _fitDestination(ref.read(destinationProvider));
      }
    });

    // The widget gets one fixed style; later light/dark changes go through
    // setStyle, because changing the widget's style makes the plugin reset its
    // other options (it moves the map credit back over our bottom panel).
    final dark = Theme.of(context).brightness == Brightness.dark;
    _initialStyle ??= dark ? kMapStyleDark : kMapStyleLight;
    if (_appliedDark != null && _appliedDark != dark) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _styleReady = false;
        _controller?.setStyle(dark ? kMapStyleDark : kMapStyleLight);
      });
    }
    _appliedDark = dark;
    return MapLibreMap(
      styleString: _initialStyle!,
      initialCameraPosition: const CameraPosition(target: kCenter, zoom: 13),
      compassEnabled: false,
      // Top right keeps the required OpenStreetMap/OpenFreeMap credit clear of the
      // bottom panels. (Margins are not supported on web; it collapses to an "i".)
      attributionButtonPosition: AttributionButtonPosition.topRight,
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: () async {
        // Runs for the first style and again whenever light/dark switches.
        _styleReady = false;
        final c = _controller;
        if (c != null) await _registerImages(c);
        _styleReady = true;
        _sync();
      },
      // A long press drops a pin: the place to "go here" or "report here".
      onMapLongClick: (_, latLng) {
        if (!ref.read(navigatingProvider)) {
          ref.read(pinProvider.notifier).set(latLng);
        }
      },
    );
  }
}
