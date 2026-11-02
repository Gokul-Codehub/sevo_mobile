import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../data/marketplace_catalog_repository.dart';

/// Tells the customer when the selected delivery point is outside every warehouse's service area. Nothing is
/// shown while the check is running, when it could not be made, or when delivery is available.
class DeliveryZoneBanner extends ConsumerWidget {
  const DeliveryZoneBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(deliveryZoneProvider).valueOrNull;
    if (zone == null || zone.status != DeliveryZoneStatus.unserviceable) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined, color: Color(0xFFB45309), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${zone.message ?? 'We do not deliver to this location yet.'} Pick another address to shop here.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.3),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/addresses'),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }
}
