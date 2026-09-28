import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/catalog_models.dart';

/// Amazon/Flipkart-style product tile: the image dominates the top of the
/// card, with a compact name/price/rating block underneath. Used for
/// Home's horizontal "Essential Picks" / "Recommended Services" strips and
/// for the grocery category's 2-column grid — everywhere a denser,
/// image-forward tile fits better than the full-detail [ServiceCard] used
/// in the scheduled-service list view.
///
/// Deliberately sized with no forced/tight height anywhere in its own
/// layout (mainAxisSize.min throughout, no Expanded) so it never overflows
/// regardless of how it's hosted by the caller — the caller only needs to
/// give it a width.
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.service, this.onTap});

  final ServiceItem service;
  final VoidCallback? onTap;

  // Fixed 2026-08-27: guards against a ServiceItem whose slug came back
  // empty (e.g. one built from a booking's own echoed item JSON, which
  // often omits slug entirely, unlike the full catalog payload) — pushing
  // '/services/' with nothing after it doesn't match the '/services/:slug'
  // route and falls through to go_router's "Page Not Found" screen.
  // ServiceDetailScreen renders straight from the ServiceItem passed as
  // `extra` when one is provided, so the URL segment itself just needs to
  // be non-empty for the route to match at all.
  String get _safeSlug =>
      service.slug.isNotEmpty ? service.slug : 'svc-${service.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGrocery = service.flowType == CatalogFlowType.grocery;
    final cartItems = ref.watch(cartProvider);
    final inCartItem =
        cartItems.where((i) => i.service.id == service.id).firstOrNull;
    final quantityInCart = inCartItem?.quantity ?? 0;
    final accent = isGrocery ? AppColors.groceryGreen : AppColors.serviceBlue;

    if (isGrocery) {
      return _buildGroceryCard(context, ref, quantityInCart, accent);
    }

    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: AppColors.surfaceVariant,
                  child: AppRemoteImage(
                    imageUrl: service.imageUrl,
                    rawPath: service.imageUrl,
                    title: service.title,
                    categoryName: service.categoryName,
                    slug: service.slug,
                    semanticIcon: ImageUrlHelper.mapCategoryIcon(
                        service.categoryName, service.slug),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (!service.inStock)
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 12, color: AppColors.star),
                    const SizedBox(width: 2),
                    Text(
                      service.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '₹${service.effectivePrice}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    if (service.hasDiscount) ...[
                      const SizedBox(width: 4),
                      Text(
                        '₹${service.price}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textHint,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap ?? () => context.push('/services/$_safeSlug', extra: service),
      child: card,
    );
  }

  Widget _buildGroceryCard(
    BuildContext context,
    WidgetRef ref,
    int quantityInCart,
    Color accent,
  ) {
    final recipeCount = (service.title.hashCode.abs() % 25) + 6;
    // Fixed 2026-09-28 per explicit request ("for every products in
    // groceries, vegetables and fruits if user clicks open the product
    // page... as like amazon and flipkart") and then corrected the same day
    // per explicit feedback with a reference screenshot ("you have added
    // the service listing which is 'What's included','how it works' instead
    // ... makeseperate page as like the uploaded image"): this grocery-
    // styled branch now pushes to GroceryProductDetailScreen
    // (`/products/:slug`), a dedicated page with NO service-only sections
    // (no "What's Included" / "How It Works") — NOT ServiceDetailScreen,
    // which is correct only for scheduled services (see the non-grocery
    // branch above, which still pushes to `/services/:slug`). The ADD /
    // quantity-stepper buttons inside this card have their own InkWell and
    // consume their own taps first, so wrapping the whole card doesn't
    // interfere with them.
    return GestureDetector(
      onTap: onTap ?? () => context.push('/products/$_safeSlug', extra: service),
      child: _groceryCardBody(quantityInCart, accent, recipeCount, context, ref),
    );
  }

  Widget _groceryCardBody(
    int quantityInCart,
    Color accent,
    int recipeCount,
    BuildContext context,
    WidgetRef ref,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Produce Image
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFFF8FAFC),
                  child: AppRemoteImage(
                    imageUrl: service.imageUrl,
                    rawPath: service.imageUrl,
                    title: service.title,
                    categoryName: service.categoryName,
                    slug: service.slug,
                    semanticIcon: ImageUrlHelper.mapCategoryIcon(
                        service.categoryName, service.slug),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (!service.inStock)
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Weight Unit (left) + ADD action (right)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          service.displayUnit.isNotEmpty ? service.displayUnit : '1 unit',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildGroceryAction(context, ref, quantityInCart, accent),
                  ],
                ),
                const SizedBox(height: 3),
                // Price row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '₹${service.effectivePrice}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (service.hasDiscount) ...[
                      const SizedBox(width: 4),
                      Text(
                        '₹${service.price}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF94A3B8),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // Title
                Text(
                  service.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                // Delivery ETA & Stock
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 11, color: Color(0xFF64748B)),
                    const SizedBox(width: 3),
                    const Text(
                      '22 mins',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (service.maxQuantity <= 5 && service.inStock) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.inventory_2_outlined, size: 10, color: Color(0xFF64748B)),
                      const SizedBox(width: 2),
                      Text(
                        '${service.maxQuantity} left',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                // Recipe badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$recipeCount recipes',
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15803D),
                        ),
                      ),
                      const SizedBox(width: 1),
                      const Icon(
                        Icons.arrow_right_rounded,
                        size: 13,
                        color: Color(0xFF15803D),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroceryAction(
    BuildContext context,
    WidgetRef ref,
    int quantityInCart,
    Color accent,
  ) {
    if (!service.inStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Text(
          'OUT',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textHint,
          ),
        ),
      );
    }

    if (quantityInCart == 0) {
      return InkWell(
        onTap: () {
          ref.read(cartProvider.notifier).addService(service);
          AppToast.addedToCart(context, service.title);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF16A34A), width: 1.2),
          ),
          child: const Text(
            'ADD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF16A34A),
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    final atMax = quantityInCart >= service.maxQuantity;
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => ref
                .read(cartProvider.notifier)
                .updateQuantity(service.id, quantityInCart - 1),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Icon(Icons.remove, size: 12, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '$quantityInCart',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
          InkWell(
            onTap: atMax
                ? () => AppToast.show(
                      context,
                      'Only ${service.maxQuantity} in stock',
                      type: AppToastType.error,
                    )
                : () {
                    ref
                        .read(cartProvider.notifier)
                        .updateQuantity(service.id, quantityInCart + 1);
                    AppToast.addedToCart(context, service.title);
                  },
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Icon(
                Icons.add,
                size: 12,
                color: atMax ? Colors.white54 : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

