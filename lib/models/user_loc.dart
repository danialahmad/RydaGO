import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/config.dart';

enum LocStatus { starting, active, denied, unavailable }

/// The user's position as far as the app knows it.
class UserLoc {
  const UserLoc(this.status, [this.fix, this.speed, this.heading, this.accuracy]);

  final LocStatus status;
  final LatLng? fix; // last real GPS fix, if any
  final double? speed; // m/s, null if the device cannot tell
  final double? heading; // degrees from north, null if unknown
  final double? accuracy; // metres

  /// The real fix, or the KLCC sample position until there is one.
  LatLng get pos => fix ?? kCenter;
  bool get isReal => fix != null;
}
