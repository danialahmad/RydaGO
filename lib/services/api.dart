import '../app/strings.dart';

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

/// Thrown when voting on a report the user made themselves (HTTP 403).
class OwnReportException implements Exception {
  const OwnReportException();
}

/// The server refused a report: this user already reported the same thing here.
class DuplicateReportException implements Exception {
  const DuplicateReportException();
}

/// The server says slow down (HTTP 429).
class RateLimitedException implements Exception {
  const RateLimitedException();
}

/// The password given to delete an account was wrong.
class WrongPasswordException implements Exception {
  const WrongPasswordException();
}

/// Everything the app asks the Go API for. See docs/API.md for the endpoints.
class Api {
  const Api._();

  // ---- reports ----------------------------------------------------------------
  /// With a [token] the answer marks the user's own reports (`mine`).
  static Future<List<Report>> nearbyReports(
    LatLng around, {
    String? token,
  }) async {
    final res = await http.get(
      Uri.parse(
        '$kApiUrl/reports?lat=${around.latitude}&lng=${around.longitude}&radius=20000',
      ),
      headers: {'Authorization': ?(token == null ? null : 'Bearer $token')},
    );
    if (res.statusCode != 200) {
      throw Exception('GET /reports ${res.statusCode}');
    }
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
    if (res.statusCode == 409) throw const DuplicateReportException();
    if (res.statusCode == 429) throw const RateLimitedException();
    if (res.statusCode != 201) {
      throw Exception('POST /reports ${res.statusCode}');
    }
    final r = Report.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    return Report(
      r.type,
      r.lat,
      r.lng,
      id: r.id,
      subtype: r.subtype,
      mine: true,
    );
  }

  /// Takes down the signed-in user's own report. A report that is already gone
  /// (404) counts as done.
  static Future<void> deleteReport({required String token, required int reportId}) async {
    final res = await http.delete(
      Uri.parse('$kApiUrl/reports/$reportId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode != 204 && res.statusCode != 404) {
      throw Exception('DELETE /reports/$reportId ${res.statusCode}');
    }
  }

  // ---- live trip sharing ------------------------------------------------------
  static Map<String, String> _authJson(String token) =>
      {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

  static Map<String, Object> _shareBody({
    required String destName,
    required double destLat,
    required double destLng,
    required double lat,
    required double lng,
    required int etaMinutes,
  }) => {
    'dest_name': destName,
    'dest_lat': destLat,
    'dest_lng': destLng,
    'lat': lat,
    'lng': lng,
    'eta_minutes': etaMinutes,
  };

  /// Starts a live trip link and returns its token.
  static Future<String> createShare({
    required String token,
    required String destName,
    required double destLat,
    required double destLng,
    required double lat,
    required double lng,
    required int etaMinutes,
  }) async {
    final res = await http.post(
      Uri.parse('$kApiUrl/shares'),
      headers: _authJson(token),
      body: jsonEncode(_shareBody(destName: destName, destLat: destLat, destLng: destLng, lat: lat, lng: lng, etaMinutes: etaMinutes)),
    );
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode != 201) throw Exception('POST /shares ${res.statusCode}');
    return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
  }

  static Future<void> updateShare({
    required String token,
    required String shareToken,
    required String destName,
    required double destLat,
    required double destLng,
    required double lat,
    required double lng,
    required int etaMinutes,
  }) async {
    final res = await http.put(
      Uri.parse('$kApiUrl/shares/$shareToken'),
      headers: _authJson(token),
      body: jsonEncode(_shareBody(destName: destName, destLat: destLat, destLng: destLng, lat: lat, lng: lng, etaMinutes: etaMinutes)),
    );
    if (res.statusCode != 204) throw Exception('PUT /shares ${res.statusCode}');
  }

  static Future<void> endShare({required String token, required String shareToken}) async {
    await http.delete(
      Uri.parse('$kApiUrl/shares/$shareToken'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// Deletes the signed-in user's account with all their reports and votes.
  static Future<void> deleteAccount({required String token, required String password}) async {
    final res = await http.delete(
      Uri.parse('$kApiUrl/me'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode == 403) throw const WrongPasswordException();
    if (res.statusCode != 204) throw Exception('DELETE /me ${res.statusCode}');
  }

  /// "Masih ada?": [stillThere] true = it is still there, false = it is gone.
  /// Returns the new (up, down) counts.
  static Future<(int, int)> vote({
    required String token,
    required int reportId,
    required bool stillThere,
  }) async {
    final res = await http.post(
      Uri.parse('$kApiUrl/reports/$reportId/vote'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'vote': stillThere ? 'up' : 'down'}),
    );
    if (res.statusCode == 401) throw const UnauthorizedException();
    if (res.statusCode == 403) throw const OwnReportException();
    if (res.statusCode != 200) {
      throw Exception('POST /reports/$reportId/vote ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['up'] as num).toInt(), (j['down'] as num).toInt());
  }

  // ---- routing ----------------------------------------------------------------
  static Future<List<RouteOption>> routes(
    LatLng from,
    LatLng to,
    AppLang lang, {
    bool avoidHighways = false,
  }) async {
    final res = await http.get(
      Uri.parse(
        '$kApiUrl/route?from=${from.latitude},${from.longitude}'
        '&to=${to.latitude},${to.longitude}&lang=${lang.code}'
        '${avoidHighways ? '&avoid=highways' : ''}',
      ),
    );
    if (res.statusCode != 200) throw Exception('GET /route ${res.statusCode}');
    return [
      for (final j in jsonDecode(res.body) as List)
        RouteOption.fromJson(j as Map<String, dynamic>),
    ];
  }

  // ---- address search ---------------------------------------------------------
  static Future<List<Place>> searchPlaces(
    String q,
    LatLng near,
    AppLang lang,
  ) async {
    final uri = Uri.parse('$kApiUrl/places').replace(
      queryParameters: {
        'q': q,
        'lat': '${near.latitude}',
        'lng': '${near.longitude}',
        'lang': lang.code,
      },
    );
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
        throw AuthFailure(res.statusCode, body['error'] as String?);
      }
      return (body['token'] as String, body['email'] as String);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(0, null); // 0 = could not reach the server
    }
  }
}

/// A failed sign-in or registration. The UI turns [status] into text in the app
/// language with `S.authError`; 0 means the server could not be reached.
class AuthFailure implements Exception {
  const AuthFailure(this.status, this.serverMessage);
  final int status;
  final String? serverMessage;
}
