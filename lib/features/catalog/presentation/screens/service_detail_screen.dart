import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/cart_pill_bar.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../../shared/widgets/slow_load_gate.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/catalog_models.dart';
import '../../domain/catalog_providers.dart';
import '../../../../core/navigation/safe_back.dart';

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
  /// The package option the customer picked (packages that have options).
  int? _chosenOptionId;

  // Fixed 2026-10-08 (QA CME05/CME04 — "the admin removes the image for the
  // package, it is still shows to the customer" / "the application
  // automatically refresh/update the latest data"): `serviceDetailProvider`
  // (catalog_providers.dart) is a `ref.keepAlive()` FutureProvider.family —
  // once fetched it never asks the backend again for the rest of the app
  // session, so an admin removing/changing a package's image (or any other
  // field) never reaches a customer already viewing it, or revisiting it
  // later in the same session. Invalidating it every time this screen is
  // entered re-fetches in the background; `AsyncValue.when`/`valueOrNull`
  // keeps showing the last-known data while that happens
  // (`skipLoadingOnRefresh` is Riverpod's default), so this reads as a
  // silent sync rather than a reload flash — see the matching fix on
  // category_detail_screen.dart's `initState` for the same pattern.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(serviceDetailProvider);
    });
  }

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
    // Goods & Transport packages are booked on the consolidated Goods &
    // Transport page, never on this generic service page (any entry point:
    // home cards, search, deep links).
    if (effectiveService != null && effectiveService.isGoodsTransport) {
      final target = effectiveService.goodsTransportPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(target);
      });
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
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

  Widget _buildScaffold(BuildContext context, ServiceItem baseService) {
    final chosen =
        baseService.packageOptions.where((o) => o.id == _chosenOptionId).firstOrNull;
    final service = chosen != null ? baseService.withOption(chosen) : baseService;
    // Options packages show the lowest option price until one is picked.
    final awaitingOption = service.hasPackageOptions && service.selectedOption == null;
    final shownPrice = awaitingOption ? service.startsAtPrice : service.effectivePrice;
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

    // Service / package pages use the redesigned layout (2026-10-14);
    // grocery items keep the original one below.
    if (!isGrocery) {
      return _buildServiceScaffold(
        context,
        baseService: baseService,
        service: service,
        awaitingOption: awaitingOption,
        shownPrice: shownPrice,
        relatedAsync: relatedAsync,
      );
    }

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
              onPressed: () => context.goBack(),
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
                    baseService.title,
                    style: const TextStyle(
                      fontSize: 19.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (baseService.badgeLabel != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 13, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            baseService.badgeLabel!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),

                  // Rating & Duration Row
                  Row(
                    children: [
                      if (service.hasReviews)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
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
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (service.hasReviews && service.reviewCount > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${service.reviewCount} reviews)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (service.durationMinutes > 0) ...[
                        const SizedBox(width: 12),
                        const Text('•',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 13)),
                        const SizedBox(width: 12),
                        const Icon(Icons.schedule_rounded,
                            size: 15, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${service.durationMinutes} mins',
                          style: const TextStyle(
                            fontSize: 12,
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
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],

                  if (service.hasPackageOptions) ...[
                    const SizedBox(height: 18),
                    _PackageOptionPicker(
                      options: service.packageOptions,
                      selectedId: _chosenOptionId,
                      onSelect: (o) => setState(() => _chosenOptionId = o.id),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Price card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
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
                            if (awaitingOption)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Text('From',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary)),
                              ),
                            Text(
                              '₹$shownPrice',
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy,
                              ),
                            ),
                            if (service.hasDiscount && !awaitingOption) ...[
                              const SizedBox(width: 8),
                              Text(
                                '₹${service.price}',
                                style: const TextStyle(
                                  fontSize: 13,
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
                  ],
                  // (no invented default inclusions: like the web app, an empty
                  // "What's Included" section is simply not shown)

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
                                    fontSize: 13,
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
                                              fontSize: 12,
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
                        color: AppColors.background,
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
                                  fontSize: 13,
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
                                        fontSize: 11.5,
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

                  // ── Customer Reviews (web parity) ──
                  if (service.reviews.isNotEmpty) ...[
                    _DetailSection(
                      icon: Icons.star_rounded,
                      title: 'Customer Reviews',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final r in service.reviews)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        r.name.isEmpty ? 'Customer' : r.name,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                      if (r.rating != null) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.star_rounded, size: 14, color: AppColors.star),
                                        const SizedBox(width: 2),
                                        Text(
                                          r.rating!.toStringAsFixed(r.rating! % 1 == 0 ? 0 : 1),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF92400E),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (r.text.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        r.text,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.4,
                                          color: AppColors.textSecondary,
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

                  // ── Frequently Asked Questions (web parity) ──
                  if (service.faqs.any((f) => f.question.trim().isNotEmpty || f.answer.trim().isNotEmpty)) ...[
                    _DetailSection(
                      icon: Icons.help_outline_rounded,
                      title: 'Frequently Asked Questions',
                      child: Column(
                        children: [
                          for (final f in service.faqs)
                            if (f.question.trim().isNotEmpty || f.answer.trim().isNotEmpty)
                              Material(
                                type: MaterialType.transparency,
                                child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding: const EdgeInsets.only(bottom: 10),
                                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                                  title: Text(
                                    f.question,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  children: [
                                    Text(
                                      f.answer,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── How It Works ──
                  const Text(
                    'How it works',
                    style: TextStyle(
                      fontSize: 16,
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
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${service.effectivePrice}',
                        style: const TextStyle(
                          fontSize: 19.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  // Fixed 2026-10-08 ("the admin inactivate the service, but
                  // it is still able to book by the customer" / QA CMP01):
                  // `ServiceItem.isAvailable` reflects the backend's
                  // `status` (PackageStatus — ACTIVE/INACTIVE/DRAFT/
                  // ARCHIVED). An admin-deactivated item must never reach
                  // "Add to Cart", so this is checked first, before the
                  // existing in-cart/not-in-cart branch.
                  if (!service.isAvailable)
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textSecondary.withValues(alpha: 0.35),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.textSecondary.withValues(alpha: 0.35),
                            disabledForegroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Unavailable',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (quantityInCart == 0)
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const Expanded(child: GoToCartPill(expand: true, push: true)),
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
                        awaitingOption ? 'From ₹$shownPrice' : '₹$shownPrice',
                        style: const TextStyle(
                          fontSize: 19.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // Reverted 2026-10-08 per explicit correction ("Grocery
                  // and services cannot be the same cart at all - this is
                  // two different workflow... the service is click package
                  // enter details choose slots and book the service this
                  // never to be enter into cart" / "remove the cart button
                  // beside the book now button"): the Add-to-Cart/View-Cart
                  // button added here on 2026-10-07 was wrong — services
                  // never go through the shared cart at all, they always go
                  // straight to Checkout via "Book Now" below. Removed; see
                  // app_router.dart's matching revert of the `/cart` route.
                  // Fixed 2026-10-08 (QA CMP01 — see the matching comment on
                  // the grocery "Add to Cart" branch above): same gate for
                  // the service-booking "Book Now" CTA.
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: service.isAvailable && !awaitingOption
                            ? () {
                                context.push(
                                  '/checkout?service=${service.slug}',
                                  extra: service,
                                );
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.serviceBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.textSecondary.withValues(alpha: 0.35),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          !service.isAvailable
                              ? 'Unavailable'
                              : (awaitingOption ? 'Select an option' : 'Book Now'),
                          style: const TextStyle(
                            fontSize: 14,
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

  // ───────────────────────────────────────────────────────────────────────
  // Redesigned service / package detail layout (2026-10-14, per the UI
  // requirement image): rounded curved hero with back + discount pill +
  // duration pill, floating title card, price card, What's Included,
  // How it works (connected steps) and a floating Book Now bar.
  // Services never use the shared cart, so there is no qty stepper / "Add".
  // ───────────────────────────────────────────────────────────────────────
  static const Color _pageBg = Color(0xFFF8F4EF);
  static const Color _okGreen = AppColors.navy;
  static const Color _mint = Color(0xFFE8EDF7);
  static const Color _mintText = Color(0xFF1E3A8A);

  Widget _modernCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _discountPill(int percent, {double fontSize = 12}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: fontSize > 13 ? 8 : 4),
      decoration: BoxDecoration(
        color: _mint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$percent% OFF',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: _mintText,
        ),
      ),
    );
  }

  Widget _buildServiceScaffold(
    BuildContext context, {
    required ServiceItem baseService,
    required ServiceItem service,
    required bool awaitingOption,
    required Object? shownPrice,
    required AsyncValue<List<ServiceItem>>? relatedAsync,
  }) {
    final topPad = MediaQuery.of(context).padding.top;
    final showDiscount = service.hasDiscount &&
        !awaitingOption &&
        service.discountPercent != null;
    final discountPercent = service.discountPercent ?? 0;

    final inclusions = service.inclusions.isNotEmpty
        ? service.inclusions
        : const [
            'Complete system diagnostic check',
            'Essential cleaning and sealing solutions',
            'Repair/replacement as needed',
            '30-Day service repair warranty',
          ];

    return Scaffold(
      backgroundColor: _pageBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Hero ──
          Padding(
            padding: EdgeInsets.fromLTRB(12, topPad + 8, 12, 0),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: ClipPath(
                clipper: _HeroCurveClipper(),
                child: SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildHeroImageOrIcon(service),
                      Positioned(
                        top: 16,
                        left: 16,
                        child: GestureDetector(
                          onTap: () => context.goBack(),
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back_rounded,
                                color: AppColors.navy, size: 24),
                          ),
                        ),
                      ),
                      if (showDiscount)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: _discountPill(discountPercent, fontSize: 14),
                        ),
                      if (service.durationMinutes > 0)
                        Positioned(
                          left: 16,
                          bottom: 40,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${service.durationMinutes} mins',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title card ──
                _modernCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              baseService.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy,
                                height: 1.15,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (baseService.badgeLabel != null &&
                                baseService.badgeLabel!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.navy,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        size: 13, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      baseService.badgeLabel!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (service.hasReviews) ...[
                                const Icon(Icons.star_rounded,
                                    size: 22, color: AppColors.star),
                                const SizedBox(width: 4),
                                Text(
                                  service.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy,
                                  ),
                                ),
                                ],
                                if (service.hasReviews && service.reviewCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '(${service.reviewCount})',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                if (service.durationMinutes > 0) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                      width: 1,
                                      height: 16,
                                      color: AppColors.border),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.schedule_rounded,
                                      size: 19,
                                      color: AppColors.textSecondary),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${service.durationMinutes} mins',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (service.description != null &&
                                service.description!.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                service.description!.trim(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          Share.share(
                            'Check out ${service.title} on CalServices: https://sevo.co.in/services/${service.slug}',
                          );
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: _pageBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.share_outlined,
                              size: 18, color: AppColors.navy),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Package options (only for packages that have them) ──
                if (service.hasPackageOptions) ...[
                  const SizedBox(height: 12),
                  _modernCard(
                    child: _PackageOptionPicker(
                      options: service.packageOptions,
                      selectedId: _chosenOptionId,
                      onSelect: (o) => setState(() => _chosenOptionId = o.id),
                    ),
                  ),
                ],

                // ── Price card ──
                const SizedBox(height: 12),
                _modernCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  if (awaitingOption)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Text('From',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary)),
                                    ),
                                  Text(
                                    '₹$shownPrice',
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.navy,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  if (service.hasDiscount &&
                                      !awaitingOption) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      '₹${service.price}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: AppColors.textHint,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (showDiscount) ...[
                              const SizedBox(height: 6),
                              _discountPill(discountPercent, fontSize: 13),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _mint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Fixed Upfront\nPrice',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: _mintText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── What's Included ──
                const SizedBox(height: 12),
                _modernCard(
                  child: _ModernChecklist(
                    title: "What's Included",
                    items: inclusions,
                    included: true,
                  ),
                ),
                if (service.exclusions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _modernCard(
                    child: _ModernChecklist(
                      title: "What's Excluded",
                      items: service.exclusions,
                      included: false,
                    ),
                  ),
                ],

                // ── What you need to get ready ──
                if (service.readyInstructions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: const Color(0xFFFDE68A), width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'What you need to get ready',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...service.readyInstructions.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Icon(Icons.circle,
                                      size: 5, color: Color(0xFF92400E)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: const TextStyle(
                                      fontSize: 13,
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

                // ── Tools & products we use ──
                if (service.tools.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _modernCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tools & products we use',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: service.tools
                              .map(
                                (tool) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _pageBg,
                                    borderRadius: BorderRadius.circular(20),
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
                ],

                // ── How it works ──
                const SizedBox(height: 12),
                _modernCard(
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How it works',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      SizedBox(height: 14),
                      _ModernStep(
                        number: '1',
                        title: 'Select Slot & Address',
                        subtitle: 'Choose your preferred date and time.',
                      ),
                      _ModernStep(
                        number: '2',
                        title: 'Expert Arrives',
                        subtitle:
                            'Verified professional comes to your location.',
                      ),
                      _ModernStep(
                        number: '3',
                        title: 'Service Completed',
                        subtitle: 'Issue fixed with quality check.',
                        isLast: true,
                      ),
                    ],
                  ),
                ),

                if (relatedAsync != null) ...[
                  const SizedBox(height: 20),
                  _RelatedItemsStrip(
                    relatedAsync: relatedAsync,
                    excludeId: service.id,
                    title: 'Related Services',
                    accent: AppColors.navy,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),

      // ── Floating bottom bar ──
      bottomNavigationBar: Container(
        color: Colors.transparent,
        padding: EdgeInsets.fromLTRB(
            12, 6, 12, 12 + MediaQuery.of(context).padding.bottom * 0.5),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!showDiscount)
                      const Text(
                        'Total Price',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            awaitingOption
                                ? 'From ₹$shownPrice'
                                : '₹$shownPrice',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          if (service.hasDiscount && !awaitingOption) ...[
                            const SizedBox(width: 8),
                            Text(
                              '₹${service.price}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textHint,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showDiscount) ...[
                      const SizedBox(height: 3),
                      _discountPill(discountPercent, fontSize: 11.5),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: service.isAvailable && !awaitingOption
                        ? () {
                            context.push(
                              '/checkout?service=${service.slug}',
                              extra: service,
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.textSecondary.withValues(alpha: 0.35),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      !service.isAvailable
                          ? 'Unavailable'
                          : (awaitingOption ? 'Select an option' : 'Book Now'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero image clip: the bottom edge curves up toward the right, like the UI
/// requirement image.
class _HeroCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - 56)
      ..quadraticBezierTo(w * 0.62, h + 6, w * 0.28, h - 4)
      ..quadraticBezierTo(w * 0.1, h - 8, 0, h - 28)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Card section with a title and green-tick (or red-cross) rows.
class _ModernChecklist extends StatelessWidget {
  const _ModernChecklist({
    required this.title,
    required this.items,
    required this.included,
  });

  final String title;
  final List<String> items;
  final bool included;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  included ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 24,
                  color: included
                      ? _ServiceDetailScreenState._okGreen
                      : AppColors.error,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "How it works" step with a mint number disc and a dashed connector.
class _ModernStep extends StatelessWidget {
  const _ModernStep({
    required this.number,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _ServiceDetailScreenState._mint,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ServiceDetailScreenState._okGreen,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 19, top: 3, bottom: 3),
            child: Column(
              children: List.generate(
                3,
                (_) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Container(
                    width: 1.5,
                    height: 3,
                    color: AppColors.border,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Choose an option" list for a package that has admin-defined options
/// (web parity: a package with options is booked per option, never at the
/// parent price).
class _PackageOptionPicker extends StatelessWidget {
  const _PackageOptionPicker({
    required this.options,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PackageOption> options;
  final int? selectedId;
  final ValueChanged<PackageOption> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose an option',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        const SizedBox(height: 10),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(o),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: o.id == selectedId ? Color(0xFFE8EDF7) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: o.id == selectedId ? AppColors.navy : AppColors.border,
                    width: o.id == selectedId ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      o.id == selectedId
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: o.id == selectedId ? AppColors.navy : AppColors.textHint,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.name,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (o.duration.trim().isNotEmpty || o.description.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                [o.duration.trim(), o.description.trim()]
                                    .where((s) => s.isNotEmpty)
                                    .join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${o.effectivePrice}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        if (o.hasOffer)
                          Text(
                            '₹${o.basePrice}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Titled card used for the Customer Reviews / FAQ sections.
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.navy),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
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
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
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
                    color: isIncluded ? AppColors.navy : AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 12,
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
            color: Color(0xFFE8EDF7),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
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
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
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
                fontSize: 16,
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
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹${item.effectivePrice}',
                              style: TextStyle(
                                fontSize: 12,
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
      backgroundColor: const Color(0xFFF8F4EF),
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
