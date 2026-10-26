import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/config.dart';
import '../services/api.dart';
import 'auth.dart';
import 'navigation.dart';
import 'trip.dart';

/// How often the shared position and ETA are refreshed while driving.
const kShareEvery = Duration(seconds: 10);

/// A live trip link. While [token] is set, the position and ETA are sent to the
/// server every [kShareEvery] so friends opening the link see where we are. It
/// ends by itself when navigation stops or we arrive.
class ShareNotifier extends Notifier<String?> {
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String? build() {
    ref.listen(navProvider, (_, nav) {
      final token = state;
      if (token == null) return;
      if (nav == null || nav.arrived) {
        end();
        return;
      }
      final now = DateTime.now();
      if (now.difference(_lastSent) < kShareEvery) return;
      _lastSent = now;
      final auth = ref.read(authProvider);
      if (auth == null) return;
      // Best effort: a missed update is replaced by the next one.
      Api.updateShare(
        token: auth.token,
        shareToken: token,
        lat: nav.pos.latitude,
        lng: nav.pos.longitude,
        etaMinutes: nav.remainingMin,
        destName: ref.read(destinationProvider)?.name ?? '',
        destLat: ref.read(destinationProvider)?.pos.latitude ?? 0,
        destLng: ref.read(destinationProvider)?.pos.longitude ?? 0,
      ).catchError((_) {});
    });
    return null;
  }

  /// Starts sharing the current trip. Returns the public link, or null when not
  /// signed in, not navigating, or the server said no.
  Future<String?> start() async {
    final auth = ref.read(authProvider);
    final nav = ref.read(navProvider);
    final dest = ref.read(destinationProvider);
    if (auth == null || nav == null || dest == null) return null;
    try {
      final token = await Api.createShare(
        token: auth.token,
        destName: dest.name,
        destLat: dest.pos.latitude,
        destLng: dest.pos.longitude,
        lat: nav.pos.latitude,
        lng: nav.pos.longitude,
        etaMinutes: nav.remainingMin,
      );
      _lastSent = DateTime.now();
      state = token;
      return linkFor(token);
    } catch (_) {
      return null;
    }
  }

  Future<void> end() async {
    final token = state;
    final auth = ref.read(authProvider);
    state = null;
    if (token == null || auth == null) return;
    try {
      await Api.endShare(token: auth.token, shareToken: token);
    } catch (_) {}
  }

  /// The link a friend opens, on the same server the app talks to.
  static String linkFor(String token) => '$kApiUrl/s/$token';
}

final shareProvider = NotifierProvider<ShareNotifier, String?>(ShareNotifier.new);
