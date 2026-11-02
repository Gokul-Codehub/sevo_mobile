import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/date_utils.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_status.dart';
import '../../domain/grocery_fee_split.dart';

const _green = Color(0xFF1B7F4B);
const _greenSoft = Color(0xFFE8F6EE);
const _line = Color(0xFFE2E8F0);

/// The five steps a grocery / vegetable order shows. There is no map for these orders - only status.
class GroceryStep {
  const GroceryStep(this.label, this.title, this.subtitle, this.icon);
  final String label; // short, under the progress icon
  final String title; // timeline heading
  final String subtitle;
  final IconData icon;
}

const List<GroceryStep> kGrocerySteps = [
  GroceryStep('Placed', 'Order Placed', 'Your order has been received', Icons.receipt_long_outlined),
  GroceryStep('Confirmed', 'Order Confirmed', 'The seller has accepted your order', Icons.check_circle_outline),
  GroceryStep('Packed', 'Packed', 'Your items are packed and ready', Icons.inventory_2_outlined),
  GroceryStep('On the way', 'Out for Delivery', 'Your order is on the way to you', Icons.delivery_dining_outlined),
  GroceryStep('Delivered', 'Delivered', 'Your order has been delivered', Icons.home_outlined),
];

/// Which of [kGrocerySteps] a booking stage is at. The booking pipeline has six stages; "on the way" and
/// "in progress" (handing over) are both "Out for Delivery" for a grocery order. Null = the order ended without
/// being delivered (cancelled and the like).
int? groceryStepFor(BookingStage stage) => switch (stage) {
      BookingStage.requested => 0,
      BookingStage.confirmed => 1,
      BookingStage.assigned => 2,
      BookingStage.onTheWay || BookingStage.inProgress => 3,
      BookingStage.completed => 4,
      BookingStage.ended || BookingStage.cancelled => null,
    };

String _rupees(num v) => '₹${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

/// Order status page for grocery and vegetable bookings.
///
/// [status] is the freshest status the screen knows (own record or live snapshot), so this widget stays a pure
/// function of its inputs. [itemThumb] draws a product picture (the screen supplies one that looks missing
/// pictures up).
class GroceryOrderStatusView extends StatelessWidget {
  const GroceryOrderStatusView({
    super.key,
    required this.booking,
    required this.status,
    required this.itemThumb,
    required this.onHelp,
    this.onCancel,
    this.onInvoice,
    this.feeLines,
  });

  final Booking booking;
  final String status;

  /// The order's fees listed one by one (delivery, handling, small order), when they could be rebuilt exactly;
  /// null shows them as one combined line.
  final List<FeeLine>? feeLines;
  final Widget Function(ServiceItem service) itemThumb;
  final VoidCallback onHelp;
  final VoidCallback? onCancel;
  final VoidCallback? onInvoice;

  @override
  Widget build(BuildContext context) {
    final stage = bookingStageOf(status);
    final step = groceryStepFor(stage);
    final ended = step == null;
    final otp = (booking.startOtp ?? booking.deliveryOtp ?? '').trim();
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 20 + MediaQuery.paddingOf(context).bottom),
      children: [
        _Header(booking: booking, step: step, onInvoice: ended ? null : onInvoice),
        if (ended)
          _EndedCard(status: status)
        else ...[
          if (step == 3 && otp.isNotEmpty) _OtpCard(otp: otp),
          _TimelineCard(booking: booking, step: step),
          if (step >= 3 && booking.technician != null) _PartnerCard(booking: booking, step: step),
        ],
        _ItemsCard(booking: booking, itemThumb: itemThumb, feeLines: feeLines),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _AddressCard(booking: booking)),
          const SizedBox(width: 12),
          Expanded(child: _PaymentCard(booking: booking)),
        ]),
        _HelpCard(onHelp: onHelp, onCancel: onCancel),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.margin = const EdgeInsets.only(bottom: 12)});
  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: margin,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: child,
      );
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.navy)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        ]),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.booking, required this.step, this.onInvoice});
  final Booking booking;
  final int? step;
  final VoidCallback? onInvoice;

  @override
  Widget build(BuildContext context) {
    final label = step == null ? booking.statusLabel : kGrocerySteps[step!].title;
    final color = step == null ? const Color(0xFFC62828) : (step == 4 ? _green : const Color(0xFFE65100));
    return _Card(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
              Text('Order ${booking.requestId}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
            ]),
            if (booking.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Placed on ${formatDmyTime(booking.createdAt!.toLocal())}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
          ]),
        ),
        if (onInvoice != null)
          OutlinedButton.icon(
            onPressed: onInvoice,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Invoice'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), visualDensity: VisualDensity.compact),
          ),
      ]),
    );
  }
}

