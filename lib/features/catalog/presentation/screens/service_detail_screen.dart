import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../../shared/widgets/slow_load_gate.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/catalog_models.dart';
import '../../domain/catalog_providers.dart';

/// Service Details screen.
///
/// Rebuilt 2026-09-17 per explicit request ("make the entire Service page
/// correctly according to customer web application... there is no select
/// package at all"): this used to fabricate a "Select Package" radio-card
/// picker (two invented tiers — "Standard Service" / "Deep Service + Foam
/// Wash" — priced by adding a hardcoded ₹200 and 20 minutes to whatever the
/// real price was) and an "Add-ons" section (two invented items at a
/// hardcoded ₹149/₹199). Neither exists on the real customer web app or
/// anywhere in the backend catalog model — each catalog item already IS one
/// exact, fully-priced bookable thing, the same way ServiceCard/ProductCard
/// present it in the list. Both fabricated sections are gone; the screen
/// now shows only real, admin-configured data: image, title, description,
/// MRP (struck through) + discount + final price, What's Included, What
/// You Need to Get Ready, and Tools & Products We Use.
class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({
    super.key,
    required this.serviceSlug,
    this.initialService,
  });

  final String serviceSlug;
  final ServiceItem? initialService;

  @override
  ConsumerState<ServiceDetailScreen> createState() =>
      _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  Widget _buildHeroImageOrIcon(ServiceItem service) {
    return AppRemoteImage(
      imageUrl: service.imageUrl,
      rawPath: service.imageUrl,
      categoryName: service.categoryName,
      slug: service.slug,
      semanticIcon: ImageUrlHelper.mapCategoryIcon(
          service.categoryName, service.slug),
      width: double.infinity,
      height: 240,
      fit: BoxFit.cover,
    );
  }

  @override
  Widget build(BuildContext context) {
    final serviceAsync = ref.watch(serviceDetailProvider(widget.serviceSlug));
    final effectiveService = serviceAsync.valueOrNull ?? widget.initialService;
    if (effectiveService != null) {
      return _buildScaffold(context, effectiveService);
    }

    return serviceAsync.when(
      // Fixed 2026-09-30 per explicit request ("For entire page redirection
      // during the loading of data show a splash screen like uploaded
      // image... only for more delay/large loading otherwise use skeleton
      // loading"): the skeleton below still shows immediately and for
      // every ordinary load — SlowLoadGate only escalates to the branded
      // full-screen loader if this fetch is still running past its
      // threshold, which a normal service-detail request never hits.
      loading: () => const SlowLoadGate(
        skeleton: _ServiceDetailSkeleton(),
        tagline: 'Fetching this service\'s details...',
      ),
      error: (err, stackTrace) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: ErrorStateWidget(
          message: err.toString(),
          onRetry: () =>
              ref.refresh(serviceDetailProvider(widget.serviceSlug)),
        ),
      ),
      data: (service) => _buildScaffold(context, service),
    );
  }

  Widget _buildScaffold(BuildContext context, ServiceItem service) {
    final isGrocery = service.flowType == CatalogFlowType.grocery;
    final cartItems = ref.watch(cartProvider);
    final inCartItem =
        cartItems.where((i) => i.service.id == service.id).firstOrNull;
    final quantityInCart = inCartItem?.quantity ?? 0;

    // Related items strip — same category, real catalog data, current
    // service excluded. Cross-sell engagement the same way Amazon suggests
    // related products once you're on a product page.
    final relatedAsync = service.categoryId != null
        ? ref.watch(categoryServicesProvider(CategoryServicesParam(
            categoryId: service.categoryId,
            categorySlug: service.categorySlug ?? '',
          )))
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // ── Sliver App Bar with Hero Image ──
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 20),
              ),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeroImageOrIcon(service),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.share_outlined,
                      color: Colors.white, size: 18),
                ),
                onPressed: () {
                  // Updated 2026-09-23: domain moved to sevo.co.in (see
                  // config/env.dart's Env.mediaBaseUrl).
                  Share.share(
                    'Check out ${service.title} on CalServices: https://sevo.co.in/services/${service.slug}',
                  );
                },
              ),
            ],
          ),

          // ── Content ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    service.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Rating & Duration Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 16, color: AppColors.star),
                            const SizedBox(width: 3),
                            Text(
                              service.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (service.reviewCount > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${service.reviewCount} reviews)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (service.durationMinutes > 0) ...[
                        const SizedBox(width: 12),
                        const Text('•',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 14)),
                        const SizedBox(width: 12),
                        const Icon(Icons.schedule_rounded,
                            size: 15, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${service.durationMinutes} mins',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Description — the real admin-entered copy for this
                  // service/package (backend's Package.description). Never
                  // shown anywhere on this screen before this fix, even
                  // though the field was already being parsed and stored.
                  if (service.description != null &&
                      service.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      service.description!.trim(),
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Price card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '₹${service.effectivePrice}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy,
                              ),
                            ),
                            if (service.hasDiscount) ...[
                              const SizedBox(width: 8),
                              Text(
                                '₹${service.price}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textHint,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              // Fixed 2026-09-16: this badge was a hardcoded
                              // literal "28% OFF" for every single service
                              // regardless of its real price/discount —
                              // now computed from the actual price vs. the
                              // backend's offer_price, and hidden entirely
                              // when there's no real percentage to show.
                              if (service.discountPercent != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.chipGreenBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${service.discountPercent}% OFF',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.chipGreenText,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppColors.border, width: 0.8),
                          ),
                          child: const Text(
                            'Fixed Upfront Price',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Inclusions & Exclusions ──
                  if (service.inclusions.isNotEmpty ||
                      service.exclusions.isNotEmpty) ...[
                    if (service.inclusions.isNotEmpty)
                      _InclusionsCard(
                        title: "What's Included",
                        items: service.inclusions,
                        isIncluded: true,
                      ),
                    const SizedBox(height: 12),
                    if (service.exclusions.isNotEmpty)
                      _InclusionsCard(
                        title: "What's Excluded",
                        items: service.exclusions,
                        isIncluded: false,
                      ),
                    const SizedBox(height: 20),
                  ] else ...[
                    // Default Inclusions
                    const _InclusionsCard(
                      title: "What's Included",
                      items: [
                        'Complete system diagnostic check',
                        'Eco-friendly cleaning solvents',
                        'Post-service cleanup & testing',
                        '30-Day service rework warranty',
                      ],
                      isIncluded: true,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── What You Need to Get Ready ──
                  // Real backend field (Package.ready via
                  // CatalogServiceSerializer) — previously never read or
                  // displayed anywhere, so this admin-entered guidance
                  // (e.g. "Please keep the area accessible" / "Clear
                  // access to the AC unit") never reached the customer.
                  if (service.readyInstructions.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFDE68A),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.checklist_rounded,
                            size: 18,
                            color: Color(0xFF92400E),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'What you need to get ready',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Fixed 2026-09-16: Package.ready is a JSON
                                // list of instruction strings, not a single
                                // paragraph — render each as its own
                                // checklist row, matching how
                                // inclusions/exclusions are shown above.
                                ...service.readyInstructions.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 2),
                                          child: Icon(
                                            Icons.circle,
                                            size: 5,
                                            color: Color(0xFF92400E),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: AppColors.textPrimary,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Tools & Products We Use ──
                  // Real backend field (Package.tools via
                  // CatalogServiceSerializer) — previously not modeled in
                  // the mobile app at all.
                  if (service.tools.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.border,
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.handyman_outlined,
                                size: 18,
                                color: AppColors.navy,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Tools & products we use',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: service.tools
                                .map(
                                  (tool) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Text(
                                      tool,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── How It Works ──
                  const Text(
                    'How it works',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _StepTile(
                    number: '1',
                    title: 'Select Slot & Address',
                    subtitle: 'Choose your preferred date and time.',
                  ),
                  const SizedBox(height: 10),
                  const _StepTile(
                    number: '2',
                    title: 'Expert Arrives',
                    subtitle: 'Verified professional arrives at your doorstep.',
                  ),
                  const SizedBox(height: 10),
                  const _StepTile(
                    number: '3',
                    title: 'Service & Pay',
                    subtitle:
                        'High-quality service delivery with digital payment.',
                  ),

                  if (relatedAsync != null) ...[
                    const SizedBox(height: 24),
                    _RelatedItemsStrip(
                      relatedAsync: relatedAsync,
                      excludeId: service.id,
                      title: isGrocery
                          ? 'Frequently Bought Together'
                          : 'Related Services',
                      accent: isGrocery
                          ? AppColors.groceryGreen
                          : AppColors.serviceBlue,
                    ),
                  ],

                  const SizedBox(height: 120), // Bottom bar padding
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Sticky Bottom Bar ──
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppColors.border, width: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: isGrocery
            ? Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.displayUnit,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${service.effectivePrice}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  if (quantityInCart == 0)
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            ref
                                .read(cartProvider.notifier)
                                .addService(service);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.groceryGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Add to Cart',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => context.push('/cart'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.groceryGreenDark,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'View Cart',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Price',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '₹${service.effectivePrice}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Fixed 2026-10-07 ("The cart section is only working for
                  // groceries and vegetables not for the services block"):
                  // scheduled/non-grocery services previously had NO way to
                  // enter the shared `cartProvider` at all — "Book Now" (kept
                  // below, unchanged, for the one-tap single-service flow)
                  // pushed straight to /checkout and never called
                  // `addService()`. This mirrors the grocery branch's
                  // Add-to-Cart/View-Cart toggle so a service can also be
                  // added to the real cart, picked up by the Cart tab and by
                  // `checkout_screen.dart`'s existing shared-cart fallback.
                  SizedBox(
                    height: 52,
                    width: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        if (quantityInCart == 0) {
                          ref.read(cartProvider.notifier).addService(service);
                          AppToast.addedToCart(context, service.title);
                        } else {
                          context.push('/cart');
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: AppColors.serviceBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.shopping_cart_outlined,
                            color: AppColors.serviceBlue,
                            size: 22,
                          ),
                          if (quantityInCart > 0)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.serviceBlue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$quantityInCart',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          context.push(
                            '/checkout?service=${service.slug}',
                            extra: service,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.serviceBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Book Now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InclusionsCard extends StatelessWidget {
  const _InclusionsCard({
    required this.title,
    required this.items,
    required this.isIncluded,
  });

  final String title;
  final List<String> items;
  final bool isIncluded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isIncluded
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 16,
                    color: isIncluded ? AppColors.primary : AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Related Services" / "Frequently Bought Together" strip on the service
/// detail page — same category, current item excluded, real catalog data.
/// Renders nothing while loading, on error, or once filtered down to
/// nothing — this is a bonus cross-sell section, not core content.
class _RelatedItemsStrip extends ConsumerWidget {
  const _RelatedItemsStrip({
    required this.relatedAsync,
    required this.excludeId,
    required this.title,
    required this.accent,
  });

  final AsyncValue<List<ServiceItem>> relatedAsync;
  final int excludeId;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = relatedAsync.valueOrNull;
    if (all == null || all.isEmpty) return const SizedBox.shrink();

    final items = all.where((s) => s.id != excludeId).take(10).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 178,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () => context.push('/services/${item.slug}',
                    extra: item),
                child: Container(
                  width: 128,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 88,
                        width: double.infinity,
                        child: AppRemoteImage(
                          imageUrl: item.imageUrl,
                          rawPath: item.imageUrl,
                          title: item.title,
                          categoryName: item.categoryName,
                          slug: item.slug,
                          semanticIcon: ImageUrlHelper.mapCategoryIcon(
                              item.categoryName, item.slug),
                          fit: BoxFit.cover,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹${item.effectivePrice}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServiceDetailSkeleton extends StatelessWidget {
  const _ServiceDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBox(
              width: double.infinity,
              height: 240,
              borderRadius: 0,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerLine(width: 80, height: 12),
                  SizedBox(height: 10),
                  ShimmerLine(width: 240, height: 22),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      ShimmerBox(width: 60, height: 20, borderRadius: 4),
                      SizedBox(width: 12),
                      ShimmerLine(width: 70, height: 16),
                    ],
                  ),
                  SizedBox(height: 16),
                  ShimmerLine(width: double.infinity, height: 12),
                  SizedBox(height: 6),
                  ShimmerLine(width: 280, height: 12),
                  SizedBox(height: 6),
                  ShimmerLine(width: 200, height: 12),
                  SizedBox(height: 24),
                  ShimmerLine(width: 140, height: 18),
                  SizedBox(height: 14),
                  ShimmerCard(height: 100),
                  SizedBox(height: 12),
                  ShimmerCard(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
