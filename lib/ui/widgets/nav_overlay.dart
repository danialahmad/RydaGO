import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../models/report.dart';
import '../../state/auth.dart';
import '../../state/demo.dart';
import '../../state/navigation.dart';
import '../../state/reports.dart';
import '../../state/settings.dart';
import '../../state/trip.dart';
import 'map_buttons.dart';

/// Icon for a Valhalla maneuver type (https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/).
IconData maneuverIcon(int type) {
  switch (type) {
    case 1:
    case 2:
    case 3:
      return Icons.navigation_rounded;
    case 4:
    case 5:
    case 6:
      return Icons.flag_rounded;
    case 9:
      return Icons.turn_slight_right;
    case 10:
      return Icons.turn_right;
    case 11:
      return Icons.turn_sharp_right;
    case 12:
      return Icons.u_turn_right;
    case 13:
      return Icons.u_turn_left;
    case 14:
      return Icons.turn_sharp_left;
    case 15:
      return Icons.turn_left;
    case 16:
      return Icons.turn_slight_left;
    case 18:
    case 20:
    case 23:
      return Icons.fork_right;
    case 19:
    case 21:
    case 24:
      return Icons.fork_left;
    case 25:
      return Icons.merge;
    case 26:
    case 27:
      return Icons.roundabout_right;
  }
  return Icons.straight;
}

/// Dark banner at the top while driving: the next turn, how far, and on which street.
class NavBanner extends ConsumerWidget {
  const NavBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final nav = ref.watch(navProvider);
    final m = nav?.upcoming;
    if (nav == null || m == null) return const SizedBox.shrink();

    final IconData icon;
    final String? big;
    final String line;
    if (nav.rerouting) {
      icon = Icons.sync_rounded;
      big = null;
      line = s.recalculating;
    } else if (nav.arrived) {
      icon = Icons.flag_rounded;
      big = null;
      line = s.arrived;
    } else {
      icon = maneuverIcon(m.type);
      big = formatDistance(nav.distToUpcomingM);
      line = m.street.isNotEmpty ? m.street : m.text;
    }
    final then = (nav.rerouting || nav.arrived) ? null : nav.then;

