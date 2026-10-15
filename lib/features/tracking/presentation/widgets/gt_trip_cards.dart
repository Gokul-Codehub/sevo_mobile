import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../booking/domain/booking_providers.dart';
import '../../../payment/domain/payment_controller.dart';
import '../../../payment/domain/payment_models.dart';
import '../../domain/tracking_models.dart';

/// Goods Transport / Packers & Movers cards shown on the live-tracking sheet.
/// They mirror the web tracking page (CustomerTrackingPage.jsx and
/// PMSurveyDecisionCard.jsx): the server owns every number, these widgets only
/// display what the tracking payload / survey endpoint returns and post the
/// customer's decision. Money is always settled through the normal payment
/// order (`/payment/initiate/`), which the server prices itself.

String _errorText(Object e, [String fallback = 'Something went wrong.']) {
  if (e is ApiError) return e.message;
  if (e is DioException) {
    final inner = e.error;
    if (inner is ApiError) return inner.message;
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'] ?? data['message'] ?? data['detail'];
      if (err is String && err.trim().isNotEmpty) return err;
      if (err is Map && (err['message'] ?? '').toString().isNotEmpty) {
        return err['message'].toString();
      }
    }
  }
  return fallback;
}

BoxDecoration _cardDeco(Color bg, Color border) => BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border),
    );

/// Starts the server-priced online payment for [bookingId] (the booking's
/// balance / survey top-up). Resolves the booking first because the payment
/// controller needs it for the checkout description.
Future<void> _startServerPricedPayment(WidgetRef ref, int bookingId) async {
  final booking = await ref.read(bookingDetailProvider(bookingId).future);
  await ref.read(paymentControllerProvider.notifier).startPayment(
        booking: booking,
        amount: Decimal.zero, // ignored: PaymentInitiateView decides the amount
        paymentType: 'balance',
      );
}

// ── Balance due ──────────────────────────────────────────────────────────────

/// "Balance due" — a prepaid trip whose final fare rose above what was paid.
class GtBalanceDueCard extends ConsumerStatefulWidget {
  const GtBalanceDueCard({super.key, required this.bookingId, required this.amount});

  final int bookingId;
  final String amount;

  @override
  ConsumerState<GtBalanceDueCard> createState() => _GtBalanceDueCardState();
}

class _GtBalanceDueCardState extends ConsumerState<GtBalanceDueCard> {
  bool _busy = false;
  bool _mine = false; // this card started the payment that is in flight

  Future<void> _pay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _mine = true;
    });
    try {
      await _startServerPricedPayment(ref, widget.bookingId);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, _errorText(e, 'Payment could not be started.'),
            type: AppToastType.error);
        setState(() {
          _busy = false;
          _mine = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaymentState>(paymentControllerProvider, (prev, next) {
      if (!_mine || !mounted) return;
      if (next is PaymentSuccess) {
        AppToast.show(context, 'Payment received. Thank you!');
        setState(() {
          _busy = false;
          _mine = false;
        });
      } else if (next is PaymentFailed) {
        AppToast.show(context, next.errorMessage, type: AppToastType.error);
        setState(() {
          _busy = false;
          _mine = false;
        });
      }
    });

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(const Color(0xFFEFF6FF), const Color(0xFF93C5FD)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Balance due: ₹${widget.amount}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A))),
          const SizedBox(height: 4),
          const Text(
            'The final fare is higher than what you paid online (extra distance, stops or waiting time).',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF1E40AF), height: 1.35),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: FilledButton(
              onPressed: _busy ? null : _pay,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.serviceBlue,
                minimumSize: const Size(140, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_busy ? 'Processing…' : 'Pay balance',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Extra charges (toll / parking) ───────────────────────────────────────────

class GtExtraChargesCard extends StatelessWidget {
  const GtExtraChargesCard({super.key, required this.charges});

  final List<TrackingExtraCharge> charges;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(const Color(0xFFF0F9FF), const Color(0xFFBAE6FD)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Toll / parking added by your driver',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF075985))),
          const SizedBox(height: 6),
          for (final c in charges)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${c.label}: ₹${c.amount}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0C4A6E))),
                  ),
                  if (c.receiptUrl != null)
                    InkWell(
                      onTap: () => launchUrl(Uri.parse(c.receiptUrl!),
                          mode: LaunchMode.externalApplication),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text('View receipt',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.serviceBlue)),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          const Text('Charged at the receipt amount and included in your final fare.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF0369A1))),
        ],
      ),
    );
  }
}

