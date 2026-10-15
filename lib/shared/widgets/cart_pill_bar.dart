import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Dark-green "Go to Cart" pill used by every grocery cart bar / page.
class GoToCartPill extends StatelessWidget {
  const GoToCartPill({super.key, this.expand = false, this.push = false});

  /// Push /cart on top of the current page instead of switching to it.
  final bool push;

  /// Stretch to the full available width (product detail page) instead of
  /// hugging its label (cart bars).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C7A41), Color(0xFF0F5A2B)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 20, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'Go to Cart',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => push ? context.push('/cart') : context.go('/cart'),
      child: expand ? SizedBox(width: double.infinity, child: pill) : pill,
    );
  }
}

/// Floating rounded cart summary bar: "4 items · ₹460" + [GoToCartPill].
class CartPillBar extends StatelessWidget {
  const CartPillBar({super.key, required this.itemCount, required this.subtotal});

  final int itemCount;
  final String subtotal;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEFA),
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$itemCount ${itemCount == 1 ? "item" : "items"}  •  ₹$subtotal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const GoToCartPill(),
            ],
          ),
        ),
      ),
    );
  }
}
