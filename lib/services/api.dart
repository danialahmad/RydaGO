import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/config.dart';
import '../models/place.dart';
import '../models/report.dart';
import '../models/route.dart';

/// Thrown when the API says the login is missing, wrong or expired (HTTP 401).
class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

/// Everything the app asks the Go API for. See docs/API.md for the endpoints.
class Api {
  const Api._();

  // ---- reports ----------------------------------------------------------------
  static Future<List<Report>> nearbyReports(LatLng around) async {
    final res = await http.get(Uri.parse(
        '$kApiUrl/reports?lat=${around.latitude}&lng=${around.longitude}&radius=20000'));
    if (res.statusCode != 200) throw Exception('GET /reports ${res.statusCode}');
    return [
      for (final j in jsonDecode(res.body) as List)
        Report.fromJson(j as Map<String, dynamic>),
    ];
  }

  static Future<Report> createReport({
    required String token,
    required ReportType type,
    String? subtype,
    required LatLng at,
  }) async {
    final res = await http.post(
      Uri.parse('$kApiUrl/reports'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'type': type.name,
        'subtype': ?subtype,
        'lat': at.latitude,
        'lng': at.longitude,
      }),
    );
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode != 201) throw Exception('POST /reports ${res.statusCode}');
    return Report.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ---- routing ----------------------------------------------------------------
  static Future<List<RouteOption>> routes(LatLng from, LatLng to) async {
    final res = await http.get(Uri.parse(
        '$kApiUrl/route?from=${from.latitude},${from.longitude}'
        '&to=${to.latitude},${to.longitude}'));
    if (res.statusCode != 200) throw Exception('GET /route ${res.statusCode}');
    return [
      for (final j in jsonDecode(res.body) as List)
        RouteOption.fromJson(j as Map<String, dynamic>),
    ];
  }

  // ---- address search ---------------------------------------------------------
  static Future<List<Place>> searchPlaces(String q, LatLng near) async {
    final uri = Uri.parse('$kApiUrl/places').replace(queryParameters: {
      'q': q,
      'lat': '${near.latitude}',
      'lng': '${near.longitude}',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('GET /places ${res.statusCode}');
    return [
      for (final j in jsonDecode(res.body) as List)
        Place.fromApi(j as Map<String, dynamic>),
    ];
  }

  // ---- accounts ---------------------------------------------------------------
  /// Returns (token, email). Throws [AuthFailure] with a message fit to show.
  static Future<(String, String)> authenticate({
    required bool register,
    required String email,
    required String password,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kApiUrl/auth/${register ? 'register' : 'login'}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw AuthFailure(body['error'] as String? ?? 'Ralat (${res.statusCode})');
      }
      return (body['token'] as String, body['email'] as String);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('Server tak dapat dihubungi');
    }
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}
