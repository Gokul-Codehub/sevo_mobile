import '../domain/reorder.dart';
import '../../../core/refresh/refresh_runner.dart';
import '../../booking/presentation/widgets/book_again_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/errors/error_manager.dart';
import '../../../core/navigation/safe_back.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/grocery_theme.dart';
import '../../../shared/utils/app_toast.dart';
import '../../../shared/utils/date_utils.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../data/grocery_orders_repository.dart';
import 'order_invoices_card.dart';
import 'order_returns.dart';

const _green = Color(0xFF1B7F4B);
const _greenSoft = Color(0xFFE8F6EE);
const _page = Color(0xFFF6F8FA);

String _rupees(double v) => '₹${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

AppBar _bar(BuildContext context, String title) => AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
      leading: BackButton(onPressed: context.goBack),
      backgroundColor: Colors.white,
      foregroundColor: AppColors.navy,
      elevation: 0,
    );

Color _stageColor(OrderStage s) => switch (s) {
      OrderStage.delivered => _green,
      OrderStage.cancelled => const Color(0xFFC62828),
      OrderStage.outForDelivery => const Color(0xFFE65100),
      _ => AppColors.navy,
    };

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.stage);
  final OrderStage stage;

  @override
  Widget build(BuildContext context) {
    final c = _stageColor(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (stage == OrderStage.outForDelivery) ...[Icon(Icons.circle, size: 8, color: c), const SizedBox(width: 5)],
        Text(stageTitle(stage), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}

// ───────────────────────────────── Orders list ─────────────────────────────────

/// Pull-to-refresh for the orders list: waits for the new list (never longer than the shared limit).
Future<void> _reloadOrders(BuildContext context, WidgetRef ref) {
  ref.invalidate(groceryOrdersProvider);
  return RefreshRunner.run(context, [() => ref.read(groceryOrdersProvider.future)]);
}

/// Profile -> My grocery orders. Active / Delivered / Cancelled, each order with a live progress bar.
class GroceryOrdersScreen extends ConsumerWidget {
  const GroceryOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(groceryOrdersProvider);
    return GroceryTheme(
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: _page,
          appBar: AppBar(
            title: const Text('My Orders', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
            leading: BackButton(onPressed: context.goBack),
            backgroundColor: Colors.white,
            elevation: 0,
            bottom: const TabBar(
              labelColor: AppColors.navy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.navy,
              labelStyle: TextStyle(fontWeight: FontWeight.w800),
              tabs: [Tab(text: 'Active'), Tab(text: 'Delivered'), Tab(text: 'Cancelled')],
            ),
          ),
          body: orders.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingState(),
            error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(groceryOrdersProvider)),
            data: (all) => TabBarView(children: [
              _OrderList(orders: all.where((o) => o.isActive).toList(), empty: 'No active orders', onRefresh: () => _reloadOrders(context, ref)),
              _OrderList(orders: all.where((o) => o.stage == OrderStage.delivered).toList(), empty: 'No delivered orders yet', onRefresh: () => _reloadOrders(context, ref)),
              _OrderList(orders: all.where((o) => o.stage == OrderStage.cancelled).toList(), empty: 'No cancelled orders', onRefresh: () => _reloadOrders(context, ref)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders, required this.empty, required this.onRefresh});
  final List<GroceryOrder> orders;
  final String empty;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(children: [
          const SizedBox(height: 80),
          EmptyState(icon: Icons.shopping_bag_outlined, title: empty, body: 'Your grocery orders will show up here.'),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => OrderCard(order: orders[i]),
      ),
    );
  }
}

class OrderCard extends ConsumerStatefulWidget {
  const OrderCard({super.key, required this.order});
  final GroceryOrder order;

  @override
  ConsumerState<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<OrderCard> {
  bool _reordering = false;

  /// Adds what can still be bought to the cart at today's price and stock, then opens the cart.
  Future<void> _orderAgain() async {
    setState(() => _reordering = true);
    final plan = await reorderGroceryOrder(ref, widget.order);
    if (!mounted) return;
    setState(() => _reordering = false);
    final text = plan == null ? "We couldn't check today's prices. Please try again." : reorderMessage(plan);
    AppToast.show(context, text, type: (plan == null || plan.isEmpty) ? AppToastType.error : AppToastType.success);
    if (plan != null && !plan.isEmpty) context.openTab('/cart');
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final o = order;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/grocery-orders/${o.orderNumber}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${o.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.navy)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFEFF2F6), borderRadius: BorderRadius.circular(6)),
              child: const Text('GROCERY', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
            const Spacer(),
            _StatusChip(o.stage),
          ]),
          const SizedBox(height: 10),
          if (o.items.isNotEmpty) ...[
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: o.items.first.image == null
                      ? Container(color: const Color(0xFFF1F5F9), child: const Icon(Icons.shopping_basket_outlined, size: 20, color: AppColors.textSecondary))
                      : Image.network(o.items.first.image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F5F9))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  o.items.length > 1 ? '${o.items.first.title} +${o.items.length - 1} more' : o.items.first.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navy),
                ),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          if (o.stage != OrderStage.cancelled) ...[
            Text(
              o.stage == OrderStage.delivered
                  ? 'Delivered'
                  : (o.slot.isNotEmpty ? 'Delivery slot: ${o.slot}' : 'Estimated delivery will be shared soon'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            StageProgressBar(stage: o.stage, compact: true),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Seller', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text(o.sellerName.isEmpty ? 'SEVO Partner' : o.sellerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Order total', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text(_rupees(o.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.navy)),
            ]),
          ]),
          if (o.createdAt != null) ...[
            const SizedBox(height: 8),
            Text('Placed ${formatDmyTime(o.createdAt!)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
          if ((o.stage == OrderStage.delivered || o.stage == OrderStage.cancelled) && o.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: AgainButton(label: 'Order again', busy: _reordering, onPressed: _orderAgain)),
          ],
        ]),
      ),
    );
  }
}

