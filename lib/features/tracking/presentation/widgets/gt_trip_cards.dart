import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../booking/data/booking_repository.dart';
import '../../../booking/domain/booking_models.dart';
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
  // Fetched directly: `ref.read(...future)` on the auto-disposed detail
  // provider can be disposed (and its request dropped) before it resolves
  // when no screen is watching it.
  final result = await ref.read(bookingRepositoryProvider).getBookingDetail(bookingId);
  final Booking booking;
  switch (result) {
    case Success(:final data):
      booking = data;
    case Failure(:final error):
      throw error;
  }
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
      if (!mounted) return;
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


// ── Rate the trip ────────────────────────────────────────────────────────────

/// "Rate your trip" — shown once the server has issued a feedback token for a
/// delivered Goods & Transport / Packers & Movers trip (the `feedback` block of
/// the tracking payload). Opens the normal feedback screen with that token.
class GtRateTripCard extends StatelessWidget {
  const GtRateTripCard({
    super.key,
    required this.token,
    this.submitted = false,
    this.rating,
  });

  final String token;
  final bool submitted;
  final int? rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(Colors.white, const Color(0xFFE6E8EE)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4D6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  submitted ? 'Thanks for your feedback' : 'Rate your trip',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  submitted
                      ? (rating != null ? 'You rated this trip $rating/5.' : 'Your rating was received.')
                      : 'How was your driver and delivery?',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (!submitted)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.navy),
              onPressed: () => context.push('/feedback/$token'),
              child: const Text('Rate', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Route / quote changes after booking + driver chat (web parity:
// ChangeDropCard, PTLRequoteCard, StopsAmendmentCard, the My Bookings stops
// editor and the tracking-page chat). The server previews and prices every
// change; these widgets only send addresses / weights and echo its answers.
// ════════════════════════════════════════════════════════════════════════════

Map<String, dynamic>? _dataOf(dynamic body) {
  if (body is Map && body['data'] is Map) {
    return Map<String, dynamic>.from(body['data'] as Map);
  }
  return body is Map ? Map<String, dynamic>.from(body) : null;
}

String _money2(dynamic v) {
  final n = double.tryParse('${v ?? ''}');
  return n == null ? '${v ?? ''}' : n.toStringAsFixed(2);
}

/// The raw response body of a failed request (the error interceptor keeps it).
Map<String, dynamic>? _errBody(Object e) {
  if (e is DioException && e.response?.data is Map) {
    return Map<String, dynamic>.from(e.response!.data as Map);
  }
  return null;
}

InputDecoration _fieldDeco(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

// ── Change drop (en-route destination change) ────────────────────────────────

class GtChangeDropCard extends ConsumerStatefulWidget {
  const GtChangeDropCard({super.key, required this.bookingId, this.onChanged});

  final int bookingId;
  final VoidCallback? onChanged;

  @override
  ConsumerState<GtChangeDropCard> createState() => _GtChangeDropCardState();
}

class _GtChangeDropCardState extends ConsumerState<GtChangeDropCard> {
  final _address = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String _error = '';
  Map<String, dynamic>? _preview;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  String get _path => '/booking/${widget.bookingId}/change-drop/';

  Future<void> _check() async {
    final text = _address.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _preview = null;
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .get(_path, queryParameters: {'drop_address': text});
      if (mounted) setState(() => _preview = _dataOf(res.data));
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await ref
          .read(apiClientProvider)
          .post(_path, data: {'drop_address': _address.text.trim()});
      if (!mounted) return;
      AppToast.show(context, 'Drop location updated. Your driver has been notified.');
      setState(() {
        _open = false;
        _preview = null;
        _address.clear();
      });
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _open = true),
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            label: const Text('Change drop location'),
          ),
        ),
      );
    }
    final p = _preview;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(const Color(0xFFF8FAFC), const Color(0xFFBFDBFE)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _address,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            decoration: _fieldDeco('New drop address',
                hint: 'Full address incl. area and city'),
            onChanged: (_) => setState(() => _preview = null),
          ),
          if (p != null) ...[
            const SizedBox(height: 10),
            Text(
              'Route: ${p['old_distance_km']} km → ${p['new_distance_km']} km\n'
              'Fare: ₹${p['old_payable']} → ₹${p['new_payable']}'
              '${p['minimum_fare_applied'] == true ? ' (minimum fare)' : ''}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, height: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Priced at your booked rate of ₹${p['rate_applied']}/km. The final fare is confirmed against the actual distance at drop.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy || (p == null && _address.text.trim().isEmpty)
                      ? null
                      : (p == null ? _check : _confirm),
                  child: Text(_busy
                      ? 'Please wait…'
                      : (p == null ? 'Check new fare' : 'Confirm & update driver')),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _open = false;
                          _preview = null;
                          _error = '';
                        }),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Light PTL quote revision ─────────────────────────────────────────────────

class GtPtlRequoteCard extends ConsumerStatefulWidget {
  const GtPtlRequoteCard(
      {super.key, required this.bookingId, this.currentWeightKg, this.onChanged});

