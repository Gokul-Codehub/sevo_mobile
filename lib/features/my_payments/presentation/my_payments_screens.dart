import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/safe_back.dart';
import '../../../core/refresh/refresh_runner.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/date_utils.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../data/my_payments_repository.dart';

String rupees(double v) => '₹${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

AppBar _bar(BuildContext context, String title) => AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
      leading: BackButton(onPressed: context.goBack),
      backgroundColor: Colors.white,
      foregroundColor: AppColors.navy,
      elevation: 0,
    );

// ─────────────────────────────── Payment history ───────────────────────────────

/// Profile -> My payments: every payment, with a clear outcome. Tap a service payment to open its booking.
class PaymentHistoryScreen extends ConsumerStatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  ConsumerState<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  PaymentOutcome? _filter;

  static const _filters = <(String, PaymentOutcome?)>[
    ('All', null),
    ('Paid', PaymentOutcome.paid),
    ('Refunded', PaymentOutcome.refunded),
    ('Failed', PaymentOutcome.failed),
  ];

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(paymentHistoryProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _bar(context, 'My payments'),
      body: history.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(paymentHistoryProvider)),
        data: (h) {
          final rows = h.records.where((r) => _filter == null || r.outcome == _filter).toList();
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(paymentHistoryProvider);
              return RefreshRunner.run(context, [() => ref.read(paymentHistoryProvider.future)]);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Expanded(child: _Total(label: 'Total paid', value: rupees(h.totalPaid), color: AppColors.navy)),
                  const SizedBox(width: 10),
                  Expanded(child: _Total(label: 'Refunded', value: rupees(h.totalRefunded), color: const Color(0xFF1B7F4B))),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  for (final f in _filters)
                    ChoiceChip(
                      label: Text(f.$1),
                      selected: _filter == f.$2,
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(color: _filter == f.$2 ? Colors.white : AppColors.navy, fontWeight: FontWeight.w600),
                      onSelected: (_) => setState(() => _filter = f.$2),
                    ),
                ]),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No payments here yet',
                      body: 'Payments for your bookings and grocery orders will appear here.',
                    ),
                  )
                else
                  for (final r in rows) _PaymentTile(record: r),
                Center(child: TextButton(onPressed: () => context.push('/support/new?topic=payment'), child: const Text('Problem with a payment? Ask support'))),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E8EE))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ]),
      );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.record});
  final PaymentRecord record;

  (Color, IconData) get _style => switch (record.outcome) {
        PaymentOutcome.paid => (const Color(0xFF1B7F4B), Icons.check_circle_rounded),
        PaymentOutcome.refunded => (const Color(0xFF1E5AA8), Icons.undo_rounded),
        PaymentOutcome.failed => (AppColors.error, Icons.cancel_rounded),
        PaymentOutcome.pending => (const Color(0xFFB26A00), Icons.schedule_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _style;
    final canOpen = record.bookingId != null;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE3E8EE))),
      child: ListTile(
        onTap: canOpen ? () => context.push('/bookings/${record.bookingId}') : null,
        leading: Icon(icon, color: color),
        title: Text(record.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          if (record.createdAt != null) formatDmy(record.createdAt!),
          if (record.method.isNotEmpty) record.method,
          if (record.reference.isNotEmpty) record.reference,
        ].join(' - ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(rupees(record.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(record.statusLabel, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Refund tracking ───────────────────────────────

/// Profile -> My refunds: where each refund is, as a simple progress bar of steps.
class RefundsScreen extends ConsumerWidget {
  const RefundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refunds = ref.watch(myRefundsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _bar(context, 'My refunds'),
      body: refunds.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(myRefundsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.undo_rounded,
              title: 'No refunds',
              body: 'When you cancel a paid booking or request a refund, you can follow it here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(myRefundsProvider);
              return RefreshRunner.run(context, [() => ref.read(myRefundsProvider.future)]);
            },
            child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final r in list) RefundCard(refund: r),
              Center(child: TextButton(onPressed: () => context.push('/support/new?topic=refund'), child: const Text('Refund not received? Ask support'))),
            ]),
          );
        },
      ),
    );
  }
}

class RefundCard extends StatelessWidget {
  const RefundCard({super.key, required this.refund});
  final RefundRecord refund;

  static const _steps = ['Requested', 'Under review', 'Approved', 'Processing', 'Refunded'];

  int get _reached => switch (refund.stage) {
        RefundStage.requested => 0,
        RefundStage.underReview || RefundStage.needsInfo => 1,
        RefundStage.approved => 2,
        RefundStage.processing => 3,
        RefundStage.refunded => 4,
        RefundStage.rejected => 1,
      };

  String get _message => switch (refund.stage) {
        RefundStage.requested || RefundStage.underReview => 'We are reviewing your request. This usually takes a short while.',
        RefundStage.needsInfo => 'We need a little more information from you. Please contact support from the help page.',
        RefundStage.approved => 'Approved. It will be sent to your original payment method.',
        RefundStage.processing => 'Your refund is being processed by our finance team.',
        RefundStage.refunded => 'Done. The money has been returned to you.',
        RefundStage.rejected => 'This refund was not approved. You can ask support to look at it again.',
      };

  @override
  Widget build(BuildContext context) {
    final rejected = refund.stage == RefundStage.rejected;
    final done = refund.stage == RefundStage.refunded;
    final color = rejected ? AppColors.error : (done ? const Color(0xFF1B7F4B) : AppColors.navy);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E8EE))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(refund.serviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text(rupees(refund.amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ]),
          const SizedBox(height: 2),
          Text(
            [if (refund.bookingRef.isNotEmpty) refund.bookingRef, if (refund.createdAt != null) 'Requested ${formatDmy(refund.createdAt!)}'].join(' - '),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < _steps.length; i++) ...[
              _Dot(active: !rejected && i <= _reached, current: i == _reached, color: color),
              if (i < _steps.length - 1) Expanded(child: Container(height: 2, color: !rejected && i < _reached ? color : const Color(0xFFD5DCE8))),
            ],
          ]),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final s in _steps) Text(s, style: const TextStyle(fontSize: 9.5, color: Colors.black54))],
          ),
          const SizedBox(height: 10),
          Text(refund.statusLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(_message, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Colors.black87)),
          if (refund.approvedAmount != null && refund.approvedAmount != refund.requestedAmount)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('You asked for ${rupees(refund.requestedAmount)}; approved ${rupees(refund.approvedAmount!)}.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          if (refund.bookingId != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => context.push('/bookings/${refund.bookingId}'), child: const Text('View booking')),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.current, required this.color});
  final bool active;
  final bool current;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: current ? 16 : 12,
        height: current ? 16 : 12,
        decoration: BoxDecoration(
          color: active ? color : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: active ? color : const Color(0xFFD5DCE8), width: 2),
        ),
        child: active ? const Icon(Icons.check, size: 9, color: Colors.white) : null,
      );
}
