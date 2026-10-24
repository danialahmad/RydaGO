import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/report.dart';
import '../services/api.dart';
import 'auth.dart';
import 'trip.dart';
import 'user_loc.dart';

enum AddResult { ok, unauthorized, failed }

/// Reports near the user, refreshed every 15 seconds.
class ReportsNotifier extends Notifier<List<Report>> {
  @override
  List<Report> build() {
    Future.microtask(refresh);
    final timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    ref.onDispose(timer.cancel);
    // The first real fix moves us away from the fallback: reload around it.
    ref.listen(userLocProvider, (prev, next) {
      if (prev?.isReal != next.isReal) refresh();
    });
    return const [];
  }

  Future<void> refresh() async {
    try {
      state = await Api.nearbyReports(ref.read(userLocProvider).pos);
    } catch (_) {
      // Keep whatever we had; the next refresh will retry.
    }
  }

  /// Sends a report from the dropped pin if there is one, otherwise from where
  /// the user is.
  Future<AddResult> add(ReportType type, {String? subtype}) async {
    final token = ref.read(authProvider)?.token;
    if (token == null) return AddResult.unauthorized;
    final at = ref.read(pinProvider) ?? ref.read(userLocProvider).pos;
    try {
      final r = await Api.createReport(
          token: token, type: type, subtype: subtype, at: at);
      state = [...state, r];
      ref.read(pinProvider.notifier).set(null);
      return AddResult.ok;
    } on UnauthorizedException {
      return AddResult.unauthorized;
    } catch (_) {
      return AddResult.failed;
    }
  }
}

final reportsProvider =
    NotifierProvider<ReportsNotifier, List<Report>>(ReportsNotifier.new);
