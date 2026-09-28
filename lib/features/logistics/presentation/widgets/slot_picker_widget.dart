import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../domain/logistics_models.dart';
import '../../domain/logistics_providers.dart';

/// Screen 12: Date & Time Slot Picker
/// Matches reference screen 12 with horizontal day cards and clean time slot selector pills.
class SlotPickerWidget extends ConsumerWidget {
  const SlotPickerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedBookingDateProvider);
    final selectedSlot = ref.watch(selectedTimeSlotProvider);
    final slotsAsync = ref.watch(currentSelectedDateSlotsProvider);

    final next7Days =
        List.generate(7, (i) => DateTime.now().add(Duration(days: i)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Date Selector Strip ──
        const Text(
          'Select Date',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: next7Days.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final date = next7Days[index];
              final isSelected = DateUtils.isSameDay(date, selectedDate);
              final isToday = DateUtils.isSameDay(date, DateTime.now());

              return GestureDetector(
                onTap: () {
                  ref.read(selectedBookingDateProvider.notifier).state = date;
                  ref.read(selectedTimeSlotProvider.notifier).state = null;
                },
                child: Container(
                  width: 64,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.navy : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.navy : AppColors.border,
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.navy.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isToday
                            ? 'Today'
                            : DateFormat('EEE').format(date),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFF86EFAC)
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('d').format(date),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          color: isSelected
                              ? Colors.white
                              : AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        DateFormat('MMM').format(date),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? Colors.white70
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 22),

        // ── 2. Time Slot Grid ──
        const Text(
          'Select Time Slot',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),

        slotsAsync.when(
          loading: () => const ShimmerCard(height: 100),
          error: (err, stackTrace) => ErrorStateWidget(
            message: 'Unable to load slots. Tap to retry.',
            onRetry: () => ref.refresh(currentSelectedDateSlotsProvider),
          ),
          data: (slots) {
            if (slots.isEmpty) {
              return const EmptyStateWidget(
                title: 'No Available Slots',
                subtitle:
                    'All slots for this date are booked. Please select another date.',
                emoji: '📅',
              );
            }

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: slots.map((slot) {
                final isPast = _isSlotPast(slot, selectedDate);
                final isAvailable = slot.isAvailable && !isPast;
                final isSelected = isAvailable && selectedSlot?.id == slot.id;

                return GestureDetector(
                  onTap: isAvailable
                      ? () {
                          ref.read(selectedTimeSlotProvider.notifier).state =
                              slot;
                        }
                      : null,
                  child: Opacity(
                    opacity: isAvailable ? 1.0 : 0.38,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF0FDF4)
                            : (isAvailable
                                ? Colors.white
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isAvailable
                                  ? AppColors.border
                                  : AppColors.divider),
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
                                : (isAvailable
                                    ? AppColors.navy
                                    : AppColors.textHint),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            slot.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? AppColors.navy
                                  : (isAvailable
                                      ? AppColors.navy
                                      : AppColors.textHint),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  /// Determines whether a time slot has already passed for the selected date.
  /// Same-day services booking operates from 9:00 AM to 6:00 PM (18:00).
  bool _isSlotPast(TimeSlot slot, DateTime selectedDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selDay =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    if (selDay.isBefore(today)) return true;
    if (selDay.isAfter(today)) return false;

    // Selected date is today. If current time is past 6 PM, all slots are closed.
    if (now.hour >= 18) return true;

    final timeStr = slot.startTime.isNotEmpty ? slot.startTime : slot.label;
    final upper = timeStr.toUpperCase();
    int slotHour = 0;
    int slotMinute = 0;
    if (upper.contains('AM') || upper.contains('PM')) {
      final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(upper);
      if (match != null) {
        slotHour = int.parse(match.group(1)!);
        slotMinute = int.parse(match.group(2)!);
        final meridiem = match.group(3)!;
        if (meridiem == 'PM' && slotHour < 12) slotHour += 12;
        if (meridiem == 'AM' && slotHour == 12) slotHour = 0;
      }
    } else {
      final parts = slot.startTime.split(':');
      if (parts.isNotEmpty) {
        slotHour = int.tryParse(parts[0]) ?? 0;
        slotMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      }
    }

    final slotTime =
        DateTime(now.year, now.month, now.day, slotHour, slotMinute);
    return now.isAfter(slotTime);
  }
}