class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.otp});
  final String otp;

  @override
  Widget build(BuildContext context) => _Card(
        child: Row(children: [
          const Icon(Icons.verified_user_outlined, color: _green),
          const SizedBox(width: 12),
          const Expanded(child: Text('Share this code with the delivery partner when you receive your order.', style: TextStyle(fontSize: 12.5, height: 1.35))),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(otp, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 3, color: _green)),
          ),
        ]),
      );
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.booking, required this.step});
  final Booking booking;
  final int? step;

  @override
  Widget build(BuildContext context) {
    final current = step!;
    final eta = [
      if (booking.scheduledDate.isNotEmpty) formatDateString(booking.scheduledDate),
      if (booking.scheduledTimeSlot.isNotEmpty) booking.scheduledTimeSlot,
    ].join(' · ');
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Title('Order Timeline', sub: eta.isEmpty ? null : 'Estimated delivery: $eta'),
        for (var i = 0; i < kGrocerySteps.length; i++)
          _TimelineRow(
            info: kGrocerySteps[i],
            done: i < current || current == kGrocerySteps.length - 1,
            current: i == current && current != kGrocerySteps.length - 1,
            last: i == kGrocerySteps.length - 1,
            // Only the placed time is recorded on the booking; later steps show no invented times.
            time: i == 0 && booking.createdAt != null ? formatDmyTime(booking.createdAt!.toLocal()) : null,
          ),
      ]),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.info, required this.done, required this.current, required this.last, this.time});
  final GroceryStep info;
  final bool done;
  final bool current;
  final bool last;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final reached = done || current;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, color: reached ? _green : const Color(0xFFF1F5F9)),
              child: Icon(done ? Icons.check_rounded : info.icon, size: 16, color: reached ? Colors.white : AppColors.textSecondary),
            ),
            if (!last) Expanded(child: Container(width: 2, color: done ? _green : _line)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 18, top: 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(info.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: reached ? AppColors.navy : AppColors.textSecondary))),
                if (current) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Current', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
                  ),
                ],
              ]),
              Text(info.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              if (time != null) Text(time!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = normalizeBookingStatus(status);
    final text = switch (s) {
      'refund_requested' => 'This order was cancelled. Your refund is in progress.',
      'refunded' => 'This order was cancelled and the amount has been refunded.',
      _ => 'This order was cancelled.',
    };
    return _Card(
      child: Row(children: [
        const Icon(Icons.cancel_outlined, color: Color(0xFFC62828)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
      ]),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.booking, required this.step});
  final Booking booking;
  final int? step;

  @override
  Widget build(BuildContext context) {
    final t = booking.technician!;
    final phone = (t.phone ?? '').trim();
    return _Card(
      child: Row(children: [
        const CircleAvatar(radius: 20, backgroundColor: _greenSoft, child: Icon(Icons.delivery_dining_rounded, color: _green)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Delivery partner', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          ]),
        ),
        if (phone.isNotEmpty)
          IconButton.filledTonal(
            tooltip: 'Call delivery partner',
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            icon: const Icon(Icons.call_rounded),
          ),
      ]),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.booking, required this.itemThumb, this.feeLines});
  final List<FeeLine>? feeLines;
  final Booking booking;
  final Widget Function(ServiceItem service) itemThumb;

  @override
  Widget build(BuildContext context) {
    final count = booking.items.fold<int>(0, (s, i) => s + i.quantity);
    final itemsTotal = booking.items.fold<Decimal>(Decimal.zero, (s, i) => s + i.totalPrice);
    // The order total also carries delivery / handling / small-order fees, taxes and tip, minus any coupon. The booking
    // stores only the final total, so what is not items is shown as one honest line rather than a wrong sum.
    final other = booking.totalAmount - itemsTotal;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Title('Order Items'),
        for (final i in booking.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 52, height: 52, child: itemThumb(i.service))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.service.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  Text('Qty: ${i.quantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_rupees(i.totalPrice.toDouble()), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                if (i.quantity > 1) Text('${_rupees(i.unitPrice.toDouble())} each', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ]),
            ]),
          ),
        const Divider(height: 22),
        _BillLine('Items total ($count item${count == 1 ? '' : 's'})', _rupees(itemsTotal.toDouble())),
        if (other > Decimal.zero && feeLines != null)
          for (final f in feeLines!) _BillLine(f.label, _rupees(f.amount.toDouble()))
        else if (other > Decimal.zero)
          _BillLine('Delivery, handling fees & taxes', _rupees(other.toDouble())),
        if (other < Decimal.zero) _BillLine('Discount applied', '-${_rupees((-other).toDouble())}', color: _green),
        const Divider(height: 18),
        _BillLine('Order total', _rupees(booking.totalAmount.toDouble()), bold: true),
      ]),
    );
  }
}

class _BillLine extends StatelessWidget {
  const _BillLine(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: bold ? 14.5 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? AppColors.navy : AppColors.textSecondary))),
          Text(value, style: TextStyle(fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: color ?? AppColors.navy)),
        ]),
      );
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final a = booking.address;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.location_on_outlined, size: 18, color: AppColors.navy),
          SizedBox(width: 6),
          Flexible(child: Text('Delivery Address', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
        ]),
        const SizedBox(height: 10),
        Text(a == null ? 'Not available' : a.formattedAddress, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final cod = (booking.paymentMethod ?? '').toUpperCase().contains('COD') || (booking.paymentMethod ?? '').toUpperCase().contains('CASH');
    final paid = booking.paymentStatus.toLowerCase() == 'paid';
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.payments_outlined, size: 18, color: AppColors.navy),
          SizedBox(width: 6),
          Flexible(child: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
        ]),
        const SizedBox(height: 10),
        Text(cod ? 'Cash on Delivery' : 'Online payment', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        Text(paid ? 'Paid' : 'Payment pending', style: TextStyle(fontSize: 12, color: paid ? _green : const Color(0xFFB45309))),
        const SizedBox(height: 6),
        Text('Total: ${_rupees(booking.totalAmount.toDouble())}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.onHelp, this.onCancel});
  final VoidCallback onHelp;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(children: [
          const Text('Need help with your order?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 4),
          const Text('Our support team is here to help you with any questions.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
            OutlinedButton(onPressed: onHelp, style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), child: const Text('Contact support')),
            if (onCancel != null)
              OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFFFCDD2))),
                child: const Text('Cancel order'),
              ),
          ]),
        ]),
      );
}
