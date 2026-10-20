import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../domain/logistics_models.dart';
import '../../domain/logistics_providers.dart';
import 'capacity_waitlist_banner.dart';

/// Screen 12: Date & Time Slot Picker
///
/// Restyled 2026-10-14 per the booking-summary UI requirement: a horizontal
/// day strip (selected day filled navy) and the time slots grouped into
/// Morning / Afternoon / Evening two-column grids (selected slot solid green).
class SlotPickerWidget extends ConsumerWidget {
  const SlotPickerWidget({super.key});

  static const Color _okGreen = AppColors.navy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedBookingDateProvider);
    final selectedSlot = ref.watch(selectedTimeSlotProvider);
    final slotsAsync = ref.watch(currentSelectedDateSlotsProvider);
    final day = ref.watch(currentSelectedDayProvider).valueOrNull;
    final claim = ref.watch(activeCapacityClaimProvider);
    final window = ref.watch(slotWindowProvider);

    // Same rule as the web checkout: slots the server flags as passed /
    // needing notice, and (for today, in India time) slots starting less than
    // 60 minutes from now, are hidden rather than shown greyed-out.
    final rawSlots = slotsAsync.valueOrNull ?? const <TimeSlot>[];
    final shown = rawSlots.where((s) => _isBookableWindow(s, selectedDate)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Month calendar ──
        _MonthCalendar(
          selected: selectedDate,
          window: window,
          onSelect: (date) {
            ref.read(selectedBookingDateProvider.notifier).state = date;
            ref.read(selectedTimeSlotProvider.notifier).state = null;
          },
        ),

        const SizedBox(height: 18),

        // A held "a slot opened up" claim: tell the customer the space is theirs.
        if (claim != null && !(day?.isFutureFull ?? false)) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EDF7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD5DCE8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: AppColors.navy, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    claim.expiresAt == null
                        ? 'A place is being held for you. Pick a time and book now.'
                        : 'A place is being held for you until ${DateFormat('h:mm a').format(claim.expiresAt!)}. Pick a time and book now.',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ── 2. Time Slots (grouped) ──
        Row(
          children: [
            const Text(
              'Select Time Slot',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        slotsAsync.when(
          loading: () => const ShimmerCard(height: 100),
          error: (err, stackTrace) => ErrorStateWidget(
            message: 'Unable to load slots. Tap to retry.',
            onRetry: () => ref.refresh(currentSelectedDateSlotsProvider),
          ),
          data: (allSlots) {
            final slots = allSlots.where((s) => _isBookableWindow(s, selectedDate)).toList();
            // A future date at its daily limit: offer an availability alert.
            if (day != null && day.isFutureFull && slots.every((s) => !s.isAvailable)) {
              return const CapacityWaitlistBanner();
            }
            final serverReason = (day?.reason ?? '').trim();
            final nothingBookable = slots.isEmpty || slots.every((s) => !s.isAvailable);
            if (nothingBookable) {
              final next = _nextBookableDate(selectedDate, window);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EmptyStateWidget(
                    title: 'No Available Slots',
                    subtitle: serverReason.isNotEmpty
                        ? serverReason
                        : 'All slots for this date are booked. Please select another date.',
                    emoji: '📅',
                  ),
                  if (next != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          ref.read(selectedBookingDateProvider.notifier).state = next;
                          ref.read(selectedTimeSlotProvider.notifier).state = null;
                        },
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: Text('Show next available date (${DateFormat('EEE, d MMM').format(next)})'),
                      ),
                    ),
                  if (slots.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _slotGroups(ref, slots, selectedDate, selectedSlot),
                  ],
                ],
              );
            }
            return _slotGroups(ref, slots, selectedDate, selectedSlot);
          },
        ),
      ],
    );
  }

  /// Next day after [from] that the server window allows (skips closed
  /// weekdays, stays inside advance_booking_days). Null when none.
  DateTime? _nextBookableDate(DateTime from, TimeSlotDay? window) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final adv = window?.advanceBookingDays ?? 30;
    final last = today.add(Duration(days: adv > 0 ? adv : 30));
    var d = DateTime(from.year, from.month, from.day).add(const Duration(days: 1));
    final closed = window?.closedWeekdays ?? const <int>[];
    while (!d.isAfter(last)) {
      if (!closed.contains(d.weekday - 1)) return d;
      d = d.add(const Duration(days: 1));
    }
    return null;
  }

  Widget _slotGroups(WidgetRef ref, List<TimeSlot> slots, DateTime selectedDate,
      TimeSlot? selectedSlot) {
    {
      {
        {

            final morning = <TimeSlot>[];
            final afternoon = <TimeSlot>[];
            final evening = <TimeSlot>[];
            for (final s in slots) {
              final h = _slotHour(s);
              if (h < 12) {
                morning.add(s);
              } else if (h < 17) {
                afternoon.add(s);
              } else {
                evening.add(s);
              }
            }

            Widget group(String title, IconData icon, Color color, List<TimeSlot> list) {
              if (list.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(width: 6),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, c) {
                        final w = (c.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            for (final slot in list)
                              _slotTile(ref, slot, selectedDate, selectedSlot, w),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                group('Morning', Icons.wb_sunny_outlined, const Color(0xFFF59E0B), morning),
                group('Afternoon', Icons.wb_sunny_rounded, const Color(0xFFF97316), afternoon),
                group('Evening', Icons.nights_stay_outlined, const Color(0xFF6366F1), evening),
              ],
            );
        }
      }
    }
  }

  Widget _slotTile(WidgetRef ref, TimeSlot slot, DateTime selectedDate,
      TimeSlot? selectedSlot, double width) {
    final isPast = _isSlotPast(slot, selectedDate);
    final isAvailable = slot.isAvailable && !isPast;
    final why = (slot.reason ?? '').trim();
    final isSelected = isAvailable && selectedSlot?.id == slot.id;

    return GestureDetector(
      onTap: isAvailable
          ? () => ref.read(selectedTimeSlotProvider.notifier).state = slot
          : null,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? _okGreen
              : (isAvailable ? Colors.white : const Color(0xFFE8ECF1)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? _okGreen
                : (isAvailable ? const Color(0xFFE2E8F0) : const Color(0xFFE8ECF1)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _shortLabel(slot),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isAvailable ? AppColors.navy : AppColors.textHint),
                ),
              ),
            ),
            if (!isAvailable && why.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  why,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.textHint),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One-hour slots show just their start ("10:00 AM"), like the design;
  /// longer windows keep the full "09:00 AM - 11:00 AM" label so the end
  /// time is never hidden from the customer.
  String _shortLabel(TimeSlot slot) {
    final start = _hourOf(slot.startTime);
    final end = _hourOf(slot.endTime);
    final oneHour = start != null && end != null && end - start == 1;
    if (!oneHour) return slot.label;
    final m = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM))', caseSensitive: false)
        .firstMatch(slot.label);
    return m != null ? m.group(1)!.toUpperCase() : slot.label;
  }

  int? _hourOf(String raw) {
    final match =
        RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?').firstMatch(raw.toUpperCase());
    if (match == null) return null;
    var h = int.parse(match.group(1)!);
    final mer = match.group(3);
    if (mer == 'PM' && h < 12) h += 12;
    if (mer == 'AM' && h == 12) h = 0;
    return h;
  }

  /// Start hour (0-23) of a slot, used for the Morning/Afternoon/Evening groups.
  int _slotHour(TimeSlot slot) {
    final timeStr = slot.startTime.isNotEmpty ? slot.startTime : slot.label;
    final upper = timeStr.toUpperCase();
    final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?').firstMatch(upper);
    if (match == null) return 9;
    var h = int.parse(match.group(1)!);
    final mer = match.group(3);
    if (mer == 'PM' && h < 12) h += 12;
    if (mer == 'AM' && h == 12) h = 0;
    return h;
  }

  /// Only whole past days are blocked locally. Same-day cut-off, notice period
  /// and "time passed" are decided by the server and arrive via slot.isAvailable
  /// (+ slot.reason), exactly like the web.
  bool _isSlotPast(TimeSlot slot, DateTime selectedDate) {
    final now = _businessNow();
    final today = DateTime(now.year, now.month, now.day);
    final selDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    return selDay.isBefore(today);
  }

  /// Booking rules run on India time (Asia/Kolkata), never the phone's clock,
  /// like the web (`businessNowParts`).
  static DateTime _businessNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  /// Web minimum lead for a same-day slot (travel + dispatch buffer).
  static const int _sameDayLeadMinutes = 60;

  /// True when the slot should be offered at all (web `isPastSlot`): hidden if
  /// the server says it has passed / needs notice, if the date is past, or if
  /// it is today and starts less than [_sameDayLeadMinutes] from now.
  bool _isBookableWindow(TimeSlot slot, DateTime selectedDate) {
    final reason = (slot.reason ?? '').toLowerCase();
    if (reason.contains('passed') ||
        reason.contains('notice') ||
        reason.contains('requires')) {
      return false;
    }
    final now = _businessNow();
    final today = DateTime(now.year, now.month, now.day);
    final selDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    if (selDay.isBefore(today)) return false;
    if (selDay.isAfter(today)) return true;
    final startMin = _minutesOf(slot.startTime.isNotEmpty ? slot.startTime : slot.label);
    if (startMin == null) return true;
    final nowMin = now.hour * 60 + now.minute;
    return startMin >= nowMin + _sameDayLeadMinutes;
  }

  int? _minutesOf(String raw) {
    final match =
        RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?').firstMatch(raw.toUpperCase());
    if (match == null) return null;
    var h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final mer = match.group(3);
    if (mer == 'PM' && h < 12) h += 12;
    if (mer == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }
}


