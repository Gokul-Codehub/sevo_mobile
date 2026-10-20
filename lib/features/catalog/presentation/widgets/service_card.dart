import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/image_url_helper.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/catalog_models.dart';

/// Screen 8: Service Card Widget
/// Matches reference screen 8 with rounded image thumbnail, navy typography, rating badge,
/// price display, and green CTA button.
class ServiceCard extends ConsumerWidget {
  const ServiceCard({
    super.key,
    required this.service,
    this.onTap,
  });

  final ServiceItem service;
  final VoidCallback? onTap;

  Widget _buildImageOrIcon(
    ServiceItem service, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    return AppRemoteImage(
      imageUrl: service.imageUrl,
      rawPath: service.imageUrl,
      title: service.title,
      categoryName: service.categoryName,
      slug: service.slug,
      semanticIcon: ImageUrlHelper.mapCategoryIcon(
          service.categoryName, service.slug),
      width: width,
      height: height,
      fit: fit,
    );
  }

  /// Routes a tap on this card to the right screen for its flow.
  ///
  /// Added 2026-09-19: Goods & Transport items were previously routed here
  /// exactly like any scheduled service (`/services/:slug`), which lands on
  /// the generic package-detail/checkout screen — that screen has no
  /// drop-address field or vehicle-tier picker, so the backend's
  /// `ServiceRequestPublicCreateSerializer` rejects the booking with a 400
  /// (no tier/lane to resolve a fare from). Logistics items now go to the
  /// dedicated `GoodsTransportBookingScreen` instead. This is the single
  /// place all three of this card's tap targets funnel through, so a future
  /// flow type only needs to be added here once.
  ///
  /// Fixed 2026-09-28 per explicit report ("Search bar does not return
  /// correct pages of what user asks"): this card is what Search's result
  /// list renders for every hit regardless of flow type, but grocery/
  /// vegetable items were still falling through to `/services/:slug` (the
  /// scheduled-service detail/checkout screen) — the same screen that was
  /// already known to be wrong for logistics items above, for the same
  /// underlying reason: it isn't the grocery product screen. Groceries now
  /// route to `/products/:slug` (GroceryProductDetailScreen), matching
  /// exactly what ProductCard already does elsewhere in the app.
  void _navigateToDetail(BuildContext context) {
    if (service.flowType == CatalogFlowType.logistics) {
      // Updated 2026-09-20: individual Goods & Transport packages (e.g.
      // "Mini Truck", "2-Wheeler") are no longer bookable as standalone
      // catalog items — the consolidated GoodsTransportBookingScreen now
      // owns vehicle-category + tier selection itself, so no ServiceItem
      // extra is needed (or valid) here anymore. In normal use this branch
      // is pre-empted by CategoryDetailScreen's own redirect before a
      // service card for this flow type is ever shown, but it is kept
      // defensive (e.g. for stale search results) rather than removed.
      context.push(AppRoutes.goodsTransportBooking);
      return;
    }
    if (service.flowType == CatalogFlowType.grocery) {
      context.push('/products/${service.slug}', extra: service);
      return;
    }
    context.push('/services/${service.slug}', extra: service);
  }

  void _handleAddToCart(BuildContext context, WidgetRef ref) {
    final cartBefore = ref.read(cartProvider);
    AppLogger.d('[P0-CATALOG]', 'categoryId=${service.categoryId}');
    AppLogger.d('[P0-CART]', 'cartBeforeAdd=${cartBefore.length}');
    ref.read(cartProvider.notifier).addService(service);
    final cartAfter = ref.read(cartProvider);
    AppLogger.d('[P0-CART]', 'cartAfterAdd=${cartAfter.length}');

    AppToast.addedToCart(context, service.title);
  }

  void _handleBuyNow(BuildContext context, WidgetRef ref, int quantityInCart) {
    if (quantityInCart == 0) {
      ref.read(cartProvider.notifier).addService(service);
      AppToast.addedToCart(context, service.title);
    }
    // Use context.go — /cart is inside the ShellRoute.
    // context.push from outside the shell crosses navigator boundaries
    // and throws a GoException in go_router 14.x (red screen crash).
    context.go(AppRoutes.cart);
  }