    return Material(
      color: AppColors.banner,
      elevation: 10,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          // Right padding leaves room for the map credit "i" button that floats top right.
          padding: const EdgeInsets.fromLTRB(18, 12, 46, 16),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 58),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (big != null)
                      Text(
                        big,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: nav.rerouting || nav.arrived
                            ? Colors.white
                            : const Color(0xFF7FD6FF),
                        fontSize: nav.rerouting || nav.arrived ? 22 : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (then != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.then,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Icon(
                        maneuverIcon(then.type),
                        color: Colors.white,
                        size: 26,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round speedometer in the corner while driving, with the posted speed limit
/// above it when OpenStreetMap knows it. Turns red when over the limit by more
/// than the tolerance chosen in settings.
class SpeedBubble extends ConsumerWidget {
  const SpeedBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final nav = ref.watch(navProvider);
    final tolerance = ref.watch(
      settingsProvider.select((s) => s.speedAlert.toleranceKmh),
    );
    final kmh = nav?.speedKmh;
    final limit = nav?.speedLimitKmh;
    final speeding =
        nav != null && tolerance != null && nav.isSpeeding(tolerance);
    final scheme = Theme.of(context).colorScheme;
    final fg = speeding ? Colors.white : scheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (limit != null) ...[
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.danger, width: 5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6),
              ],
            ),
            child: Text(
              '$limit',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Material(
          color: speeding ? AppColors.danger : scheme.surface,
          elevation: 6,
          shape: const CircleBorder(),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  kmh == null ? '--' : '${kmh.round()}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: fg,
                  ),
                ),
                Text(
                  s.kmh,
                  style: TextStyle(
                    fontSize: 11,
                    color: speeding ? Colors.white70 : AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mute / unmute the spoken instructions.
class VoiceButton extends ConsumerWidget {
  const VoiceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(settingsProvider.select((s) => s.voiceOn));
    final s = S.of(context);
    return RoundMapButton(
      icon: on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
      tooltip: on ? s.muteVoice : s.unmuteVoice,
      onPressed: () => ref.read(settingsProvider.notifier).setVoice(!on),
    );
  }
}

/// A heads-up for the nearest report on the road ahead, within 800 m. Reports on
/// other roads, or behind us, do not count (that is what the route is for).
class NearbyReportPill extends ConsumerWidget {
  const NearbyReportPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final nav = ref.watch(navProvider);
    if (nav == null || nav.arrived) return const SizedBox.shrink();
    final ahead = nav.reportsAhead(ref.watch(reportsProvider));
    if (ahead.isEmpty) return const SizedBox.shrink();
    final r = ahead.first.report;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: r.type.color,
              child: Icon(r.type.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${r.title(s)} · ${formatDistance(ahead.first.aheadM)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Masih ada?": when passing a report made by someone else, asks whether it is
/// still there. One tap confirms (keeps the report alive) or dismisses it (three
/// net "gone" votes remove it for everyone).
class ReportPrompt extends ConsumerWidget {
  const ReportPrompt({super.key});

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    Report r,
    bool stillThere,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final res = await ref
        .read(reportsProvider.notifier)
        .vote(r, stillThere: stillThere);
    final msg = switch (res) {
      VoteResult.ok => s.voteOk,
      VoteResult.ownReport => s.voteOwn,
      VoteResult.unauthorized => s.voteSession,
      VoteResult.failed => s.voteFailed,
    };
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final nav = ref.watch(navProvider);
    final signedIn = ref.watch(authProvider) != null;
    final voted = ref.watch(votedReportsProvider);
    if (nav == null || nav.arrived || !signedIn) return const SizedBox.shrink();

    // Asked while approaching (within 250 m) and for a short while after passing.
    final candidates = nav
        .reportsAhead(ref.watch(reportsProvider), withinM: 250, passedM: 120)
        .where(
          (a) =>
              !a.report.mine &&
              a.report.id != 0 &&
              !voted.contains(a.report.id),
        )
        .toList();
    if (candidates.isEmpty) return const SizedBox.shrink();
    final r = candidates.first.report;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.stillThere(r.spokenName(s)),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.go.withValues(alpha: 0.18),
                      foregroundColor: AppColors.go,
                    ),
                    onPressed: () => _answer(context, ref, r, true),
                    icon: const Icon(Icons.thumb_up_alt_rounded, size: 20),
                    label: Text(s.yes, style: const TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.danger.withValues(alpha: 0.14),
                      foregroundColor: AppColors.danger,
                    ),
                    onPressed: () => _answer(context, ref, r, false),
                    icon: const Icon(Icons.thumb_down_alt_rounded, size: 20),
                    label: Text(s.no, style: const TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar while driving: arrival time, time and distance left. Tap it for
/// the street you are on, progress, and actions (share ETA, mute, stop).
class NavBottomBar extends ConsumerStatefulWidget {
  const NavBottomBar({super.key});

  @override
  ConsumerState<NavBottomBar> createState() => _NavBottomBarState();
}

class _NavBottomBarState extends ConsumerState<NavBottomBar> {
  bool _expanded = false;

  void _finish() {
    stopNavigation(ref);
    ref.read(destinationProvider.notifier).set(null);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final nav = ref.watch(navProvider);
    if (nav == null) return const SizedBox.shrink();
    final dest = ref.watch(destinationProvider);
    final voiceOn = ref.watch(settingsProvider.select((s) => s.voiceOn));
    final arrival = formatClock(
      DateTime.now().add(Duration(minutes: nav.remainingMin)),
      s,
    );

    if (nav.arrived) {
      return BottomPanel(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.arrived,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.go,
                    ),
                  ),
                  Text(
                    dest?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.go),
                onPressed: _finish,
                child: Text(s.done),
              ),
            ),
          ],
        ),
      );
    }

    return BottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          arrival,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          '${formatDuration(nav.remainingMin, s)} · ${formatDistance(nav.remainingM)}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 32,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            if (nav.route.via.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  s.via(nav.route.via),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            if (nav.route.toll != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  s.tollDetail(
                    nav.route.toll!.km.toString(),
                    formatRm(nav.route.toll!.rm),
                  ),
                  style: const TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: nav.progress,
                minHeight: 8,
                backgroundColor: Theme.of(context).dividerTheme.color,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 14),
            if (ref.watch(demoProvider)) ...[
              // Demo only: jump off the route to show re-routing.
              _Action(
                icon: Icons.alt_route_rounded,
                label: s.detourDemo,
                onTap: ref.read(demoDriverProvider.notifier).detour,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: _Action(
                    icon: Icons.ios_share_rounded,
                    label: s.shareEta,
                    onTap: () async {
                      final text = s.etaText(
                        dest?.name ?? s.destination,
                        arrival,
                      );
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(s.etaCopied)));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Action(
                    icon: voiceOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: voiceOn ? s.mute : s.voice,
                    onTap: () =>
                        ref.read(settingsProvider.notifier).setVoice(!voiceOn),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Action(
                    icon: Icons.close_rounded,
                    label: s.end,
                    color: AppColors.danger,
                    onTap: _finish,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Material(
      color: c.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
