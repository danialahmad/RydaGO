import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/config.dart';
import '../../app/theme.dart';
import '../../models/geo.dart';
import '../../models/report.dart';
import '../../models/route.dart';
import '../../models/user_loc.dart';
import '../../services/map_style.dart';
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

/// Camera tilt while driving: 0 = flat top-down, heading-up, like Waze. A tilted
/// 3D view makes it hard to see which lane or exit is meant.
const kNavTilt = 0.0;

/// Zoom while driving, close enough to read lanes and junctions (17 was too wide).
const kNavZoom = 18.0;

/// The dot sits in the lower part of the screen, with more road ahead than behind.
const kNavAheadM = 45.0;

class _MapViewState extends ConsumerState<MapView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _imagesReady = false;
  bool _syncing = false;
  bool _dirty = false;
  Circle? _userDot;
  Circle? _userHalo;
  // A fill, not a symbol: symbols fade back in each time they move on web, so an
  // arrow icon blinked on every fix.
  Fill? _userArrow; // direction of travel, drawn on the dot while navigating
  List<Symbol> _reportSymbols = const [];
  List<Circle> _reportDots = const [];
  String _reportsKey = ''; // what the drawn report markers show
  bool _centeredOnFix = false;
  double _bearing = 0;
  String? _initialStyle;
  String? _lightStyle; // flattened style JSON, or the plain URL if it could not be fetched
  String? _darkStyle;
  bool? _appliedDark;
  Size _viewSize = Size.zero;
  Timer? _fitTimer;

  /// Kept clear at the top when framing a route: the menu button and GPS chip.
  static const _kTopClearPx = 76.0;

  @override
  void initState() {
    super.initState();
    _loadStyles();
  }

  Future<void> _loadStyles() async {
    final both = await Future.wait([loadFlatStyle(kMapStyleLight), loadFlatStyle(kMapStyleDark)]);
    if (!mounted) return;
    setState(() {
      _lightStyle = both[0] ?? kMapStyleLight;
      _darkStyle = both[1] ?? kMapStyleDark;
    });
  }

  @override
  void dispose() {
    _fitTimer?.cancel();
    super.dispose();
  }

  /// The drive state owns the dot while navigating; otherwise the GPS does.
  LatLng get _userPos => ref.read(navProvider)?.pos ?? ref.read(userLocProvider).pos;

  // ---- drawing -----------------------------------------------------------------

  /// Redraws everything, or with [reportsOnly] just the report markers (the
  /// reports refresh on a timer; redrawing the route each time made it blink).
  Future<void> _sync({bool reportsOnly = false}) async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    if (_syncing) {
      _dirty = true; // the full redraw that follows covers the reports too
      return;
    }
    _syncing = true;
    try {
      var full = !reportsOnly;
      do {
        if (full) {
          _dirty = false;
          await _draw(c);
        } else {
          await _drawReports(c);
        }
        full = true;
      } while (_dirty);
    } catch (_) {
      // The map was disposed mid-draw; nothing to do.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _draw(MapLibreMapController c) async {
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
    await c.clearFills();
    if (_imagesReady) await c.clearSymbols();
    _reportSymbols = const [];
    _reportDots = const [];

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
        if (dest != null)
          SymbolOptions(
              geometry: dest.pos, iconImage: destinationImageName, iconSize: 0.46),
        if (pin != null && !navigating)
          SymbolOptions(geometry: pin, iconImage: pinImageName, iconSize: 0.5),
      ]);
    } else {
      // Icon images failed to build: fall back to plain coloured dots.
      await c.addCircles([
        if (dest != null) _dot(dest.pos, AppColors.danger, 10),
        if (pin != null && !navigating) _dot(pin, const Color(0xFF6C3FC5), 12),
      ]);
    }
    await _drawReports(c);

    // Kept as handles so the drive can move the dot without a full redraw.
    final here = _userPos;
    _userHalo = await c.addCircle(CircleOptions(
      geometry: here,
      circleColor: _hex(AppColors.brand),
      circleRadius: 22,
      circleOpacity: 0.22,
    ));
    _userDot = await c.addCircle(_dot(here, AppColors.brand, navigating ? 12 : 9, stroke: 3));
    _userArrow = navigating
        ? await c.addFill(FillOptions(
            geometry: [arrowPolygon(here, _bearing)],
            fillColor: '#FFFFFF',
            fillOutlineColor: '#FFFFFF'))
        : null;

    // The first GPS fix can arrive before the map is ready; centre once now.
    if (!_centeredOnFix &&
        ref.read(userLocProvider).isReal &&
        dest == null &&
        !navigating) {
      _centeredOnFix = true;
      await c.animateCamera(CameraUpdate.newLatLngZoom(here, 14));
    }
  }

  /// Replaces the report markers, leaving the route, destination and dot alone.
  Future<void> _drawReports(MapLibreMapController c) async {
    final reports = ref.read(reportsProvider);
    if (_reportSymbols.isNotEmpty) await c.removeSymbols(_reportSymbols);
    if (_reportDots.isNotEmpty) await c.removeCircles(_reportDots);
    _reportSymbols = const [];
    _reportDots = const [];
    _reportsKey = _keyOf(reports);
    if (reports.isEmpty) return;
    if (_imagesReady) {
      _reportSymbols = await c.addSymbols([
        for (final r in reports)
          SymbolOptions(
              geometry: r.pos, iconImage: reportImageName(r.type), iconSize: 0.42),
      ]);
    } else {
      _reportDots = await c.addCircles([
        for (final r in reports) _dot(r.pos, r.type.color, 11),
      ]);
    }
  }

  /// Everything a report marker shows. A refresh that changes only votes
  /// leaves the markers as they are.
  static String _keyOf(List<Report> reports) => [
        for (final r in reports) '${r.id}:${r.type.name}:${r.lat},${r.lng}',
      ].join('|');

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
    final camera = CameraUpdate.newCameraPosition(
        CameraPosition(
            target: offsetAhead(n.pos, _bearing, kNavAheadM),
            zoom: kNavZoom,
            bearing: _bearing,
            tilt: kNavTilt));
    try {
      // On web animateCamera is a flyTo, which dips the zoom on its way: every
      // fix pulled the map just under zoom 17, swapping tile levels, and it
      // blinked. Jump instead; the camera follows the dot fix by fix.
      if (kIsWeb) {
        await c.moveCamera(camera);
      } else {
        await c.animateCamera(camera);
      }
      final dot = _userDot, halo = _userHalo, arrow = _userArrow;
      if (dot != null) await c.updateCircle(dot, CircleOptions(geometry: n.pos));
      if (halo != null) await c.updateCircle(halo, CircleOptions(geometry: n.pos));
      if (arrow != null) {
        await c.updateFill(
            arrow, FillOptions(geometry: [arrowPolygon(n.pos, _bearing)]));
      }
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

  /// Frames the trip after the route sheet has settled: it animates in, then
  /// grows when the routes arrive, and each change restarts the wait.
  void _scheduleFit() {
    _fitTimer?.cancel();
    _fitTimer = Timer(const Duration(milliseconds: 300), _fitTrip);
  }

  /// Shows the routes on offer (or just the user and the destination while they
  /// load) in the middle of the map the panels leave visible. Computed here:
  /// newLatLngBounds pads differently on web (it scales by the device pixel ratio).
  Future<void> _fitTrip() async {
    final c = _controller;
    if (c == null || ref.read(navigatingProvider)) return;
    final dest = ref.read(destinationProvider);
    final CameraPosition camera;
    if (dest == null) {
      camera = CameraPosition(target: _userPos, zoom: 14, bearing: 0, tilt: 0);
    } else {
      if (_viewSize.isEmpty) return;
      final routesAsync = ref.read(routesProvider);
      final routes = routesAsync.isLoading
          ? const <RouteOption>[]
          : (routesAsync.value ?? const <RouteOption>[]);
      final fit = fitCamera(
        [_userPos, dest.pos, for (final r in routes) ...r.points],
        _viewSize.width,
        _viewSize.height,
        top: _kTopClearPx,
        bottom: ref.read(mapBottomInsetProvider) + 24,
        side: 40,
      );
      camera = CameraPosition(target: fit.center, zoom: fit.zoom, bearing: 0, tilt: 0);
    }
    try {
      await c.animateCamera(CameraUpdate.newCameraPosition(camera));
    } catch (_) {
      // Camera moves are cosmetic; ignore failures.
    }
  }

  // ---- widget ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(reportsProvider, (_, next) {
      // Refreshed every 15 s, mostly with the same reports.
      if (_keyOf(next) != _reportsKey) _sync(reportsOnly: true);
    });
    ref.listen(pinProvider, (_, _) => _sync());
    ref.listen(routeIndexProvider, (_, _) => _sync());
    ref.listen(routesProvider, (_, next) {
      _sync();
      if (!next.isLoading) _scheduleFit();
    });
    ref.listen(mapBottomInsetProvider, (_, _) {
      if (ref.read(destinationProvider) != null && !ref.read(navigatingProvider)) {
        _scheduleFit();
      }
    });
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
      if (next == null) {
        _fitTimer?.cancel();
        _fitTrip();
      } else {
        _scheduleFit();
      }
    });
    ref.listen(navigatingProvider, (_, nav) {
      _sync();
      if (nav) {
        _controller?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
            target: offsetAhead(_userPos, _bearing, kNavAheadM),
            zoom: kNavZoom,
            bearing: _bearing,
            tilt: kNavTilt)));
      } else {
        _bearing = 0;
        _scheduleFit();
      }
    });

    // The widget gets one fixed style; later light/dark changes go through
    // setStyle, because changing the widget's style makes the plugin reset its
    // other options (it moves the map credit back over our bottom panel).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final light = _lightStyle, darkStyle = _darkStyle;
    if (light == null || darkStyle == null) return const SizedBox.expand(); // style still loading
    _initialStyle ??= dark ? darkStyle : light;
    if (_appliedDark != null && _appliedDark != dark) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _styleReady = false;
        _controller?.setStyle(dark ? darkStyle : light);
      });
    }
    _appliedDark = dark;
    return LayoutBuilder(builder: (context, constraints) {
      _viewSize = constraints.biggest; // for framing routes; no rebuild needed
      return _map();
    });
  }

  Widget _map() {
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