/// The segmented bar from the shipments reference: one segment per step, filled up to the current one.
class StageProgressBar extends StatelessWidget {
  const StageProgressBar({super.key, required this.stage, this.compact = false});
  final OrderStage stage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final current = stage == OrderStage.cancelled ? -1 : stage.index;
    return Column(children: [
      Row(children: [
        for (var i = 0; i < kOrderStages.length; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= current ? _stageColor(stage == OrderStage.delivered ? OrderStage.delivered : OrderStage.confirmed) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (i != kOrderStages.length - 1) const SizedBox(width: 4),
        ],
      ]),
      if (!compact) ...[
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < kOrderStages.length; i++)
            Expanded(
              child: Text(
                ['Confirmed', 'Packing', 'Ready', 'On the way', 'Delivered'][i],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, fontWeight: i == current ? FontWeight.w800 : FontWeight.w500, color: i <= current ? AppColors.navy : AppColors.textSecondary),
              ),
            ),
        ]),
      ],
    ]);
  }
}

// ───────────────────────────────── Order detail ─────────────────────────────────

class GroceryOrderDetailScreen extends ConsumerStatefulWidget {
  const GroceryOrderDetailScreen({super.key, required this.orderNumber});
  final String orderNumber;

  @override
  ConsumerState<GroceryOrderDetailScreen> createState() => _GroceryOrderDetailScreenState();
}