  final int bookingId;
  final String? currentWeightKg;
  final VoidCallback? onChanged;

  @override
  ConsumerState<GtPtlRequoteCard> createState() => _GtPtlRequoteCardState();
}

class _GtPtlRequoteCardState extends ConsumerState<GtPtlRequoteCard> {
  late final TextEditingController _weight =
      TextEditingController(text: widget.currentWeightKg ?? '');
  final _address = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String _error = '';
  Map<String, dynamic>? _preview;

  @override
  void dispose() {
    _weight.dispose();
    _address.dispose();
    super.dispose();
  }

  String get _path => '/booking/${widget.bookingId}/ptl-requote/';

  bool get _canPreview {
    final w = _weight.text.trim();
    final changed = w.isNotEmpty && w != (widget.currentWeightKg ?? '');
    return (changed || _address.text.trim().isNotEmpty) &&
        !((double.tryParse(w) ?? 1) <= 0);
  }

  String _err(Object e) {
    if (e is DioException && (e.response?.statusCode == 401 || e.response?.statusCode == 403)) {
      return 'Only the signed-in customer who made this booking can revise its quote.';
    }
    return _errorText(e);
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _preview = null;
    });
    try {
      final res = await ref.read(apiClientProvider).get(_path, queryParameters: {
        if (_weight.text.trim().isNotEmpty) 'declared_weight_kg': _weight.text.trim(),
        if (_address.text.trim().isNotEmpty) 'drop_address': _address.text.trim(),
      });
      if (mounted) setState(() => _preview = _dataOf(res.data));
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final p = _preview;
    if (p == null || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final body = <String, dynamic>{
      'declared_weight_kg': p['declared_weight_kg'],
      'quote_id': p['quote_id'],
      'quote_hash': p['quote_hash'],
      'expires_at': p['expires_at'],
      'total_amount': p['total'],
      if (_address.text.trim().isNotEmpty) ...{
        'drop_latitude': p['drop_lat'],
        'drop_longitude': p['drop_lng'],
        'drop_address': _address.text.trim(),
      },
    };
    try {
      await ref.read(apiClientProvider).post(_path, data: body);
      if (!mounted) return;
      AppToast.show(context, 'Quote updated.');
      setState(() {
        _open = false;
        _preview = null;
        _address.clear();
      });
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _open = true),
            icon: const Icon(Icons.scale_outlined, size: 18),
            label: const Text('Revise quote (weight / drop)'),
          ),
        ),
      );
    }
    final p = _preview;
    final charged = p?['chargeable_weight_kg'];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(const Color(0xFFF8FAFC), const Color(0xFFBFDBFE)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Revise Part Truck Load quote',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _fieldDeco('Declared weight (kg)'),
            onChanged: (_) => setState(() => _preview = null),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            minLines: 1,
            maxLines: 3,
            decoration: _fieldDeco('New drop address (optional)',
                hint: 'Leave blank to keep the current drop'),
            onChanged: (_) => setState(() => _preview = null),
          ),
          if (p != null) ...[
            const SizedBox(height: 10),
            Text(
              'Weight: ${p['declared_weight_kg']} kg'
              '${charged != null && '$charged' != '${p['declared_weight_kg']}' ? ' (charged as $charged kg)' : ''}\n'
              'Fare: ₹${p['old_payable']} → ₹${p['new_payable']}'
              '${p['minimum_fare_applied'] == true ? ' (minimum fare)' : ''}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, height: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${p['rate_per_kg']}/kg. You load and unload the goods. This quote is valid for a limited time.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy || (p == null && !_canPreview)
                      ? null
                      : (p == null ? _check : _confirm),
                  child: Text(_busy
                      ? 'Please wait…'
                      : (p == null ? 'Check new price' : 'Confirm new quote')),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _open = false;
                          _preview = null;
                          _error = '';
                        }),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stops editor + fare amendment (paid bookings) ────────────────────────────

