import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/domain/catalog_models.dart';

/// "Book again" for a past service: opens that service's page, ready to book. The page fetches the CURRENT price and
/// slots itself; only a service that no longer has a page in the catalog falls back to the old snapshot.
/// A Goods & Transport booking goes to the transport booking page of the same kind.
void openServiceAgain(BuildContext context, ServiceItem service) {
  if (service.isGoodsTransport) {
    context.push(service.goodsTransportPath);
    return;
  }
  final hasSlug = service.slug.isNotEmpty;
  context.push('/services/${hasSlug ? service.slug : 'svc-${service.id}'}', extra: hasSlug ? null : service);
}

/// The compact outlined pill used for "Book again" / "Order again" on the Bookings & Orders cards.
class AgainButton extends StatelessWidget {
  const AgainButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.replay_rounded, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0B2337),
          side: const BorderSide(color: Color(0xFFD5DCE8)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(0, 34),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
}