class _GroceryOrderDetailScreenState extends ConsumerState<GroceryOrderDetailScreen> {
  Timer? _poll;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    // Statuses move on their own (seller packs, rider picks up), so keep the page fresh while the order is active.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      final o = ref.read(groceryOrderProvider(widget.orderNumber)).valueOrNull;
      if (mounted && (o == null || o.isActive)) ref.invalidate(groceryOrderProvider(widget.orderNumber));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _cancel(GroceryOrder o) async {
    const reasons = [
      'Ordered by mistake',
      'Want to change items or address',
      'Found a better price elsewhere',
      'Delivery is taking too long',
      'Other',
    ];
    String picked = reasons.first;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Cancel this order?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The seller will stop preparing it. If you already paid, the amount is refunded.'),
              const SizedBox(height: 10),
              const Text('Why are you cancelling?', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final r in reasons)
                InkWell(
                  onTap: () => setLocal(() => picked = r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Icon(picked == r ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 20, color: picked == r ? const Color(0xFFC62828) : Colors.black45),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r)),
                    ]),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Keep order')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
              onPressed: () => Navigator.of(ctx).pop(picked),
              child: const Text('Cancel order'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _cancelling = true);
    final r = await ref.read(groceryOrdersRepositoryProvider).cancel(o.orderNumber, reason: reason);
    if (!mounted) return;
    setState(() => _cancelling = false);
    switch (r) {
      case Success():
        AppToast.show(context, 'Order cancelled.', type: AppToastType.success);
        ref.invalidate(groceryOrderProvider(o.orderNumber));
        ref.invalidate(groceryOrdersProvider);
      case Failure(:final error):
        AppToast.show(context, ErrorManager.present(error).body, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groceryOrderProvider(widget.orderNumber));
    return GroceryTheme(
      child: Scaffold(
        backgroundColor: _page,
        appBar: _bar(context, 'Order #${widget.orderNumber}'),
        body: async.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(groceryOrderProvider(widget.orderNumber))),
          data: (o) => Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () {
                  ref.invalidate(groceryOrderProvider(widget.orderNumber));
                  return RefreshRunner.run(context, [() => ref.read(groceryOrderProvider(widget.orderNumber).future)]);
                },
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                  _Header(order: o),
                  const SizedBox(height: 12),
                  if (o.showOtp) _OtpCard(otp: o.deliveryOtp!),
                  if (o.stage == OrderStage.outForDelivery) _RiderCard(order: o),
                  if (o.stage != OrderStage.cancelled) _ProgressCard(order: o) else _CancelledCard(order: o),
                  if (o.sellerLines.length > 1) _SellerLinesCard(lines: o.sellerLines),
                  if (o.events.isNotEmpty) _ActivityCard(events: o.events),
                  _ItemsCard(order: o),
                  if (o.stage == OrderStage.delivered) OrderInvoicesCard(orderNumber: o.orderNumber),
                  OrderReturnsCard(order: o),
                  _InfoCard(icon: Icons.location_on_outlined, title: 'Delivery address', body: o.deliveryAddress.isEmpty ? 'Not available' : o.deliveryAddress),
                  _PaymentCard(order: o),
                  _HelpCard(),
                ]),
              ),
            ),
            if (o.canCancel)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFFFCDD2)), padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _cancelling ? null : () => _cancel(o),
                      child: _cancelling ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Cancel order'),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.sub});
  final String text;
  final String? sub;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.navy)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        ]),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.order});
  final GroceryOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return _Card(
      margin: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          _StatusChip(o.stage),
          if (o.paymentStatus.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
              child: Text('Payment: ${o.paymentStatus}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
        ]),
        const SizedBox(height: 10),
        Text('Order #${o.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.navy)),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 2, children: [
          if (o.sellerName.isNotEmpty) _Meta('Seller', o.sellerName),
          if (o.warehouseName.isNotEmpty) _Meta('Warehouse', o.warehouseName),
          if (o.slot.isNotEmpty) _Meta('Slot', o.slot),
        ]),
        if (o.createdAt != null) ...[
          const SizedBox(height: 6),
          Text('Placed ${formatDmyTime(o.createdAt!)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.k, this.v);
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: AppColors.textSecondary)),
          TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
        ]),
        style: const TextStyle(fontSize: 12.5),
      );
}