/// Month grid used to pick the booking date (design: "October 2024" header
/// with round prev/next buttons, selected day as a navy rounded square,
/// days outside the month / the bookable window faded and not tappable).
class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({required this.selected, required this.onSelect, this.window});

  final DateTime selected;
  final TimeSlotDay? window;
  final ValueChanged<DateTime> onSelect;

  /// How many days ahead (including today) a customer can pick.
  static const int bookableDays = 30;

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  late DateTime _month; // first day of the visible month

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.selected.year, widget.selected.month);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final adv = widget.window?.advanceBookingDays;
    final last = today.add(Duration(
        days: (adv != null && adv > 0) ? adv : _MonthCalendar.bookableDays - 1));

    final firstOfMonth = DateTime(_month.year, _month.month);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final offset = firstOfMonth.weekday % 7; // Sunday = 0
    final rows = ((offset + daysInMonth) / 7).ceil();
    final gridStart = firstOfMonth.subtract(Duration(days: offset));

    final canGoPrev = firstOfMonth.isAfter(DateTime(today.year, today.month));
    final canGoNext = DateTime(_month.year, _month.month + 1).isBefore(last) ||
        DateTime(_month.year, _month.month + 1).isAtSameMomentAs(last);

    Widget navButton(IconData icon, bool enabled, VoidCallback onTap) {
      return GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            color: Colors.white,
          ),
          child: Icon(icon,
              size: 20,
              color: enabled ? AppColors.navy : const Color(0xFFCBD5E1)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              navButton(Icons.chevron_left_rounded, canGoPrev, () {
                setState(() => _month = DateTime(_month.year, _month.month - 1));
              }),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
              navButton(Icons.chevron_right_rounded, canGoNext, () {
                setState(() => _month = DateTime(_month.year, _month.month + 1));
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final d in const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _dayCell(gridStart.add(Duration(days: r * 7 + c)), today, last)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day, DateTime today, DateTime last) {
    final inMonth = day.month == _month.month;
    final closedDays = widget.window?.closedWeekdays ?? const <int>[];
    final noSameDay = widget.window != null && widget.window!.sameDayBooking == false;
    final bookable = !day.isBefore(today) &&
        !day.isAfter(last) &&
        !closedDays.contains(day.weekday - 1) &&
        !(noSameDay && DateUtils.isSameDay(day, today));
    final isSelected = DateUtils.isSameDay(day, widget.selected);
    final enabled = inMonth && bookable;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => widget.onSelect(day) : null,
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected && inMonth ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected && inMonth ? FontWeight.w800 : FontWeight.w600,
            color: isSelected && inMonth
                ? Colors.white
                : (enabled
                    ? AppColors.navy
                    : (inMonth ? const Color(0xFFB6BFCC) : const Color(0xFFCBD5E1))),
          ),
        ),
      ),
    );
  }
}
