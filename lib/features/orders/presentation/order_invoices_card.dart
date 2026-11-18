import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/api_error.dart';
import '../../../shared/theme/app_colors.dart';
import '../../booking/presentation/screens/pdf_viewer_screen.dart';
import '../data/grocery_orders_repository.dart';
import '../../../shared/utils/app_toast.dart';

/// Download buttons for an order's invoices (one tax invoice per seller, plus any credit note). Shown only when the
/// server has issued something, which for a normal order means after delivery.
class OrderInvoicesCard extends ConsumerStatefulWidget {
  const OrderInvoicesCard({super.key, required this.orderNumber, this.saveAndShare});
  final String orderNumber;

  /// Test seam: what to do with the downloaded PDF (default: write a temp file and open the share sheet).
  final Future<void> Function(List<int> bytes, String fileName)? saveAndShare;

  @override
  ConsumerState<OrderInvoicesCard> createState() => _OrderInvoicesCardState();
}

class _OrderInvoicesCardState extends ConsumerState<OrderInvoicesCard> {
  String? _busy; // invoice number being downloaded

  Future<void> _download(OrderInvoice inv) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = inv.number);
    final result = await ref.read(groceryOrdersRepositoryProvider).invoicePdf(widget.orderNumber, inv.sellerId);
    if (!mounted) return;
    setState(() => _busy = null);
    switch (result) {
      case Success(:final data):
        try {
          final fileName = '${inv.isCreditNote ? 'CreditNote' : 'Invoice'}-${inv.number}.pdf'.replaceAll('/', '-');
          if (widget.saveAndShare != null) {
            await widget.saveAndShare!(data, fileName);
          } else {
            // Open it on screen in the app's own PDF viewer (Share / Save stay in its app bar) instead of
            // depending on the Android share sheet, which failed on some phones.
            final dir = await getTemporaryDirectory();
            final file = File('${dir.path}/$fileName');
            await file.writeAsBytes(data, flush: true);
            if (!mounted) return;
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PdfViewerScreen(
                filePath: file.path,
                title: '${inv.isCreditNote ? 'Credit note' : 'Tax invoice'} ${inv.number}',
                shareSubject: fileName,
              ),
            ));
          }
        } catch (_) {
          AppToast.show(messenger.context, 'Could not open the invoice. Please try again.', type: AppToastType.error);
        }
      case Failure(:final error):
        AppToast.show(messenger.context, error.message, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(groceryInvoicesProvider(widget.orderNumber)).valueOrNull ?? const <OrderInvoice>[];
    if (invoices.isEmpty) return const SizedBox.shrink();
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
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Invoices', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.navy)),
        ),
        for (final inv in invoices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(inv.isCreditNote ? Icons.assignment_return_outlined : Icons.receipt_long_outlined, size: 20, color: AppColors.navy),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${inv.isCreditNote ? 'Credit note' : 'Tax invoice'} ${inv.number}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
              OutlinedButton.icon(
                onPressed: _busy == null ? () => _download(inv) : null,
                icon: _busy == inv.number
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded, size: 16),
                label: const Text('PDF'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), visualDensity: VisualDensity.compact),
              ),
            ]),
          ),
      ]),
    );
  }
}
