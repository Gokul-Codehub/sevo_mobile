import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../domain/gt_models.dart';
import '../../domain/gt_providers.dart';
import '../../domain/logistics_models.dart';
import '../../domain/logistics_providers.dart';

/// Goods & Transport date + slot picker driven entirely by
/// `GET /api/logistics/slots/`. The server owns the cut-off, lead time,
/// capacity and bookable dates, so nothing is hard-coded here (the generic
/// [SlotPickerWidget] assumes a fixed 6 PM close, which does not apply to
/// Goods & Transport).
///
/// Writes the same providers the booking screen already submits from:
/// [selectedBookingDateProvider] and [selectedTimeSlotProvider]. The slot
/// `label` is sent verbatim as `preferred_time` — the backend matches slot
/// labels exactly.
///
/// [category]: "goods_transport_truck" | "goods_transport_two_wheeler" |
/// "packers_movers" | "ptl".
class GtSlotPicker extends ConsumerWidget {
  const GtSlotPicker({super.key, required this.category, this.city});

  final String category;
  final String? city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedBookingDateProvider);
    final selectedSlot = ref.watch(selectedTimeSlotProvider);
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final slotsAsync = ref.watch(
      gtSlotsProvider((date: dateStr, category: category, city: city)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        slotsAsync.when(
          loading: () => const ShimmerCard(height: 120),
          error: (err, _) => ErrorStateWidget(
            message: err is Exception
                ? 'Unable to load slots. Tap to retry.'
                : 'Unable to load slots.',
            onRetry: () => ref.invalidate(gtSlotsProvider),
          ),
          data: (res) => _buildBody(context, ref, res, selectedDate, selectedSlot, dateStr),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    GtSlotsResult res,
    DateTime selectedDate,
    TimeSlot? selectedSlot,
    String dateStr,
  ) {
    final dates = res.upcomingDates;

    // The server's first bookable date can be later than the provider's
    // default (e.g. same-day closed, or PTL advance-only). Snap to it once.
    if (dates.isNotEmpty && !dates.any((d) => d.date == dateStr)) {
      final first = DateTime.tryParse(dates.first.date);
      if (first != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(selectedBookingDateProvider.notifier).state = first;
          ref.read(selectedTimeSlotProvider.notifier).state = null;
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dates.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final d = dates[i];
                final isSelected = d.date == dateStr;
                return GestureDetector(
                  onTap: () {
                    final parsed = DateTime.tryParse(d.date);
                    if (parsed == null) return;
                    ref.read(selectedBookingDateProvider.notifier).state = parsed;
                    ref.read(selectedTimeSlotProvider.notifier).state = null;
                  },
                  child: Container(
                    width: 64,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.navy : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppColors.navy : AppColors.border,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          d.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? const Color(0xFF86EFAC) : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.value,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? Colors.white : AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (res.isSameDayClosed &&
            (res.cutoffLabel ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Same-day booking is closed (${res.cutoffLabel}). Pick a later date.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Select Time Slot',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        if (res.allSlots.isEmpty)
          const EmptyStateWidget(
            title: 'No Available Slots',
            subtitle: 'No slots are open for this date. Please select another date.',
            emoji: '📅',
          )
        else
          for (final group in res.groups)
            if (group.slots.isNotEmpty) ...[
              if (group.name.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 2),
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final slot in group.slots)
                    _SlotChip(
                      slot: slot,
                      isSelected: slot.isAvailable &&
                          selectedSlot != null &&
                          selectedSlot.label == slot.label &&
                          selectedSlot.date == dateStr,
                      onTap: () {
                        if (!slot.isAvailable) {
                          final reason = slot.reason;
                          if (reason != null && reason.isNotEmpty) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(content: Text(reason)));
                          }
                          return;
                        }
                        ref.read(selectedTimeSlotProvider.notifier).state =
                            slot.toTimeSlot(dateStr);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.slot,
    required this.isSelected,
    required this.onTap,
  });

  final GtSlot slot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = slot.isAvailable;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: available ? 1.0 : 0.38,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF0FDF4)
                : (available ? Colors.white : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (available ? AppColors.border : AppColors.divider),
              width: isSelected ? 1.8 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 15,
                color: isSelected
                    ? AppColors.primary
                    : (available ? AppColors.navy : AppColors.textHint),
              ),
              const SizedBox(width: 6),
              Text(
                slot.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: available ? AppColors.navy : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
