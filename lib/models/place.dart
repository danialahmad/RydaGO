import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// A destination: a search result, a saved place, or a dropped pin.
class Place {
  const Place(this.name, this.area, this.icon, this.pos);
  final String name;
  final String area;
  final IconData icon;
  final LatLng pos;

  Map<String, dynamic> toJson() => {
        'name': name,
        'area': area,
        'lat': pos.latitude,
        'lng': pos.longitude,
      };

  /// Used for places stored on the device; the icon is not stored.
  static Place fromJson(Map<String, dynamic> j) => Place(
        j['name'] as String,
        j['area'] as String,
        Icons.place,
        LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      );

  /// Builds a place from one entry of the API's `GET /places` response.
  static Place fromApi(Map<String, dynamic> j) => Place(
        j['name'] as String,
        j['area'] as String,
        iconForCategory(j['category'] as String, j['type'] as String),
        LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      );

  /// Same place if the name matches and the coordinates are within ~50 m.
  bool isSameAs(Place o) =>
      name == o.name &&
      (pos.latitude - o.pos.latitude).abs() < 0.0005 &&
      (pos.longitude - o.pos.longitude).abs() < 0.0005;
}

/// Picks an icon from Nominatim's category/type, e.g. ("aeroway", "aerodrome").
IconData iconForCategory(String category, String type) {
  if (category == 'aeroway') return Icons.flight;
  if (category == 'railway' || category == 'public_transport') return Icons.train;
  if (category == 'shop' || type == 'mall' || type == 'marketplace') {
    return Icons.shopping_bag;
  }
  if (category == 'tourism') return Icons.landscape;
  if (category == 'highway') return Icons.add_road;
  if (category == 'place' || category == 'boundary') return Icons.location_city;
  switch (type) {
    case 'restaurant':
    case 'cafe':
    case 'fast_food':
      return Icons.restaurant;
    case 'fuel':
      return Icons.local_gas_station;
    case 'school':
    case 'university':
    case 'college':
      return Icons.school;
    case 'hospital':
    case 'clinic':
      return Icons.local_hospital;
    case 'place_of_worship':
      return Icons.mosque;
    case 'parking':
      return Icons.local_parking;
  }
  return Icons.place;
}