class _StopDraft {
  _StopDraft({String type = 'WAYPOINT', String address = '', String phone = '', this.name = '', this.notes = ''})
      : type = type,
        address = TextEditingController(text: address),
        phone = TextEditingController(text: phone);

  final String type;
  final TextEditingController address;
  final TextEditingController phone;
  final String name;
  final String notes;

  Map<String, dynamic> toJson() => {
        'stop_type': type,
        'address': address.text.trim(),
        'contact_name': name,
        'contact_phone': phone.text.trim(),
        'notes': notes,
      };

  void dispose() {
    address.dispose();
    phone.dispose();
  }
}

/// "Manage stops" on a logistics booking: GET / PUT `/booking/<id>/stops/`.
/// A paid booking whose fare would change answers AMENDMENT_REQUIRED; the
/// [GtStopsAmendmentCard] below then carries the customer's decision.
class GtStopsEditorCard extends ConsumerStatefulWidget {
  const GtStopsEditorCard({super.key, required this.bookingId});

  final int bookingId;

  @override
  ConsumerState<GtStopsEditorCard> createState() => _GtStopsEditorCardState();
}

class _GtStopsEditorCardState extends ConsumerState<GtStopsEditorCard> {
  final List<_StopDraft> _draft = [];
  bool _open = false;
  bool _loading = false;
  bool _saving = false;
  String _error = '';
  String _saved = '';
  Map<String, dynamic>? _amendment;

  String get _path => '/booking/${widget.bookingId}/stops/';

  @override
  void dispose() {
    for (final d in _draft) {
      d.dispose();
    }
    super.dispose();
  }

