import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/demo.dart';
import '../../state/trip.dart';
import '../../state/user_loc.dart';
import '../../state/voice.dart';
import '../map/map_view.dart';
import '../widgets/home_panel.dart';
import '../widgets/map_buttons.dart';
import '../widgets/nav_overlay.dart';
import '../widgets/pin_panel.dart';
import '../widgets/report_sheet.dart';
import '../widgets/route_preview.dart';
import 'settings_screen.dart';

/// The one main screen. What floats over the map depends on the stage:
/// browsing (search bar + shortcuts), pin dropped, route preview, or driving.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(demoDriverProvider); // keeps the demo driver alive
    ref.watch(voiceGuideProvider); // keeps spoken instructions alive
    final navigating = ref.watch(navigatingProvider);
    final dest = ref.watch(destinationProvider);
    final pin = ref.watch(pinProvider);

    final Widget panel;
    if (navigating) {
      panel = const NavBottomBar(key: ValueKey('nav'));
    } else if (dest != null) {
      panel = const RoutePreviewPanel(key: ValueKey('preview'));
    } else if (pin != null) {
      panel = PinPanel(key: const ValueKey('pin'), pin: pin);
    } else {
      panel = const HomePanel(key: ValueKey('home'));
    }

    // The system back button steps back one stage instead of closing the app.
    return PopScope(
      canPop: !navigating && dest == null && pin == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || navigating) return;
        if (dest != null) {
          ref.read(destinationProvider.notifier).set(null);
        } else {
          ref.read(pinProvider.notifier).set(null);
        }
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: MapView()),
            if (navigating)
              Align(
                alignment: Alignment.topCenter,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const NavBanner(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          NearbyReportPill(),
                          SizedBox(height: 8),
                          ReportPrompt(),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      const VoiceButton(),
                    ]),
                  ),
                ]),
              )
            else
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RoundMapButton(
                          icon: Icons.menu_rounded,
                          tooltip: 'Menu dan tetapan',
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen())),
                        ),
                        const SizedBox(height: 10),
                        const LocStatusChip(),
                      ],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (navigating) const SpeedBubble(),
                    const Spacer(),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      if (!navigating) ...[
                        RoundMapButton(
                          icon: Icons.my_location_rounded,
                          tooltip: 'Lokasi saya',
                          onPressed: () {
                            final loc = ref.read(userLocProvider);
                            if (!loc.isReal && !ref.read(demoProvider)) {
                              // Ask again: the user may have allowed location since.
                              ref.read(userLocProvider.notifier).start();
                            }
                            ref.read(recenterProvider.notifier).bump();
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      ReportButton(onPressed: () => openReportFlow(context, ref)),
                    ]),
                  ]),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: panel,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
