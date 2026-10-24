import '../../app/strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/user_loc.dart';
import '../../state/demo.dart';
import '../../state/user_loc.dart';

/// The round, shadowed buttons that float over the map.
class RoundMapButton extends StatelessWidget {
  const RoundMapButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.background,
    this.foreground,
    this.size = 52,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Material(
      color: background ?? scheme.surface,
      elevation: 5,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: foreground ?? scheme.onSurface,
            size: size * 0.5,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The orange report button, the most prominent control on the map.
class ReportButton extends StatelessWidget {
  const ReportButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => RoundMapButton(
    icon: Icons.add_alert_rounded,
    tooltip: S.of(context).reportShort,
    size: 64,
    background: AppColors.report,
    foreground: Colors.white,
    onPressed: onPressed,
  );
}

/// Small pill that says why the blue dot is not on the user's real position
/// (searching, permission denied, GPS off) or that demo mode is on.
class LocStatusChip extends ConsumerWidget {
  const LocStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final loc = ref.watch(userLocProvider);
    if (ref.watch(demoProvider)) {
      return _Pill(
        icon: Icons.science_outlined,
        text: s.demoBanner,
        tint: Color(0xFFFFF1CC),
      );
    }
    if (loc.isReal) return const SizedBox.shrink();
    return switch (loc.status) {
      LocStatus.starting => _Pill(icon: Icons.gps_not_fixed, text: s.locating),
      LocStatus.denied => _Pill(icon: Icons.location_off, text: s.locDenied),
      LocStatus.unavailable => _Pill(
        icon: Icons.location_off,
        text: s.locUnavailable,
      ),
      LocStatus.active => _Pill(icon: Icons.gps_not_fixed, text: s.waitingGps),
    };
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.tint});
  final IconData icon;
  final String text;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final onTint = tint != null;
    return Material(
      elevation: 3,
      color: tint ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: onTint ? AppColors.ink : AppColors.muted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: onTint ? AppColors.ink : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded white sheet that sits at the bottom of the map screen.
class BottomPanel extends StatelessWidget {
  const BottomPanel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 16,
    shadowColor: Colors.black54,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerTheme.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            child,
          ],
        ),
      ),
    ),
  );
}
