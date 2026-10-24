import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/report.dart';
import '../../state/auth.dart';
import '../../state/reports.dart';
import '../screens/login_screen.dart';

/// Opens the report sheet, or the login screen first if the user is signed out.
void openReportFlow(BuildContext context, WidgetRef ref) {
  if (ref.read(authProvider) == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log masuk dahulu untuk membuat laporan.')));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
    final res = await ref.read(reportsProvider.notifier).add(type, subtype: sub.key);
    nav.pop();
    switch (res) {
      case AddResult.ok:
        messenger.showSnackBar(SnackBar(
          content: Text('Terima kasih! ${type.label} (${sub.label}) dilaporkan.'),
        ));
      case AddResult.unauthorized:
        await ref.read(authProvider.notifier).logout();
        messenger.showSnackBar(
            const SnackBar(content: Text('Sesi tamat. Sila log masuk semula.')));
        nav.push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      case AddResult.failed:
        messenger.showSnackBar(const SnackBar(
            content: Text('Gagal hantar laporan. Server tak dapat dihubungi.')));
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
        child: type == null ? _pickType() : _pickDetail(type),
      ),
    );
  }

  Widget _pickType() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Apa yang anda nampak?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
      ]);

  Widget _pickDetail(ReportType type) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(
            tooltip: 'Kembali',
            onPressed: () => setState(() => _type = null),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          CircleAvatar(
            backgroundColor: type.color,
            child: Icon(type.icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text(type.label,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
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
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(children: [
                    Expanded(
                      child: Text(sub.label,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    if (_sending)
                      const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.send_rounded, color: AppColors.muted, size: 20),
                  ]),
                ),
              ),
            ),
          ),
      ]);
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
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(type.icon, size: 42, color: type.color),
            const SizedBox(height: 8),
            Text(type.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}
