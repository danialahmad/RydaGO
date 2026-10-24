import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/place.dart';
import '../models/route.dart';
import '../services/api.dart';
import 'saved_places.dart';
import 'settings.dart';
import 'user_loc.dart';

/// Where the user is going, once they picked a place. Null = just browsing the map.
class DestinationNotifier extends Notifier<Place?> {
  @override
  Place? build() => null;

  void set(Place? p) => state = p;
}

final destinationProvider = NotifierProvider<DestinationNotifier, Place?>(
  DestinationNotifier.new,
);

/// Which of the offered routes is selected in the preview.
class RouteIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int i) => state = i;
}

final routeIndexProvider = NotifierProvider<RouteIndexNotifier, int>(
  RouteIndexNotifier.new,
);

/// Routes to the destination from where the user is now. Empty without one.
final routesProvider = FutureProvider<List<RouteOption>>((ref) async {
  final dest = ref.watch(destinationProvider);
  if (dest == null) return const [];
  // read, not watch: GPS updates must not refetch the routes mid-trip.
  final lang = ref.watch(settingsProvider.select((s) => s.lang));
  return Api.routes(ref.read(userLocProvider).pos, dest.pos, lang);
});

/// Keeps a stored index inside the list (a route type can be missing if the API
/// could only compute some of them).
int clampRouteIndex(int index, int count) =>
    count == 0 ? 0 : math.min(index, count - 1);

class NavigatingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final navigatingProvider = NotifierProvider<NavigatingNotifier, bool>(
  NavigatingNotifier.new,
);

/// A pin dropped with a long press. Also where the next report goes, if set.
class PinNotifier extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  void set(LatLng? p) => state = p;
}

final pinProvider = NotifierProvider<PinNotifier, LatLng?>(PinNotifier.new);

/// Starts a trip to [place]: remembers it in recents and shows the route preview.
void chooseDestination(WidgetRef ref, Place place) {
  ref.read(recentsProvider.notifier).add(place);
  ref.read(routeIndexProvider.notifier).set(0);
  ref.read(pinProvider.notifier).set(null);
  ref.read(destinationProvider.notifier).set(place);
}
