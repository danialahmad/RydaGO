import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/report.dart';
import '../services/api.dart';
import 'auth.dart';
import 'trip.dart';
import 'user_loc.dart';

enum AddResult { ok, unauthorized, failed }

enum VoteResult { ok, unauthorized, ownReport, failed }

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
    // Logging in or out changes which reports are marked as the user's own.
    ref.listen(authProvider, (_, _) => refresh());
    return const [];
  }

  Future<void> refresh() async {
    try {
      state = await Api.nearbyReports(
        ref.read(userLocProvider).pos,
        token: ref.read(authProvider)?.token,
      );
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

  /// Answers "Masih ada?" for [report]. A report that ends up with three more
  /// "gone" than "still there" votes disappears at once, as it will on the server.
  Future<VoteResult> vote(Report report, {required bool stillThere}) async {
    final token = ref.read(authProvider)?.token;
    if (token == null) return VoteResult.unauthorized;
    try {
      final (up, down) = await Api.vote(
          token: token, reportId: report.id, stillThere: stillThere);
      ref.read(votedReportsProvider.notifier).add(report.id);
      state = [
        for (final r in state)
          if (r.id != report.id)
            r
          else if (down - up < 3)
            r.copyWith(up: up, down: down),
      ];
      return VoteResult.ok;
    } on UnauthorizedException {
      return VoteResult.unauthorized;
    } on OwnReportException {
      ref.read(votedReportsProvider.notifier).add(report.id); // stop asking
      return VoteResult.ownReport;
    } catch (_) {
      return VoteResult.failed;
    }
  }
}

final reportsProvider =
    NotifierProvider<ReportsNotifier, List<Report>>(ReportsNotifier.new);

/// Reports the user has already answered "Masih ada?" for in this session, so the
/// prompt does not come back for them.
class VotedReportsNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void add(int id) => state = {...state, id};
}

final votedReportsProvider =
    NotifierProvider<VotedReportsNotifier, Set<int>>(VotedReportsNotifier.new);