// ── Delivery exception ───────────────────────────────────────────────────────

class GtDeliveryExceptionCard extends StatelessWidget {
  const GtDeliveryExceptionCard({super.key, required this.exception});

  final TrackingDeliveryException exception;

  @override
  Widget build(BuildContext context) {
    final atPickup = exception.leg == 'EN_ROUTE_PICKUP' || exception.leg == 'LOADING';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(const Color(0xFFFFF7ED), const Color(0xFFFDBA74)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exception.label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF9A3412))),
          const SizedBox(height: 4),
          Text(
            'Your driver reported this at the ${atPickup ? 'pickup' : 'drop'} point. '
            'Please reach out to the driver or contact support so the trip can continue.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF7C2D12), height: 1.35),
          ),
        ],
      ),
    );
  }
}

// ── Packers & Movers: decision on the surveyed quote ─────────────────────────

/// Packers & Movers pre-move survey: the vendor confirms crew / vehicles and a
/// revised fare; the customer approves or declines before a deadline
/// (`GET/POST /booking/<id>/pm-survey-decision/`). A price increase on a
/// prepaid move is paid through the normal payment order and the server
/// releases the move once that payment is recorded.
class PmSurveyDecisionCard extends ConsumerStatefulWidget {
  const PmSurveyDecisionCard({super.key, required this.bookingId, this.trackingToken});

  final int bookingId;
  final String? trackingToken;

  @override
  ConsumerState<PmSurveyDecisionCard> createState() => _PmSurveyDecisionCardState();
}

class _PmSurveyDecisionCardState extends ConsumerState<PmSurveyDecisionCard> {
  Map<String, dynamic>? _info;
  bool _busy = false;
  bool _mine = false;
  String _msg = '';
  Timer? _tick;
  Timer? _refresh;
  DateTime _now = DateTime.now();

