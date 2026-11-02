import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/errors/error_manager.dart';
import '../../../core/navigation/safe_back.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/grocery_theme.dart';
import '../../../shared/utils/app_toast.dart';
import '../../../shared/utils/date_utils.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../data/grocery_orders_repository.dart';
import '../data/order_returns_repository.dart';

const _green = Color(0xFF1B7F4B);

String _rupees(double v) => '₹${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

Color _stageColor(ReturnStage s) => switch (s) {
      ReturnStage.refunded => _green,
      ReturnStage.rejected || ReturnStage.cancelled => const Color(0xFFC62828),
      _ => const Color(0xFFE65100),
    };

/// On the order page: the returns already filed (with where each one stands) and, for a delivered order still inside
/// the return window, the "Return items" button.
class OrderReturnsCard extends ConsumerWidget {
  const OrderReturnsCard({super.key, required this.order});
  final GroceryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(orderReturnsProvider(order.orderNumber)).valueOrNull ?? const <ReturnRequest>[];
    if (returns.isEmpty && !order.canReturn) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Returns & refunds', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.navy)),
        const SizedBox(height: 10),
        for (final r in returns) _ReturnRow(r),
        if (order.canReturn) ...[
          if (returns.isNotEmpty) const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () async {
                await context.push('/grocery-orders/${order.orderNumber}/return');
                ref.invalidate(orderReturnsProvider(order.orderNumber));
              },
              icon: const Icon(Icons.assignment_return_outlined, size: 18),
              label: const Text('Return items'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Returns are accepted within 7 days of delivery.', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ),
        ],
      ]),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow(this.r);
  final ReturnRequest r;

  @override
  Widget build(BuildContext context) {
    final c = _stageColor(r.stage);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF6F8FA), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Return #${r.returnNumber}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(r.statusLabel.isEmpty ? r.stage.name : r.statusLabel, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 4),
        Text([r.reasonLabel, if (r.refundAmount > 0) _rupees(r.refundAmount)].where((s) => s.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        if (r.refundNote.isNotEmpty) Text(r.refundNote, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.refundStatus.toUpperCase() == 'REFUNDED' ? _green : const Color(0xFFB45309))),
        if (r.stage == ReturnStage.rejected && r.rejectionReason.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Reason: ${r.rejectionReason}', style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)))),
        if (r.createdAt != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Requested ${formatDmyTime(r.createdAt!)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
      ]),
    );
  }
}

/// Pick the items (and how many) to return, say why, and send the request.
class ReturnRequestScreen extends ConsumerStatefulWidget {
  const ReturnRequestScreen({super.key, required this.orderNumber});
  final String orderNumber;

  @override
  ConsumerState<ReturnRequestScreen> createState() => _ReturnRequestScreenState();
}

class _ReturnRequestScreenState extends ConsumerState<ReturnRequestScreen> {
  final Map<int, int> _qty = {}; // order item id -> quantity to return (absent/0 = not returning)
  ReturnReason _reason = ReturnReason.damaged;
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(GroceryOrder o) async {
    final picked = [for (final i in o.items) if (i.id != null && (_qty[i.id] ?? 0) > 0) i];
    if (picked.isEmpty) {
      AppToast.show(context, 'Please select at least one item to return.', type: AppToastType.error);
      return;
    }
    // One request covers one seller: an order with several sellers needs the seller line the items belong to.
    final sellers = {for (final i in picked) i.sellerId};
    int? sellerLineId;
    if (o.sellerLines.length > 1) {
      if (sellers.length > 1) {
        AppToast.show(context, 'Items from different sellers need separate returns. Please select items from one seller at a time.', type: AppToastType.error);
        return;
      }
      sellerLineId = o.sellerLines.where((l) => l.sellerId == sellers.first).firstOrNull?.id;
    }
    setState(() => _busy = true);
    final r = await ref.read(orderReturnsRepositoryProvider).create(
          o.orderNumber,
          lines: [for (final i in picked) ReturnLine(i.id!, _qty[i.id]!)],
          reason: _reason,
          notes: _notes.text,
          sellerLineId: sellerLineId,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Success(:final data):
        AppToast.show(context, 'Return #${data.returnNumber} submitted.', type: AppToastType.success);
        ref.invalidate(orderReturnsProvider(o.orderNumber));
        ref.invalidate(groceryOrderProvider(o.orderNumber));
        // Normally pushed from the order page; if opened directly (deep link) go to the order instead.
        context.canPop() ? context.pop() : context.go('/grocery-orders/${o.orderNumber}');
      case Failure(:final error):
        AppToast.show(context, ErrorManager.present(error).body, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groceryOrderProvider(widget.orderNumber));
    return GroceryTheme(
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FA),
        appBar: AppBar(
          title: const Text('Return items', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
          leading: BackButton(onPressed: context.goBack),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: async.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(groceryOrderProvider(widget.orderNumber))),
          data: (o) {
            final refund = [for (final i in o.items) if (i.id != null) i.unitPrice * (_qty[i.id] ?? 0)].fold<double>(0, (a, b) => a + b);
            return Column(children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Order #${o.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text('Choose what you want to return.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  for (final i in o.items) if (i.id != null) _ItemPicker(line: i, qty: _qty[i.id] ?? 0, onChanged: (q) => setState(() => _qty[i.id!] = q)),
                  const SizedBox(height: 12),
                  const Text('Reason', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final r in ReturnReason.values)
                      ChoiceChip(label: Text(r.label), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Anything else we should know? (optional)', border: OutlineInputBorder()),
                  ),
                ]),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        const Text('Estimated refund', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        Text(_rupees(refund), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.navy)),
                      ]),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 22)),
                      onPressed: _busy ? null : () => _submit(o),
                      child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit return'),
                    ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _ItemPicker extends StatelessWidget {
  const _ItemPicker({required this.line, required this.qty, required this.onChanged});
  final OrderLine line;
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? _green : const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        Checkbox(value: selected, onChanged: (v) => onChanged(v == true ? 1 : 0)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Text('${_rupees(line.unitPrice)} each · ordered ${line.quantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ]),
        ),
        if (selected)
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => onChanged(qty - 1)),
            Text('$qty', style: const TextStyle(fontWeight: FontWeight.w800)),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: qty < line.quantity ? () => onChanged(qty + 1) : null),
          ]),
      ]),
    );
  }
}
