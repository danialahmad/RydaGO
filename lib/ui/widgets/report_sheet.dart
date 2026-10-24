import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../models/report.dart';
import '../../state/auth.dart';
import '../../state/reports.dart';
import '../screens/login_screen.dart';

/// Opens the report sheet, or the login screen first if the user is signed out.
void openReportFlow(BuildContext context, WidgetRef ref) {
  if (ref.read(authProvider) == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.of(context).signInFirst)));
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const ReportSheet(),
  );
}

/// Two steps: pick what you saw, then (for most kinds) pick the detail. One tap
/// on the detail sends the report.
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key});

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportType? _type;
  bool _sending = false;

  Future<void> _send(ReportType type, ReportSubtype sub) async {
    if (_sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final s = S.of(context);
    final res = await ref
        .read(reportsProvider.notifier)
        .add(type, subtype: sub.key);
    nav.pop();
    switch (res) {
      case AddResult.ok:
        messenger.showSnackBar(
          SnackBar(
            content: Text(s.reported(type.localLabel(s), sub.localLabel(s))),
          ),
        );
      case AddResult.unauthorized:
        await ref.read(authProvider.notifier).logout();
        messenger.showSnackBar(SnackBar(content: Text(s.sessionExpiredReport)));
        nav.push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      case AddResult.failed:
        messenger.showSnackBar(SnackBar(content: Text(s.reportFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = _type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: type == null
            ? _pickType(S.of(context))
            : _pickDetail(type, S.of(context)),
      ),
    );
  }

  Widget _pickType(S s) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          s.reportWhat,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.98,
        children: [
          for (final t in ReportType.values)
            _TypeTile(
              type: t,
              onTap: () => t.subtypes.length == 1
                  ? _send(t, t.subtypes.first)
                  : setState(() => _type = t),
            ),
        ],
      ),
    ],
  );

  Widget _pickDetail(ReportType type, S s) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          IconButton(
            tooltip: s.back,
            onPressed: () => setState(() => _type = null),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          CircleAvatar(
            backgroundColor: type.color,
            child: Icon(type.icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text(
            type.localLabel(s),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      const SizedBox(height: 10),
      for (final sub in type.subtypes)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: type.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _sending ? null : () => _send(type, sub),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sub.localLabel(s),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_sending)
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.send_rounded,
                        color: AppColors.muted,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.type, required this.onTap});
  final ReportType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: type.color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(type.icon, size: 42, color: type.color),
          const SizedBox(height: 8),
          Text(
            type.localLabel(S.of(context)),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}