class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.otp});
  final String otp;

  @override
  Widget build(BuildContext context) => _Card(
        child: Row(children: [
          const Icon(Icons.verified_user_outlined, color: _green),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Share this code with the delivery partner when you receive your order.', style: TextStyle(fontSize: 12.5, height: 1.35)),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(otp, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 3, color: _green)),
          ),
        ]),
      );
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.order});
  final GroceryOrder order;

  @override
  Widget build(BuildContext context) {
    final r = order.rider;
    final eta = r?.etaMinutes;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(radius: 20, backgroundColor: _greenSoft, child: Icon(Icons.delivery_dining_rounded, color: _green)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r?.name ?? 'Delivery Partner', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(
                eta != null ? 'Arriving in about $eta min' : ((r?.live ?? false) ? 'On the way to you' : 'Waiting for the rider location'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ]),
          ),
          if ((r?.phone ?? '').isNotEmpty)
            IconButton.filledTonal(
              tooltip: 'Call delivery partner',
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: r!.phone)),
              icon: const Icon(Icons.call_rounded),
            ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
            onPressed: () => context.push('/track/${order.orderNumber}'),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Track live on map'),
          ),
        ),
      ]),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.order});
  final GroceryOrder order;

  @override
  Widget build(BuildContext context) {
    final current = order.stage.index;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle('Delivery progress', sub: order.slot.isEmpty ? null : 'Delivery slot: ${order.slot}'),
        for (var i = 0; i < kOrderStages.length; i++)
          _TimelineRow(info: kOrderStages[i], index: i, done: i < current || order.stage == OrderStage.delivered, current: i == current && order.stage != OrderStage.delivered, last: i == kOrderStages.length - 1),
      ]),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.info, required this.index, required this.done, required this.current, required this.last});
  final StageInfo info;
  final int index;
  final bool done;
  final bool current;
  final bool last;

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
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: reached ? _green : const Color(0xFFF1F5F9)),
              child: Icon(done ? Icons.check_rounded : info.icon, size: 17, color: reached ? Colors.white : AppColors.textSecondary),
            ),
            if (!last) Expanded(child: Container(width: 2, color: done ? _green : const Color(0xFFE2E8F0))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 18, top: 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(info.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: reached ? _green : AppColors.textSecondary)),
              Text(info.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CancelledCard extends StatelessWidget {
  const _CancelledCard({required this.order});
  final GroceryOrder order;

  @override
  Widget build(BuildContext context) => _Card(
        child: Row(children: [
          const Icon(Icons.cancel_outlined, color: Color(0xFFC62828)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('This order was cancelled. Any amount paid is refunded to the original payment method.', style: TextStyle(fontSize: 13, height: 1.35)),
          ),
        ]),
      );
}

class _SellerLinesCard extends StatelessWidget {
  const _SellerLinesCard({required this.lines});
  final List<SellerLine> lines;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionTitle('Shipments in this order'),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text(l.sellerName.isEmpty ? 'SEVO Partner' : l.sellerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                _StatusChip(l.stage),
              ]),
            ),
        ]),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.events});
  final List<OrderEvent> events;

  @override
  Widget build(BuildContext context) {
    final sorted = [...events]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionTitle('Activity updates'),
        for (final e in sorted)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFF6F8FA), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(child: Text(e.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              if (e.at != null) Text(formatDmyTime(e.at!), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ),
      ]),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});
  final GroceryOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle('Items in this order (${o.items.length})'),
        for (final i in o.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: i.image == null
                      ? Container(color: const Color(0xFFF1F5F9), child: const Icon(Icons.shopping_basket_outlined, size: 20, color: AppColors.textSecondary))
                      : Image.network(i.image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F5F9))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  Text('${i.pack.isEmpty ? '' : '${i.pack} · '}Qty ${i.quantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ]),
              ),
              Text(_rupees(i.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            ]),
          ),
        if (o.subtotal != null || o.deliveryFee != null) ...[
          const Divider(height: 22),
          if (o.subtotal != null) _AmountRow('Items subtotal', _rupees(o.subtotal!)),
          if (o.deliveryFee != null) _AmountRow('Delivery fee', o.deliveryFee == 0 ? 'Free' : _rupees(o.deliveryFee!)),
        ],
        const Divider(height: 22),
        _AmountRow(o.isCod && o.paymentStatus.toUpperCase() != 'PAID' ? 'Amount to pay on delivery' : 'Order total', _rupees(o.total), bold: true),
      ]),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: bold ? 14.5 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? AppColors.navy : AppColors.textSecondary))),
          Text(value, style: TextStyle(fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: AppColors.navy)),
        ]),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => _Card(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AppColors.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
      );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order});
  final GroceryOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final method = o.isCod ? 'Cash on Delivery' : (o.paymentMethod.isEmpty ? 'Online payment' : o.paymentMethod);
    return _InfoCard(
      icon: Icons.payments_outlined,
      title: 'Payment method',
      body: '$method${o.paymentStatus.isEmpty ? '' : ' (${o.paymentStatus})'}',
    );
  }
}

class _HelpCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _Card(
        child: Column(children: [
          const Text('Need help with your order?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 4),
          const Text('Our support team is here to help.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => context.push('/support'), child: const Text('Contact support')),
        ]),
      );
}
