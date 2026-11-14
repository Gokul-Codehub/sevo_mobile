import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';

/// The "Active Quote" card on a booking detail screen — shown when a
/// Painting / Masonry / AC-Inspection booking (an ESTIMATION/inspection
/// [Booking.requestKind]) has a live [Booking.quote] attached.
///
/// Added 2026-09-26 as the Flutter counterpart of the React web app's own
/// Active Quote Card (`frontend/src/ui/pages/BookingPage.jsx`) — same
/// backend, same decision endpoint
/// (`/api/workforce/quotes/decision/<token>/`), same rule: the amount shown
/// here always comes from the backend ([QuoteSummary]), never recomputed
/// client-side, and every decision re-fetches the booking afterwards rather
/// than assuming the outcome.
class ActiveQuoteCard extends ConsumerWidget {
  const ActiveQuoteCard({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = booking.quote;
    if (quote == null) return const SizedBox.shrink();

    final decisionState = ref.watch(quoteDecisionControllerProvider);
    final isDeciding = decisionState.isLoading;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    quote.quoteNumber != null
                        ? 'Quotation ${quote.quoteNumber}${quote.quoteVersion != null ? " (v${quote.quoteVersion})" : ""}'
                        : 'Your Quotation',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary),
                  ),
                ),
                _StatusPill(quote: quote),
              ],
            ),
            if (quote.validUntil != null) ...[
              const SizedBox(height: 6),
              Text(
                'Valid until ${DateFormat('dd-MM-yyyy').format(quote.validUntil!)}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            if (quote.items.isNotEmpty) ...[
              ...quote.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${item.description}${item.quantity != 1 ? " × ${item.quantity}" : ""}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                      Text(
                        item.amount != null ? '₹${item.amount}' : '—',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 20),
            ],
            if (quote.isWithoutPrice)
              const _InfoBanner(
                icon: Icons.fact_check_outlined,
                color: AppColors.navy,
                text: 'This is a scope approval. Approve the work and your technician will send the priced quotation next.',
              ),
            if (!quote.isWithoutPrice && quote.subtotal != null) _AmountRow(label: 'Subtotal', amount: quote.subtotal!),
            if (quote.discountAmount != null && quote.discountAmount! > Decimal.zero)
              _AmountRow(label: 'Discount', amount: quote.discountAmount!, isNegative: true),
            if (quote.taxAmount != null) _AmountRow(label: 'Tax', amount: quote.taxAmount!),
            if (quote.inspectionFee != null && quote.inspectionFee! > Decimal.zero)
              _AmountRow(label: 'Inspection fee adjustment', amount: quote.inspectionFee!, isNegative: true),
            if (!quote.isWithoutPrice) ...[
            const Divider(height: 20),
            _AmountRow(
              label: quote.netPayable != null ? 'Net Payable' : 'Total',
              amount: quote.displayTotal,
              emphasize: true,
            ),
            ],
            // Advance / balance exactly as the server quoted them (only shown
            // when the quote carries a real advance; never computed here).
            if (!quote.isWithoutPrice && quote.advanceAmount != null && quote.advanceAmount! > Decimal.zero) ...[
              const SizedBox(height: 4),
              _AmountRow(label: 'Advance to pay after accepting', amount: quote.advanceAmount!),
              if (quote.alreadyPaidAdvance != null && quote.alreadyPaidAdvance! > Decimal.zero)
                _AmountRow(label: 'Already paid', amount: quote.alreadyPaidAdvance!, isNegative: true),
              if (quote.advanceFullyCovered)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Your earlier payment already covers the advance.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                )
              else if (quote.additionalAdvanceDue != null && quote.additionalAdvanceDue! > Decimal.zero)
                _AmountRow(label: 'Advance due now', amount: quote.additionalAdvanceDue!, emphasize: true),
              if (quote.balanceAmount != null && quote.balanceAmount! > Decimal.zero)
                _AmountRow(label: 'Balance after the work', amount: quote.balanceAmount!),
            ],
            if (quote.pendingAdminApproval) ...[
              const SizedBox(height: 12),
              const _InfoBanner(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.warning,
                text: 'This quotation is being reviewed by our team. You can accept or decline it as soon as it is approved.',
              ),
            ],
            if (quote.hasWorkSchedule) _WorkSchedule(quote: quote),
            if (_previousVersion(quote, booking.quotationHistory) case final prev?) _QuoteChanges(current: quote, previous: prev),
            if (quote.isDeclined) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: Icons.cancel_outlined,
                color: AppColors.error,
                text: quote.declineReason != null && quote.declineReason!.isNotEmpty
                    ? 'You declined this quotation: ${quote.declineReason}'
                    : 'You declined this quotation.',
              ),
            ] else if (quote.isExpired) ...[
              const SizedBox(height: 12),
              const _InfoBanner(
                icon: Icons.timer_off_outlined,
                color: AppColors.textSecondary,
                text: 'This quotation has expired. Please contact support for a fresh quote.',
              ),
            ] else if (quote.isSuperseded) ...[
              const SizedBox(height: 12),
              const _InfoBanner(
                icon: Icons.history,
                color: AppColors.textSecondary,
                text: 'This version was replaced by a newer quotation.',
              ),
            ] else if (quote.isChangesRequested) ...[
              const SizedBox(height: 12),
              const _InfoBanner(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.warning,
                text: 'Your change request has been sent. We\'ll notify you when the revised quotation is ready.',
              ),
            ] else if (quote.isConversionPending) ...[
              const SizedBox(height: 12),
              const _InfoBanner(
                icon: Icons.autorenew_rounded,
                color: AppColors.primary,
                text: 'Quotation accepted. Creating your service booking...',
              ),
            ] else if (quote.isAccepted) ...[
              const SizedBox(height: 12),
              const _InfoBanner(
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.success,
                text: 'Quotation accepted. Your work booking has been created — see it in Booking Stages below.',
              ),
            ] else if (quote.isSentToCustomer && quote.decisionToken != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isDeciding ? null : () => _declineFlow(context, ref, quote),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isDeciding ? null : () => _requestChangesFlow(context, ref, quote),
                      child: const Text('Request Changes'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isDeciding ? null : () => _acceptFlow(context, ref, quote),
                      child: isDeciding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _acceptFlow(BuildContext context, WidgetRef ref, QuoteSummary quote) async {
    var agreed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: Text(quote.isWithoutPrice ? 'Approve the scope?' : 'Accept Quotation?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          quote.isWithoutPrice
              ? 'Your technician will prepare the priced quotation once you approve the scope of work.'
              : (quote.advanceAmount != null && quote.advanceAmount! > Decimal.zero)
              ? (quote.advanceFullyCovered
                  ? 'The quoted total is ₹${quote.displayTotal}. Your earlier payment already covers the advance.'
                  : 'The quoted total is ₹${quote.displayTotal}. After accepting, pay the '
                      '₹${quote.additionalAdvanceDue != null && quote.additionalAdvanceDue! > Decimal.zero ? quote.additionalAdvanceDue : quote.advanceAmount} advance so the technician can start; the rest is due after the work.')
              : 'You will be charged ₹${quote.displayTotal} for this work. '
                  'Once accepted, we\'ll create your service booking.',
        ),
        // Mandatory advisory + terms tick: the server rejects approval of a priced quotation without it.
        if (!quote.isWithoutPrice) ...[
          const SizedBox(height: 10),
          const Text(
            'Mandatory company advisory: customer authorization is required before the technician begins additional '
            'repair work or installs new spare parts.',
            style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF92400E)),
          ),
          CheckboxListTile(
            value: agreed,
            onChanged: (v) => setLocal(() => agreed = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              'I have reviewed and agree to the scope of work and quotation charges (₹${quote.displayTotal}).',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: (quote.isWithoutPrice || agreed) ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Accept'),
          ),
        ],
      )),
    );
    if (confirmed != true || !context.mounted) return;
    await _submitDecision(context, ref, quote, 'CUSTOMER_ACCEPTED', termsAcknowledged: true);
  }

  Future<void> _declineFlow(BuildContext context, WidgetRef ref, QuoteSummary quote) async {
    const reasons = <String>[
      'Price is too high',
      'Found another provider',
      'No longer need this service',
      'Taking too long',
    ];
    String? selectedReason;
    final otherController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final isOther = selectedReason == 'Other';
          final canSubmit = selectedReason != null && (!isOther || otherController.text.trim().isNotEmpty);
          return AlertDialog(
            title: const Text('Decline Quotation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...reasons.map(
                    (r) => RadioListTile<String>(
                      value: r,
                      groupValue: selectedReason,
                      title: Text(r, style: const TextStyle(fontSize: 13)),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setState(() => selectedReason = v),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'Other',
                    groupValue: selectedReason,
                    title: const Text('Other', style: TextStyle(fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => selectedReason = v),
                  ),
                  if (isOther)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextField(
                        controller: otherController,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Tell us more...'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(ctx, isOther ? otherController.text.trim() : selectedReason)
                    : null,
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Decline'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    const codes = <String, String>{
      'Price is too high': 'TOO_EXPENSIVE',
      'Found another provider': 'COMPETITOR_CHOSEN',
      'No longer need this service': 'CHANGE_OF_PLANS',
      'Taking too long': 'DELAYED_TIMELINE',
    };
    final code = codes[result];
    await _submitDecision(context, ref, quote, 'DECLINED', reasonCode: code ?? 'OTHER', reasonNotes: code == null ? result : null);
  }

  Future<void> _requestChangesFlow(BuildContext context, WidgetRef ref, QuoteSummary quote) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Request Changes'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. Please include balcony painting.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: controller.text.trim().isNotEmpty ? () => Navigator.pop(ctx, controller.text.trim()) : null,
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (note == null || note.isEmpty || !context.mounted) return;
    await _submitDecision(context, ref, quote, 'CHANGE_REQUESTED', reasonNotes: note);
  }

  Future<void> _submitDecision(
    BuildContext context,
    WidgetRef ref,
    QuoteSummary quote,
    String decision, {
    String? reasonNotes,
    bool termsAcknowledged = false,
    String? reasonCode,
  }) async {
    final token = quote.decisionToken;
    if (token == null) return;
    final error = await ref.read(quoteDecisionControllerProvider.notifier).decide(
          decisionToken: token,
          decision: decision,
          parentBookingId: booking.id,
          reasonNotes: reasonNotes,
          termsAcknowledged: termsAcknowledged,
          reasonCode: reasonCode,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Done.'),
        backgroundColor: error != null ? AppColors.error : AppColors.success,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.quote});

  final QuoteSummary quote;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label = quote.statusDisplay ?? quote.status.replaceAll('_', ' ');
    if (quote.isAccepted || quote.isConversionPending) {
      color = AppColors.success;
    } else if (quote.isDeclined || quote.isExpired) {
      color = AppColors.error;
    } else if (quote.isChangesRequested) {
      color = AppColors.warning;
    } else {
      color = AppColors.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount, this.emphasize = false, this.isNegative = false});

  final String label;
  final Decimal amount;
  final bool emphasize;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 14 : 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              color: emphasize ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          Text(
            '${isNegative ? "-" : ""}₹${amount.abs()}',
            style: TextStyle(
              fontSize: emphasize ? 15 : 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ───────────── Work schedule + "what changed" (parity with the website's quotation card) ─────────────

DateTime? _parseDay(String? s) => DateTime.tryParse((s ?? '').trim().split(' ').first.split('T').first);

/// "09:30", "09:30:00" or "9:30 AM" -> (hour24, minute); null when it cannot be read.
({int h, int m})? _parseClock(String? raw) {
  final s = (raw ?? '').trim().toUpperCase();
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$').firstMatch(s);
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final ap = m.group(3);
  if (ap == 'PM' && h < 12) h += 12;
  if (ap == 'AM' && h == 12) h = 0;
  if (h > 23 || min > 59) return null;
  return (h: h, m: min);
}

String _clockLabel(String? raw) {
  final c = _parseClock(raw);
  if (c == null) return (raw ?? '').trim();
  final h12 = c.h % 12 == 0 ? 12 : c.h % 12;
  return '$h12:${c.m.toString().padLeft(2, '0')} ${c.h >= 12 ? 'PM' : 'AM'}';
}

String _dayLabel(String? raw) {
  final d = _parseDay(raw);
  if (d == null) return (raw ?? '').trim();
  final today = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return DateFormat('EEE, dd MMM yyyy').format(d);
}

String? _durationLabel(QuoteSummary q) {
  final sd = _parseDay(q.workStartDate);
  final sc = _parseClock(q.workStartTime);
  final ed = _parseDay(q.workEndDate) ?? sd;
  final ec = _parseClock(q.workEndTime);
  if (sd == null || sc == null || ed == null || ec == null) return null;
  final start = DateTime(sd.year, sd.month, sd.day, sc.h, sc.m);
  final end = DateTime(ed.year, ed.month, ed.day, ec.h, ec.m);
  final mins = end.difference(start).inMinutes;
  if (mins <= 0) return null;
  final days = mins ~/ (24 * 60);
  final hours = (mins % (24 * 60)) ~/ 60;
  final rem = mins % 60;
  return [
    if (days > 0) '$days day${days > 1 ? 's' : ''}',
    if (hours > 0) '$hours hr',
    if (rem > 0 && days == 0) '$rem min',
  ].join(' ');
}

/// Technician's estimated work start / completion, as on the website's quotation card.
class _WorkSchedule extends StatelessWidget {
  const _WorkSchedule({required this.quote});
  final QuoteSummary quote;

  Widget _cell(IconData icon, String title, String? date, String? time) {
    final hasAny = (date ?? '').trim().isNotEmpty || (time ?? '').trim().isNotEmpty;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border, width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 5),
            Flexible(child: Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
          ]),
          const SizedBox(height: 4),
          Text(hasAny ? _dayLabel(date) : 'To be confirmed', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if ((time ?? '').trim().isNotEmpty)
            Text(_clockLabel(time), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dur = _durationLabel(quote);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Estimated work schedule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navy)),
        const Text('Confirmed by your assigned technician', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          _cell(Icons.play_circle_outline_rounded, 'WORK START', quote.workStartDate, quote.workStartTime),
          const SizedBox(width: 8),
          _cell(Icons.flag_outlined, 'COMPLETION', quote.workEndDate ?? quote.workStartDate, quote.workEndTime),
        ]),
        if (dur != null) ...[
          const SizedBox(height: 6),
          Text('Estimated duration: $dur', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }
}

/// What this version added / changed / removed compared with the previous one.
class _QuoteChanges extends StatelessWidget {
  const _QuoteChanges({required this.current, required this.previous});
  final QuoteSummary current;
  final QuoteSummary previous;

  static String _k(QuoteLineItem i) => i.description.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final prev = {for (final i in previous.items) _k(i): i};
    final cur = {for (final i in current.items) _k(i): i};
    final lines = <({String sign, Color color, String text})>[];
    for (final i in current.items) {
      final p = prev[_k(i)];
      if (p == null) {
        lines.add((sign: '+', color: AppColors.success, text: '${i.description}${i.amount != null ? '  ₹${i.amount}' : ''}'));
      } else if (p.amount != i.amount || p.quantity != i.quantity) {
        lines.add((sign: '~', color: AppColors.warning, text: '${i.description}: ${p.amount != null ? '₹${p.amount}' : '-'} → ${i.amount != null ? '₹${i.amount}' : '-'}'));
      }
    }
    for (final p in previous.items) {
      if (!cur.containsKey(_k(p))) lines.add((sign: '−', color: AppColors.error, text: '${p.description} removed'));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    final pv = previous.quoteVersion;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDE68A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(pv != null ? 'Changes since v$pv' : 'Changes since the previous quotation',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF78350F))),
        const SizedBox(height: 4),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 16, child: Text(l.sign, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: l.color))),
              Expanded(child: Text(l.text, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
            ]),
          ),
      ]),
    );
  }
}

/// The newest earlier version of [q] in [history] (history is newest first), or null.
QuoteSummary? _previousVersion(QuoteSummary q, List<QuoteSummary> history) {
  final v = q.quoteVersion;
  for (final h in history) {
    if (h.id != null && h.id == q.id) continue;
    if (v == null || (h.quoteVersion != null && h.quoteVersion! < v)) return h;
  }
  return null;
}
