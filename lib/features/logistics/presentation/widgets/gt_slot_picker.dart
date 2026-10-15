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
/// Laid out like the other services' booking: a month calendar (only the
/// server's bookable dates are tappable) and the time slots split into
/// Morning / Afternoon / Evening.
///
/// Writes the same providers the booking screen already submits from:
/// [selectedBookingDateProvider] and [selectedTimeSlotProvider]. The slot
/// `label` is sent verbatim as `preferred_time` — the backend matches slot
/// labels exactly.
///
/// [category]: "goods_transport_truck" | "goods_transport_two_wheeler" |
/// "packers_movers" | "ptl".
class GtSlotPicker extends ConsumerStatefulWidget {
  const GtSlotPicker({super.key, required this.category, this.city});

  final String category;
  final String? city;

  @override
  ConsumerState<GtSlotPicker> createState() => _GtSlotPickerState();
}

class _GtSlotPickerState extends ConsumerState<GtSlotPicker> {
  /// Bookable dates from the last successful response, so the calendar stays
  /// on screen (and keeps its visible month) while a new date's slots load.
  List<GtBookableDate>? _dates;

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedBookingDateProvider);
    final selectedSlot = ref.watch(selectedTimeSlotProvider);
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final slotsAsync = ref.watch(
      gtSlotsProvider(
          (date: dateStr, category: widget.category, city: widget.city)),
    );

    final res = slotsAsync.valueOrNull;
    if (res != null) {
      _dates = res.upcomingDates;
      // The server's first bookable date can be later than the provider's
      // default (e.g. same-day closed, or PTL advance-only). Snap to it once.
      final dates = res.upcomingDates;
      if (dates.isNotEmpty && !dates.any((d) => d.date == dateStr)) {
        final first = DateTime.tryParse(dates.first.date);
        if (first != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedBookingDateProvider.notifier).state = first;
            ref.read(selectedTimeSlotProvider.notifier).state = null;
          });
        }
      }
    }

    if (_dates == null) {
      return slotsAsync.when(
        loading: () => const Column(
          children: [
            ShimmerCard(height: 300),
            SizedBox(height: 16),
            ShimmerCard(height: 120),
          ],
        ),
        error: (err, _) => ErrorStateWidget(
          message: err is Exception
              ? 'Unable to load slots. Tap to retry.'
              : 'Unable to load slots.',
          onRetry: () => ref.invalidate(gtSlotsProvider),
        ),
        data: (_) => const SizedBox.shrink(),
      );
    }

    final bookable = <DateTime>{
      for (final d in _dates!)
        if (DateTime.tryParse(d.date) != null)
          DateUtils.dateOnly(DateTime.parse(d.date)),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        _MonthCalendar(
          selected: selectedDate,
          bookable: bookable,
          onSelect: (date) {
            ref.read(selectedBookingDateProvider.notifier).state = date;
            ref.read(selectedTimeSlotProvider.notifier).state = null;
          },
        ),
        if (res != null &&
            res.isSameDayClosed &&
            (res.cutoffLabel ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Same-day booking is closed (${res.cutoffLabel}). Pick a later date.',
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Select Time Slot',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
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
          data: (r) => _buildSlots(r, selectedSlot, dateStr),
        ),
      ],
    );
  }

  Widget _buildSlots(GtSlotsResult res, TimeSlot? selectedSlot, String dateStr) {
    if (res.allSlots.isEmpty) {
      return const EmptyStateWidget(
        title: 'No Available Slots',
        subtitle: 'No slots are open for this date. Please select another date.',
        emoji: '📅',
      );
    }

    final morning = <GtSlot>[];
    final afternoon = <GtSlot>[];
    final evening = <GtSlot>[];
    for (final s in res.allSlots) {
      final h = _slotHour(s);
      if (h < 12) {
        morning.add(s);
      } else if (h < 17) {
        afternoon.add(s);
      } else {
        evening.add(s);
      }
    }

    Widget group(String title, IconData icon, List<GtSlot> list) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.navy),
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
                      _SlotTile(
                        width: w,
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
                                ..showSnackBar(
                                    SnackBar(content: Text(reason)));
                            }
                            return;
                          }
                          ref.read(selectedTimeSlotProvider.notifier).state =
                              slot.toTimeSlot(dateStr);
                        },
                      ),
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
        group('Morning', Icons.wb_sunny_outlined, morning),
        group('Afternoon', Icons.wb_sunny_rounded, afternoon),
        group('Evening', Icons.nights_stay_outlined, evening),
      ],
    );
  }

  /// Start hour (0-23) of a slot, used for the Morning/Afternoon/Evening split.
  static int _slotHour(GtSlot slot) {
    final raw = ((slot.startTime ?? '').isNotEmpty ? slot.startTime! : slot.label)
        .toUpperCase();
    final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?').firstMatch(raw);
    if (match == null) return 9;
    var h = int.parse(match.group(1)!);
    final mer = match.group(3);
    if (mer == 'PM' && h < 12) h += 12;
    if (mer == 'AM' && h == 12) h = 0;
    return h;
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.width,
    required this.slot,
    required this.isSelected,
    required this.onTap,
  });

  final double width;
  final GtSlot slot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = slot.isAvailable;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.navy
              : (available ? Colors.white : const Color(0xFFE8ECF1)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.navy
                : (available
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFE8ECF1)),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            slot.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : (available ? AppColors.navy : AppColors.textHint),
            ),
          ),
        ),
      ),
    );
  }
}

/// Month grid used to pick the booking date: round prev/next buttons, the
/// selected day as a navy rounded square, and only the server's bookable
/// dates tappable (everything else faded).
class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({
    required this.selected,
    required this.bookable,
    required this.onSelect,
  });

  final DateTime selected;
  final Set<DateTime> bookable;
  final ValueChanged<DateTime> onSelect;

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
    final firstBookable = widget.bookable.isEmpty
        ? today
        : (widget.bookable.toList()..sort()).first;
    final lastBookable = widget.bookable.isEmpty
        ? today
        : (widget.bookable.toList()..sort()).last;

    final firstOfMonth = DateTime(_month.year, _month.month);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final offset = firstOfMonth.weekday % 7; // Sunday = 0
    final rows = ((offset + daysInMonth) / 7).ceil();
    final gridStart = firstOfMonth.subtract(Duration(days: offset));

    final canGoPrev =
        firstOfMonth.isAfter(DateTime(firstBookable.year, firstBookable.month));
    final canGoNext =
        DateTime(_month.year, _month.month + 1).isBefore(lastBookable) ||
            DateTime(_month.year, _month.month + 1)
                .isAtSameMomentAs(lastBookable);

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
                setState(
                    () => _month = DateTime(_month.year, _month.month - 1));
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
                setState(
                    () => _month = DateTime(_month.year, _month.month + 1));
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final d in const [
                'Sun',
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat'
              ])
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
                  Expanded(
                      child: _dayCell(gridStart.add(Duration(days: r * 7 + c)))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final inMonth = day.month == _month.month;
    final isBookable = widget.bookable.contains(DateUtils.dateOnly(day));
    final isSelected = DateUtils.isSameDay(day, widget.selected);
    final enabled = inMonth && isBookable;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => widget.onSelect(DateUtils.dateOnly(day)) : null,
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
            fontWeight:
                isSelected && inMonth ? FontWeight.w800 : FontWeight.w600,
            color: isSelected && inMonth
                ? Colors.white
                : (enabled
                    ? AppColors.navy
                    : (inMonth
                        ? const Color(0xFFB6BFCC)
                        : const Color(0xFFCBD5E1))),
          ),
        ),
      ),
    );
  }
}