  // Fixed 2026-10-07 — same root cause and fix as ProductCard._lockTextScale
  // (see that file's comment for the full explanation): this card's rows
  // use fixed-height image thumbnails and divider spacing tuned for the
  // platform's default text scale, so a device with a larger system
  // font-size setting can push the real content a few pixels past what
  // those rows budgeted for. Locking this card's own text scale to 1.0
  // keeps it deterministic across devices without touching accessibility
  // scaling anywhere else in the app.
  Widget _lockTextScale(BuildContext context, Widget child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.0),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGrocery = service.flowType == CatalogFlowType.grocery;
    final cartItems = ref.watch(cartProvider);
    final inCartItem =
        cartItems.where((i) => i.service.id == service.id).firstOrNull;
    final quantityInCart = inCartItem?.quantity ?? 0;
    AppLogger.d('[P0-CARD]',
        'building ServiceCard: title=${service.title}, id=${service.id}, quantityInCart=$quantityInCart, isGrocery=$isGrocery');

    return _lockTextScale(context, Container(
      margin: EdgeInsets.symmetric(vertical: isGrocery ? 6 : 9),
      decoration: isGrocery
          ? BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            )
          : null,
      clipBehavior: isGrocery ? Clip.antiAlias : Clip.none,
      child: isGrocery
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: _buildCardContent(
                context,
                ref,
                isGrocery: isGrocery,
                quantityInCart: quantityInCart,
              ),
            )
          : InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap ?? () => _navigateToDetail(context),
              child: _buildCardContent(
                context,
                ref,
                isGrocery: isGrocery,
                quantityInCart: quantityInCart,
              ),
            ),
    ));
  }

  Widget _buildCardContent(
    BuildContext context,
    WidgetRef ref, {
    required bool isGrocery,
    required int quantityInCart,
  }) {
    // Scheduled-service cards (not groceries — those keep the compact
    // left-thumbnail + ADD/BUY stepper layout below, since a quantity
    // stepper needs the denser row shape) now lead with a full-width image
    // "hero" section using the real admin-uploaded photo as the card's
    // background, instead of a small 88x88 side thumbnail. Added
    // 2026-09-16 per explicit request: "In at services - make the card
    // with image section for backgroung which has uploaded by the admin."
    if (!isGrocery) {
      return _buildServiceHeroContent(context, ref, quantityInCart: quantityInCart);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                  // Service Image Thumbnail
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildImageOrIcon(service, width: 76, height: 76),
                  ),
                  const SizedBox(width: 10),

                  // Info Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          service.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),

                        // Rating & Duration Row
                        if (isGrocery) ...[
                          Text(
                            service.displayUnit,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 15,
                                color: AppColors.star,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                service.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Text(
                                '(336)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textHint,
                                ),
                              ),
                              if (service.durationMinutes > 0) ...[
                                const SizedBox(width: 8),
                                const Text('•',
                                    style: TextStyle(
                                        color: AppColors.textHint, fontSize: 11.5)),
                                const SizedBox(width: 8),
                                Text(
                                  '${service.durationMinutes} mins',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],

                        const SizedBox(height: 6),

                        // Short description snippet if available
                        if (service.shortDescription != null &&
                            service.shortDescription!.isNotEmpty)
                          Text(
                            service.shortDescription!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 8),

              // Bottom Row: Price & Flow Action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Price tag
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₹${service.effectivePrice}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                      if (service.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          '₹${service.price}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textHint,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Actions
                  if (isGrocery) ...[
                    // Grocery ADD / BUY buttons
                    if (quantityInCart == 0) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => _handleAddToCart(context, ref),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFF1E3A8A), Color(0xFF0D253A)],
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shopping_cart_outlined,
                                      size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Add',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () =>
                                _handleBuyNow(context, ref, quantityInCart),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              minimumSize: const Size(60, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'BUY',
                              style: TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {
                                    ref
                                        .read(cartProvider.notifier)
                                        .updateQuantity(
                                          service.id,
                                          quantityInCart - 1,
                                        );
                                  },
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(8),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: Icon(
                                      Icons.remove,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '$quantityInCart',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    ref
                                        .read(cartProvider.notifier)
                                        .updateQuantity(
                                          service.id,
                                          quantityInCart + 1,
                                        );
                                    // Fixed 2026-09-18 per explicit request
                                    // ("the message popped up only for the
                                    // first, if count increases that also
                                    // should be popping out").
                                    AppToast.addedToCart(context, service.title);
                                  },
                                  borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(8),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () =>
                                _handleBuyNow(context, ref, quantityInCart),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              minimumSize: const Size(60, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'BUY',
                              style: TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    // Scheduled Service CTA Button
                    ElevatedButton(
                      onPressed: onTap ?? () => _navigateToDetail(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFE8EDF7),
                        foregroundColor: AppColors.navy,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 6),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
  }

  /// Image-forward hero layout for non-grocery service cards: the real
  /// admin-uploaded photo (via `_buildImageOrIcon` → `AppRemoteImage`,
  /// falling back to the flow-colored icon/gradient placeholder only when
  /// no image is configured or the network fetch fails) fills the full
  /// card width as a background section, with a bottom gradient scrim so
  /// the duration chip stays legible over any photo. Price and "View
  /// Details" sit below it, unchanged in spirit from the original bottom
  /// row, just without the left-thumbnail Row this replaces.
  /// Services listing card (redesigned 2026-10-14 from the supplied reference):
  /// a large rounded photo with a mint "X% OFF" pill, and a white panel that
  /// overlaps the photo's bottom edge holding a dark duration disc, the title +
  /// blurb, and a mint price block with the "View Details" action.
  Widget _buildServiceHeroContent(
    BuildContext context,
    WidgetRef ref, {
    required int quantityInCart,
  }) {
    const mint = Color(0xFFE8EDF7);
    const mintText = Color(0xFF1E3A8A);
    const overlap = 30.0;

    final showDiscount = service.discountPercent != null && !service.hasPackageOptions;
    final mins = service.durationMinutes;
    final durationTop = mins >= 60
        ? (mins % 60 == 0 ? '${mins ~/ 60}' : (mins / 60).toStringAsFixed(1))
        : '$mins';
    final durationUnit = mins >= 60 ? (mins == 60 ? 'hr' : 'hrs') : 'mins';

    return LayoutBuilder(
      builder: (context, c) {
        final imageHeight = (c.maxWidth.isFinite ? c.maxWidth : 320.0) / 1.22;
        return Stack(
          children: [
            // ── Photo ───────────────────────────────────────────────────
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImageOrIcon(
                      service,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    // Admin-deactivated package: grey the photo and label it
                    // (QA CMP04) — same behaviour as before the redesign.
                    if (!service.isAvailable) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                      ),
                      const Positioned.fill(
                        child: Center(child: _UnavailableBadge()),
                      ),
                    ],
                    // "Most Booked" style badge from the real isPopular flag.
                    if (service.badgeLabel != null)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 12, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                service.badgeLabel!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Top-right: mint "X% OFF" pill (from the real discount),
                    // or the rating when there is no discount to show.
                    Positioned(
                      right: 10,
                      top: 10,
                      child: showDiscount
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: mint,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${service.discountPercent}% OFF',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: mintText,
                                ),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 14, color: AppColors.star),
                                  const SizedBox(width: 3),
                                  Text(
                                    service.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Overlapping white panel ─────────────────────────────────
            Padding(
              padding: EdgeInsets.only(top: imageHeight - overlap),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (mins > 0) ...[
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1B1B1F),
                          shape: BoxShape.circle,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              durationTop,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              durationUnit,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.05,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        service.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Mint price block, exactly as in the reference: big
                    // price with the struck-through old price beside/below it.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: mint,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (service.hasPackageOptions)
                            const Text(
                              'From',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          Text(
                            '₹${service.hasPackageOptions ? service.startsAtPrice : service.effectivePrice}',
                            style: const TextStyle(
                              fontSize: 19.5,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111111),
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (service.hasDiscount && !service.hasPackageOptions)
                            Text(
                              '₹${service.price}',
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Small pill shown over a deactivated package's hero image — see the
/// "Fixed 2026-10-08 (QA CMP04...)" comment above where this is used.
class _UnavailableBadge extends StatelessWidget {
  const _UnavailableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
      ),
      child: const Text(
        'Unavailable',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