  void _setDraft(List<_StopDraft> next) {
    for (final d in _draft) {
      d.dispose();
    }
    _draft
      ..clear()
      ..addAll(next);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ref.read(apiClientProvider).get(_path);
      final body = res.data;
      final list = body is Map ? body['data'] : body;
      final stops = <_StopDraft>[
        for (final s in (list is List ? list : const []))
          if (s is Map)
            _StopDraft(
              type: (s['stop_type'] ?? 'WAYPOINT').toString(),
              address: (s['address'] ?? '').toString(),
              phone: (s['contact_phone'] ?? '').toString(),
              name: (s['contact_name'] ?? '').toString(),
              notes: (s['notes'] ?? '').toString(),
            ),
      ];
      if (mounted) setState(() => _setDraft(stops));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load existing stops.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_draft.any((d) => d.address.text.trim().isEmpty)) {
      setState(() => _error = 'Every stop needs an address.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
      _saved = '';
    });
    try {
      final res = await ref.read(apiClientProvider).put(
        _path,
        data: {'stops': [for (final d in _draft) d.toJson()]},
      );
      final body = res.data;
      final pricing = body is Map && body['meta'] is Map ? (body['meta'] as Map)['pricing'] : null;
      if (mounted) {
        setState(() => _saved = pricing is Map
            ? 'Stops saved. Fare updated to ₹${pricing['new_payable']} (was ₹${pricing['old_payable']}).'
            : 'Stops saved.');
      }
    } catch (e) {
      final err = _errBody(e)?['error'];
      if (err is Map && err['code'] == 'AMENDMENT_REQUIRED' && err['amendment'] is Map) {
        // Paid booking: the server changed nothing; the customer must approve.
        if (mounted) {
          setState(() {
            _amendment = Map<String, dynamic>.from(err['amendment'] as Map);
            _saved = 'This change alters your paid fare. Review and approve it below.';
          });
        }
      } else if (mounted) {
        setState(() => _error = err is Map && (err['message'] ?? '').toString().isNotEmpty
            ? err['message'].toString()
            : _errorText(e, 'Could not save stops.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(Colors.white, const Color(0xFFE6E8EE)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() => _open = !_open);
              if (_open) _load();
            },
            child: Row(
              children: [
                const Icon(Icons.alt_route_rounded, size: 18, color: AppColors.navy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Manage stops',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
              ),
            if (_saved.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_saved, style: const TextStyle(color: Color(0xFF047857), fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Loading stops…', style: TextStyle(color: AppColors.textSecondary)),
              )
            else ...[
              if (_draft.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('No extra stops yet - just the default pickup and drop.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ),
              for (var i = 0; i < _draft.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(top: 10, right: 8),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                        child: Text(_draft[i].type == 'PICKUP' ? 'P' : _draft[i].type == 'DROP' ? 'D' : '${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: _draft[i].address,
                              minLines: 1,
                              maxLines: 2,
                              decoration: _fieldDeco('Address'),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _draft[i].phone,
                              keyboardType: TextInputType.phone,
                              decoration: _fieldDeco('Contact phone (optional)'),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _draft.removeAt(i).dispose();
                        }),
                        icon: const Icon(Icons.close_rounded, color: AppColors.error, size: 20),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _draft.add(_StopDraft())),
                    child: const Text('+ Add stop'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save stops'),
                  ),
                ],
              ),
              GtStopsAmendmentCard(
                bookingId: widget.bookingId,
                initialAmendment: _amendment,
                onResolved: () {
                  setState(() => _amendment = null);
                  _load();
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Paid booking + a stop edit that changes the fare: the customer's explicit
/// decision (approve / cancel) and, for an increase, the top-up payment. The
/// route changes only once the server has recorded the payment.
class GtStopsAmendmentCard extends ConsumerStatefulWidget {
  const GtStopsAmendmentCard({
    super.key,
    required this.bookingId,
    this.initialAmendment,
    this.onResolved,
  });

  final int bookingId;
  final Map<String, dynamic>? initialAmendment;
  final VoidCallback? onResolved;

  @override
  ConsumerState<GtStopsAmendmentCard> createState() => _GtStopsAmendmentCardState();
}

class _GtStopsAmendmentCardState extends ConsumerState<GtStopsAmendmentCard> {
  Map<String, dynamic>? _am;
  bool _busy = false;
  bool _mine = false;
  String _msg = '';

  String get _path => '/booking/${widget.bookingId}/stops/amendment/';

  @override
  void initState() {
    super.initState();
    _am = widget.initialAmendment;
    if (_am == null) _load();
  }

  @override
  void didUpdateWidget(covariant GtStopsAmendmentCard old) {
    super.didUpdateWidget(old);
    if (widget.initialAmendment != old.initialAmendment) {
      setState(() => _am = widget.initialAmendment);
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    try {
      final res = await ref.read(apiClientProvider).get(_path);
      final next = _dataOf(res.data);
      if (mounted) setState(() => _am = next);
      return next;
    } catch (_) {
      return null;
    }
  }

  Future<void> _decide(String action) async {
    final am = _am;
    if (am == null || _busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .post(_path, data: {'action': action, 'amendment_id': am['id']});
      final d = _dataOf(res.data) ?? const <String, dynamic>{};
      final status = (d['status'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        if (status == 'APPROVED_PENDING_PAYMENT') {
          _msg = 'Approved. Pay ₹${_money2(d['top_up_amount'])} to apply the new route.';
        } else if (status == 'APPLIED') {
          _msg = d['refund'] != null
              ? 'Route updated. The fare difference will be refunded after review.'
              : 'Route updated.';
        } else if (status == 'CANCELLED') {
          _msg = 'Change cancelled. Your booking is unchanged.';
        }
      });
      await _load();
      widget.onResolved?.call();
    } catch (e) {
      if (mounted) setState(() => _msg = _errorText(e));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    ref.listen<PaymentState>(paymentControllerProvider, (prev, next) async {
      if (!_mine || !mounted) return;
      if (next is PaymentSuccess || next is PaymentFailed) {
        final ok = next is PaymentSuccess;
        // Never assume success: re-read the server state.
        final fresh = await _load();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _mine = false;
          _msg = ok
              ? (fresh == null
                  ? 'Payment received. Your route has been updated.'
                  : 'Payment received. We are confirming it; your route updates as soon as it is recorded.')
              : (next as PaymentFailed).errorMessage;
        });
        widget.onResolved?.call();
      }
    });

    final am = _am;
    if (am == null ||
        !const {'PENDING_CUSTOMER_APPROVAL', 'APPROVED_PENDING_PAYMENT'}
            .contains((am['status'] ?? '').toString())) {
      return const SizedBox.shrink();
    }
    final diff = double.tryParse('${am['difference']}') ?? 0;
    final increase = diff > 0;
    final exp = DateTime.tryParse('${am['expires_at'] ?? ''}');
    final expired = exp != null && !exp.isAfter(DateTime.now());
    final status = (am['status'] ?? '').toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(const Color(0xFFFFFBEB), const Color(0xFFFDE68A)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This route change needs your approval',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF78350F))),
          const SizedBox(height: 6),
          Text(
            'Paid fare: ₹${_money2(am['old_payable'])} · New fare: ₹${_money2(am['new_payable'])}\n'
            '${increase ? 'You pay ₹${_money2(diff)} more before the new route is applied.' : 'Difference of ₹${_money2(diff.abs())} will be refunded after review.'}',
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
          if ((double.tryParse('${am['new_distance_km']}') ?? 0) > 0)
            Text('New distance: ${_money2(am['new_distance_km'])} km · Stops: ${am['stops']}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          if (expired)
            const Text('This offer has expired. Edit the stops again.',
                style: TextStyle(fontSize: 11.5, color: AppColors.error)),
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_msg, style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E))),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'PENDING_CUSTOMER_APPROVAL' && !expired)
                FilledButton(
                  onPressed: _busy ? null : () => _decide('APPROVE'),
                  child: Text(increase ? 'Approve & continue to payment' : 'Approve change'),
                ),
              if (status == 'APPROVED_PENDING_PAYMENT' && !expired)
                FilledButton(
                  onPressed: _busy ? null : _pay,
                  child: Text(_busy ? 'Processing…' : 'Pay ₹${_money2(diff)} to apply the new route'),
                ),
              TextButton(
                onPressed: _busy ? null : () => _decide('CANCEL'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Cancel this change'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Chat with the driver / technician ────────────────────────────────────────

class BookingChatCard extends ConsumerStatefulWidget {
  const BookingChatCard({
    super.key,
    required this.bookingId,
    this.trackingToken,
    this.isLogistics = true,
  });

  final int bookingId;
  final String? trackingToken;

  /// Goods trip → "driver"; any other service → "technician".
  final bool isLogistics;

  @override
  ConsumerState<BookingChatCard> createState() => _BookingChatCardState();
}

class _BookingChatCardState extends ConsumerState<BookingChatCard> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = const [];
  Timer? _poll;
  bool _open = false;
  bool _sending = false;
  bool _unavailable = false;

  String get _path => '/booking/${widget.bookingId}/messages/';
  Map<String, dynamic>? get _query =>
      (widget.trackingToken ?? '').isEmpty ? null : {'token': widget.trackingToken};

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _poll?.cancel();
    if (_open) {
      _fetch();
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => _fetch());
    }
  }

  Future<void> _fetch() async {
    try {
      final res = await ref.read(apiClientProvider).get(_path, queryParameters: _query);
      final body = res.data;
      final raw = body is Map ? (body['data'] ?? body['results']) : body;
      final list = <Map<String, dynamic>>[
        for (final m in (raw is List ? raw : const []))
          if (m is Map) Map<String, dynamic>.from(m),
      ];
      if (!mounted) return;
      final grew = list.length != _messages.length;
      setState(() => _messages = list);
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } on DioException catch (e) {
      final c = e.response?.statusCode;
      if ((c == 401 || c == 403) && mounted) setState(() => _unavailable = true);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).post(
            _path,
            data: {'body': text, if ((widget.trackingToken ?? '').isNotEmpty) 'token': widget.trackingToken},
            queryParameters: _query,
          );
      _input.clear();
      await _fetch();
    } on DioException catch (e) {
      final c = e.response?.statusCode;
      if (mounted) {
        if (c == 401 || c == 403) {
          setState(() => _unavailable = true);
        } else {
          AppToast.show(context, _errorText(e, 'Message could not be sent.'),
              type: AppToastType.error);
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(Colors.white, const Color(0xFFE6E8EE)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppColors.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.isLogistics ? 'Chat with your driver' : 'Chat with your technician',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: _messages.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No messages yet. Say hello!',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m = _messages[i];
                        final mine = (m['sender_persona'] ?? '').toString().toLowerCase() == 'customer';
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            constraints: const BoxConstraints(maxWidth: 260),
                            decoration: BoxDecoration(
                              color: mine ? AppColors.navy : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!mine && (m['sender_name'] ?? '').toString().isNotEmpty)
                                  Text(m['sender_name'].toString(),
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                                Text((m['body'] ?? '').toString(),
                                    style: TextStyle(fontSize: 13, color: mine ? Colors.white : AppColors.textPrimary)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: _fieldDeco('Type a message'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
