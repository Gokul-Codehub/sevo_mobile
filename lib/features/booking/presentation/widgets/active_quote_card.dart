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
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                  ),
                ),
                _StatusPill(quote: quote),
              ],
            ),
            if (quote.validUntil != null) ...[
              const SizedBox(height: 6),
              Text(
                'Valid until ${DateFormat('d MMM, y').format(quote.validUntil!)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ),
                      Text(
                        item.amount != null ? '₹${item.amount}' : '—',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 20),
            ],
            if (quote.subtotal != null) _AmountRow(label: 'Subtotal', amount: quote.subtotal!),
            if (quote.discountAmount != null && quote.discountAmount! > Decimal.zero)
              _AmountRow(label: 'Discount', amount: quote.discountAmount!, isNegative: true),
            if (quote.taxAmount != null) _AmountRow(label: 'Tax', amount: quote.taxAmount!),
            if (quote.inspectionFee != null && quote.inspectionFee! > Decimal.zero)
              _AmountRow(label: 'Inspection fee adjustment', amount: quote.inspectionFee!, isNegative: true),
            const Divider(height: 20),
            _AmountRow(
              label: quote.netPayable != null ? 'Net Payable' : 'Total',
              amount: quote.displayTotal,
              emphasize: true,
            ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Quotation?'),
        content: Text(
          'You will be charged ₹${quote.displayTotal} for this work. '
          'Once accepted, we\'ll create your service booking.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _submitDecision(context, ref, quote, 'CUSTOMER_ACCEPTED');
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
                      title: Text(r, style: const TextStyle(fontSize: 14)),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setState(() => selectedReason = v),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'Other',
                    groupValue: selectedReason,
                    title: const Text('Other', style: TextStyle(fontSize: 14)),
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
    await _submitDecision(context, ref, quote, 'DECLINED', reasonNotes: result);
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
  }) async {
    final token = quote.decisionToken;
    if (token == null) return;
    final error = await ref.read(quoteDecisionControllerProvider.notifier).decide(
          decisionToken: token,
          decision: decision,
          parentBookingId: booking.id,
          reasonNotes: reasonNotes,
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
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
