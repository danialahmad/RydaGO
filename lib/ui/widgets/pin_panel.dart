import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../models/place.dart';
import '../../state/trip.dart';
import 'map_buttons.dart';
import 'report_sheet.dart';

/// Shown after a long press on the map: go to that spot, or report something there.
class PinPanel extends ConsumerWidget {
  const PinPanel({super.key, required this.pin});
  final LatLng pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final coords =
        '${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}';
    return BottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFF6C3FC5),
                child: Icon(Icons.place, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.pinTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      coords,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: s.close,
                onPressed: () => ref.read(pinProvider.notifier).set(null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.go),
                  onPressed: () => chooseDestination(
                    ref,
                    Place(s.pinTitle, coords, Icons.place, pin),
                  ),
                  icon: const Icon(Icons.navigation_rounded),
                  label: Text(s.go),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openReportFlow(context, ref),
                  icon: const Icon(Icons.add_alert_rounded),
                  label: Text(s.reportShort),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