  String get _path => '/booking/${widget.bookingId}/pm-survey-decision/';
  Map<String, dynamic>? get _query =>
      (widget.trackingToken ?? '').isEmpty ? null : {'token': widget.trackingToken};

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // The vendor may confirm the survey while the customer has this screen open.
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).get(_path, queryParameters: _query);
      var data = res.data;
      if (data is Map && data['data'] is Map) data = data['data'];
      if (!mounted) return;
      setState(() => _info = data is Map ? Map<String, dynamic>.from(data) : null);
    } catch (_) {
      // No survey (or no access): the card simply stays hidden.
    }
  }

  Future<void> _decide(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .post(_path, data: {'action': action}, queryParameters: _query);
      var d = res.data;
      if (d is Map && d['data'] is Map) d = d['data'];
      final m = d is Map ? d : const {};
      final status = (m['status'] ?? '').toString();
      setState(() {
        if (status == 'APPROVED_PENDING_PAYMENT') {
          _msg = 'Quote approved. Pay ₹${m['top_up_amount']} to release your move.';
        } else if (status == 'APPROVED') {
          _msg = 'Quote approved. Your move is being scheduled.';
        } else if (status == 'CANCELLED') {
          _msg = 'Booking cancelled. Any amount you paid will be refunded.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _msg = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _pay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _mine = true;
      _msg = '';
    });
    try {
      await _startServerPricedPayment(ref, widget.bookingId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _mine = false;
          _msg = _errorText(e, 'Payment could not be started.');
        });
      }
    }
  }

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    ref.listen<PaymentState>(paymentControllerProvider, (prev, next) {
      if (!_mine || !mounted) return;
      if (next is PaymentSuccess) {
        setState(() {
          _busy = false;
          _mine = false;
          _msg = 'Payment received. Your move will be released shortly.';
        });
        _load();
      } else if (next is PaymentFailed) {
        setState(() {
          _busy = false;
          _mine = false;
          _msg = next.errorMessage;
        });
      }
    });

    final info = _info;
    if (info == null || info['has_survey'] != true) return const SizedBox.shrink();
    if (_s(info['status']).toUpperCase() != 'CONFIRMED') return const SizedBox.shrink();

    final approval = _s(info['approval_status']).toUpperCase();
    if (approval == 'QUOTE_EXPIRED') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: _cardDeco(const Color(0xFFFEF2F2), const Color(0xFFFECACA)),
        child: const Text(
          'The revised quote was not answered in time, so this booking was cancelled. '
          'Any amount you paid will be refunded.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF991B1B), height: 1.35),
        ),
      );
    }
    if (approval != 'PENDING_CUSTOMER_APPROVAL' && approval != 'APPROVED_PENDING_PAYMENT') {
      return const SizedBox.shrink();
    }

    final deadline = DateTime.tryParse(_s(info['decision_deadline']))?.toLocal();
    final left = deadline == null ? null : deadline.difference(_now);
    final timedOut = approval == 'PENDING_CUSTOMER_APPROVAL' &&
        left != null &&
        left.isNegative;
    String mmss() {
      final d = left == null || left.isNegative ? Duration.zero : left;
      final m = d.inMinutes;
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    final diff = double.tryParse(_s(info['fare_difference']));
    final survey = info['survey'] is Map ? Map<String, dynamic>.from(info['survey'] as Map) : const {};
    final topUp = _s(survey['top_up_required']);
    const strong = TextStyle(fontWeight: FontWeight.w800);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(const Color(0xFFFFFBEB), const Color(0xFFFDE68A)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pre-move survey: confirm your final quote',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF78350F))),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textPrimary),
              children: [
                const TextSpan(text: 'Crew: '),
                TextSpan(text: _s(info['confirmed_crew']).isEmpty ? '-' : _s(info['confirmed_crew']), style: strong),
                const TextSpan(text: '  ·  Vehicles: '),
                TextSpan(text: _s(info['confirmed_vehicles']).isEmpty ? '-' : _s(info['confirmed_vehicles']), style: strong),
                if (_s(info['original_fare']).isNotEmpty) ...[
                  const TextSpan(text: '\nOriginal fare: '),
                  TextSpan(text: '₹${_s(info['original_fare'])}', style: strong),
                ],
                const TextSpan(text: '\nFinal quote: '),
                TextSpan(text: '₹${_s(info['revised_fare'])}', style: strong),
                if (diff != null && diff != 0) ...[
                  const TextSpan(text: '\nChange: '),
                  TextSpan(
                    text: '${diff > 0 ? '+' : '-'}₹${diff.abs().toStringAsFixed(2)}',
                    style: strong.copyWith(
                        color: diff > 0 ? const Color(0xFFB91C1C) : const Color(0xFF1E3A8A)),
                  ),
                  TextSpan(
                    text: diff > 0
                        ? ' (you pay the difference before the move)'
                        : ' (the difference is refunded)',
                  ),
                ],
              ],
            ),
          ),
          if (_s(info['change_reason']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Reason: ${_s(info['change_reason'])}',
                  style: const TextStyle(fontSize: 12)),
            ),
          if (_s(info['change_note']).isNotEmpty)
            Text('Note from the vendor: ${_s(info['change_note'])}',
                style: const TextStyle(fontSize: 12)),
          if (approval == 'PENDING_CUSTOMER_APPROVAL' && deadline != null) ...[
            const SizedBox(height: 6),
            Text(
              timedOut
                  ? 'Time to decide has run out. This booking is being cancelled.'
                  : 'Please decide within ${mmss()} or the booking is cancelled.',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: timedOut ? const Color(0xFFB91C1C) : const Color(0xFF92400E)),
            ),
          ],
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_msg, style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E))),
          ],
          const SizedBox(height: 10),
          if (approval == 'PENDING_CUSTOMER_APPROVAL' && !timedOut)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _decide('APPROVE'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D253A),
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Approve quote', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _decide('CANCEL'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE2E2),
                      foregroundColor: const Color(0xFFB91C1C),
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Decline & cancel', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          if (approval == 'APPROVED_PENDING_PAYMENT')
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.serviceBlue,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _busy
                      ? 'Processing…'
                      : (topUp.isEmpty
                          ? 'Pay to release the move'
                          : 'Pay ₹$topUp to release the move'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
