import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/booking_models.dart';
import '../../domain/mason_rules.dart';

/// True for a Mason (or waterproofing) booking: the ones whose accepted quotation is paid as advance + balance,
/// collected by the technician. Mirrors the web app's "Masonry split payment card".
bool isMasonQuoteBooking(Booking b) {
  if (b.items.any((i) => isMasonOnlyService(i.service))) return true;
  return b.items.any((i) {
    final c = '${i.service.categorySlug ?? ''} ${i.service.categoryName ?? ''}'.toLowerCase();
    return c.contains('waterproof');
  });
}

/// "Quote Accepted" summary: Quote Total / Advance / Remaining and what happens next (advance collected by the
/// technician, zero-advance, balance on completion, fully paid). Every amount comes from the server's quotation -
/// nothing is computed here except the remaining-balance fallback the web card also uses.
class MasonQuotePaymentCard extends StatelessWidget {
  const MasonQuotePaymentCard({super.key, required this.booking});

  final Booking booking;

  static const _completionStates = {
    'completed', 'closed', 'feedback_pending', 'feedback_received', 'proof_submitted', 'verified',
  };

  static String _inr(Decimal d) {
    final v = d.toDouble();
    final whole = v == v.roundToDouble();
    return '₹${NumberFormat(whole ? '#,##,##0' : '#,##,##0.00', 'en_IN').format(v)}';
  }

  @override
  Widget build(BuildContext context) {
    final q = booking.quote;
    if (q == null || !(q.isAccepted)) return const SizedBox.shrink();

    final total = q.displayTotal;
    final pct = q.advancePercent ?? Decimal.fromInt(50);
    final reqAdvance = q.requiresAdvance || (q.advancePercent != null && q.advancePercent! > Decimal.zero);
    final advanceRequired = !reqAdvance
        ? Decimal.zero
        : (q.advanceAmount ?? ((total * pct) / Decimal.fromInt(100)).toDecimal());
    final remaining = q.balanceAmount ?? (total - advanceRequired);

    final pay = booking.paymentStatus.toLowerCase();
    final balancePaid = pay == 'paid';
    final advancePaid = balancePaid || pay == 'collected' || pay == 'partially_paid' || pay == 'partial';
    final workDone = _completionStates.contains(booking.status.toLowerCase());

    if (balancePaid) {
      return _Shell(
        color: const Color(0xFFECFDF5),
        border: const Color(0xFF10B981),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF065F46), size: 18),
              SizedBox(width: 6),
              Text('Fully Paid', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Color(0xFF065F46))),
            ]),
            const SizedBox(height: 4),
            Text('Quotation total of ${_inr(total)} has been fully paid.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
          ],
        ),
      );
    }

    final String badge = !advancePaid
        ? (reqAdvance ? 'Awaiting Advance (${pct.toStringAsFixed(0)}%)' : 'Work in Progress')
        : 'Awaiting Balance';

    return _Shell(
      color: Colors.white,
      border: AppColors.swatchE3E8F0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Row(children: [
                  Text('Quote Accepted', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Color(0xFF10B981))),
                  SizedBox(width: 4),
                  Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 17),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: !advancePaid ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: !advancePaid ? const Color(0xFFB45309) : const Color(0xFF1E40AF))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Row(
              children: [
                _Figure(label: 'Quote Total', value: _inr(total)),
                _Figure(
                  label: reqAdvance ? '${pct.toStringAsFixed(0)}% Advance' : 'Advance',
                  value: '${_inr(advanceRequired)}${advancePaid ? ' ✓' : ''}',
                  color: !advancePaid ? const Color(0xFF7C3AED) : const Color(0xFF065F46),
                ),
                _Figure(
                  label: reqAdvance ? 'Remaining ${(Decimal.fromInt(100) - pct).toStringAsFixed(0)}%' : 'Balance on Completion',
                  value: _inr(remaining),
                  color: (advancePaid && !balancePaid) ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!advancePaid && reqAdvance)
            _Note('${pct.toStringAsFixed(0)}% advance will be collected directly by your technician upon arrival')
          else if (!advancePaid)
            _Note('Zero Advance · Total ${_inr(total)} will be collected by your technician upon completion')
          else if (workDone)
            _Note('Outstanding balance of ${_inr(remaining)} will be collected directly by your technician')
          else
            const _Note('Advance verified. The remaining balance will be collected upon service completion.', dashed: true),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, required this.color, required this.border});
  final Widget child;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: 1.5),
        ),
        child: child,
      );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color = AppColors.navy});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                maxLines: 2,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.dashed = false});
  final String text;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: dashed ? const Color(0xFFF8FAFC) : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: dashed ? const Color(0xFFCBD5E1) : const Color(0xFFBBF7D0)),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: dashed ? const Color(0xFF64748B) : const Color(0xFF166534))),
      );
}
