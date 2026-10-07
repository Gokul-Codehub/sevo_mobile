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
  const ProductCard({
    super.key,
    required this.service,
    this.onTap,
    this.showImage = true,
    this.showPrice = true,
    this.showDiscount = true,
    this.showAddButton = true,
  });

  final ServiceItem service;
  final VoidCallback? onTap;

  // Added 2026-10-05 for the Grocery Home Section Builder's per-layout
  // "Display" checkboxes (Horizontal Carousel / Grid 3 / Grid 2 in
  // grocery_section_layouts.dart) — every existing call site of this widget
  // (category browse, search, seller-hub grids, product-detail "similar
  // products") constructs it with none of these, so they all default to
  // `true` and render byte-for-byte as before. Only the grocery-styled
  // branch ([_buildGroceryCard]) reads them; the non-grocery/service branch
  // is never reached from a grocery section (ServiceItem.flowType is forced
  // to grocery there) so it's left exactly as it was.
  final bool showImage;
  final bool showPrice;
  final bool showDiscount;
  final bool showAddButton;

  // Reserved height of the grocery card's title block (2 lines @ fontSize
  // 11.5, height 1.2 ≈ 27.6, rounded up) -- see the SizedBox wrapping the
  // Title Text in [_groceryCardBody] below. Kept as one named constant so
  // it can only ever be defined in the one place that also defines the
  // Text style it has to match, rather than as a second number in
  // [groceryCardHeight] that could silently drift from it.
  static const double _titleBlockHeight = 28.0;

  // Added 2026-10-05, fixing the grocery-row sizing bug described above the
  // Title SizedBox in [_groceryCardBody]. This is the SINGLE SOURCE OF
  // TRUTH for how tall a grocery [ProductCard] renders, given only the
  // content toggles that actually change its height -- never a specific
  // product's own data, since [_groceryCardBody]'s title block is now a
  // fixed [_titleBlockHeight] regardless of 1-line vs 2-line names. Any
  // caller that needs to give this card's horizontal/vertical container a
  // height (_ProductCarouselRow in grocery_section_layouts.dart) MUST
  // compute it from here rather than hardcoding its own guess -- that
  // exact drift (one guessed `height: 308` constant reused for every
  // section regardless of its actual showImage/showPrice/showAddButton
  // combination) is what produced both the empty-space-below-card bug and
  // the "BOTTOM OVERFLOWED" render error this fixed. The padding/row/
  // SizedBox figures below are transcribed directly from
  // [_groceryCardBody]'s own tree (fromLTRB(6,4,6,6), the 3px/2px/2px
  // inter-row SizedBoxes, the price row's ~19px text+baseline height, the
  // unit-badge/ADD row's ~26px tallest state) plus an 8px safety margin for
  // ordinary platform font-metric variance -- if that tree changes, this
  // must change with it.
  static double groceryCardHeight({
    required double cardWidth,
    bool showImage = true,
    bool showPrice = true,
    bool showAddButton = true,
  }) {
    double h = 0;
    if (showImage) h += cardWidth; // AspectRatio(aspectRatio: 1.0) image
    h += 4 + 6; // Padding.fromLTRB(6, 4, 6, 6) -- top + bottom
    h += showAddButton ? 26.0 : 20.0; // unit badge row / cart stepper row
    h += 3; // SizedBox(height: 3) after the badge/ADD row
    if (showPrice) h += 19.0; // price row (fontSize 15 + strike-through)
    h += 2; // SizedBox(height: 2) after the price row
    h += _titleBlockHeight; // reserved title block, always 2 lines' worth
    h += 2; // SizedBox(height: 2) after the title
    h += 14.0; // delivery-time / low-stock row
    h += 8.0; // safety margin for platform font-metric variance
    return h;
  }

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

  // Fixed 2026-10-07 ("in at device one... looking perfect but in at device
  // two there appearing the overflow by certain pixel issue... in future
  // this kind of bug should not arise even in different sized screen
  // devices"): every fixed-pixel height budget in this file (groceryCardHeight,
  // _titleBlockHeight, the image AspectRatios) was computed assuming the
  // platform's default text scale (1.0x). A second device with a larger
  // system font-size/accessibility setting renders the SAME text taller at
  // the SAME declared fontSize, which silently busts those budgets by a few
  // pixels — exactly the "BOTTOM OVERFLOWED BY N PIXELS" banners reported,
  // and exactly why it only showed up on one of the two devices even though
  // the code and screen size were identical. Dense catalog-card grids like
  // this one (fixed image aspect ratios, hard-coded title/price row heights)
  // cannot reflow sensibly at arbitrary text scale anyway, so — matching the
  // standard pattern other catalog apps use for the same reason — every
  // render of this card locks its own text scale to exactly 1.0 regardless
  // of the device's accessibility font-size setting. This never touches
  // body text, forms or any other screen's accessibility scaling — only the
  // text inside this one pixel-budgeted card.
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
    final accent = isGrocery ? AppColors.groceryGreen : AppColors.serviceBlue;

    if (isGrocery) {
      return _lockTextScale(
        context,
        _buildGroceryCard(context, ref, quantityInCart, accent),
      );
    }

    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0C0F172A),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0x04000000),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.2,
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
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 12, color: AppColors.star),
                        const SizedBox(width: 2.5),
                        Text(
                          service.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (service.hasDiscount)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Text(
                        'OFFER',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                if (!service.inStock)
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
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
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (service.hasDiscount) ...[
                            Text(
                              '₹${service.price}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textHint,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(height: 1),
                          ],
                          Text(
                            '₹${service.effectivePrice}',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Book',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 8,
                            color: accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return _lockTextScale(
      context,
      GestureDetector(
        onTap: onTap ?? () => context.push('/services/$_safeSlug', extra: service),
        child: card,
      ),
    );
  }

  Widget _buildGroceryCard(
    BuildContext context,
    WidgetRef ref,
    int quantityInCart,
    Color accent,
  ) {
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
      child: _groceryCardBody(quantityInCart, accent, context, ref),
    );
  }

  Widget _groceryCardBody(
    int quantityInCart,
    Color accent,
    BuildContext context,
    WidgetRef ref,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0C0F172A),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0x04000000),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Produce Image -- hidden entirely (not just blanked) when
          // showImage is false, so a text-only grocery card doesn't carry a
          // tall empty square above it.
          if (showImage)
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
                    if (showAddButton) _buildGroceryAction(context, ref, quantityInCart, accent),
                  ],
                ),
                const SizedBox(height: 3),
                // Price row -- fully hidden when showPrice is false; the
                // strike-through MRP has its own showDiscount flag so an
                // admin can keep the effective price visible while hiding
                // the "was ₹X" comparison, without ever fabricating a
                // discount that isn't real ([ServiceItem.hasDiscount] still
                // decides whether one exists at all).
                if (showPrice)
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
                      if (service.hasDiscount && showDiscount) ...[
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
                // Title -- reserved to a FIXED height for exactly 2 lines
                // regardless of whether this particular product's name
                // actually wraps to 1 line or 2. Fixed 2026-10-05: when this
                // card sat in a horizontal row (_ProductCarouselRow in
                // grocery_section_layouts.dart) whose outer box used one
                // hardcoded height for every section, a short 1-line title
                // left visible empty space below the card, while a longer
                // 2-line title in another section pushed the card's real
                // content past that same hardcoded height and produced a
                // "BOTTOM OVERFLOWED" render error. Making this card's own
                // height a pure function of its three content toggles (see
                // [groceryCardHeight] below) — never of a specific product's
                // title length — is what makes that computed height
                // trustworthy for every item in the row, not just whichever
                // one happened to be checked by eye.
                SizedBox(
                  height: _titleBlockHeight,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
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
                // Recipe badge removed 2026-09-30 per explicit request: the
                // Recipe feature isn't implemented yet (planned for phase 2,
                // after launch) — this card no longer advertises a
                // recipe count that doesn't lead anywhere.
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
    // Extracted 2026-10-05 into the public [QuickAddControl] widget below so
    // the new Grocery Home Section layouts (Compact List, Quick Add List)
    // can reuse the exact same add/increment/decrement cart logic instead
    // of a second, parallel implementation — see QuickAddControl's doc
    // comment.
    return QuickAddControl(service: service);
  }
}

/// The add/stepper control grocery [ProductCard]s have always used —
/// pulled out unchanged on 2026-10-05 so the Grocery Home Section Builder's
/// Compact List and Quick Add List layouts (grocery_section_layouts.dart)
/// share this exact cart logic rather than reimplementing it. Behavior is
/// byte-for-byte what [ProductCard] already did: "ADD" when nothing is in
/// the cart, a stepper once something is, "OUT" when out of stock, and a
/// toast when the per-item max quantity is hit. This is also why every
/// grocery layout — card, row, or quick-add list — ends up hitting the
/// exact same [cartProvider], never a second cart implementation.
class QuickAddControl extends ConsumerWidget {
  const QuickAddControl({super.key, required this.service});

  final ServiceItem service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final quantityInCart =
        cartItems.where((i) => i.service.id == service.id).firstOrNull?.quantity ?? 0;

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

