import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/banner_media.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../../shared/widgets/sevo_logo.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../booking/data/coupon_repository.dart';
import '../../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../../booking/domain/booking_models.dart';
import '../../../booking/domain/booking_providers.dart';
import '../../../catalog/data/grocery_hub_repository.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../../catalog/presentation/screens/grocery_hub_category_screen.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../data/homepage_repository.dart';
import '../../domain/home_flow_mode.dart';
import '../widgets/home_flow_theme.dart';

/// Up to 6 distinct services/groceries pulled from the customer's own
/// booking history for the "Book Again" shortcut row beneath the promo
/// banner — never an invented or hardcoded list. De-duplicated by service
/// id so re-ordering the same thing repeatedly doesn't crowd out other
/// recent orders. Bookings are sorted most-recent-first by their own
/// `createdAt` rather than assumed to already arrive that way from the API.
///
/// [flowFilter] added 2026-09-19 as part of the two-themed-home-pages
/// redesign: Services mode's "Book Again" should only reorder past
/// services, Groceries mode's only past groceries — otherwise switching
/// modes wouldn't actually separate the two experiences.
List<ServiceItem> _recentBookAgainItems(
  List<Booking> bookings, {
  CatalogFlowType? flowFilter,
}) {
  final sorted = [...bookings]..sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

  final seenServiceIds = <int>{};
  final result = <ServiceItem>[];
  for (final booking in sorted) {
    for (final item in booking.items) {
      // Fixed 2026-09-19: this used to be a strict equality check, so
      // passing CatalogFlowType.serviceBooking (Services mode's call below)
      // silently excluded the new CatalogFlowType.logistics value (Goods &
      // Transport) the moment that enum value was added — Goods & Transport
      // bookings vanished from "Book Again" in Services mode even though
      // they're bookings, not groceries. Services mode's filter now means
      // "anything that isn't a grocery booking" instead of "only
      // serviceBooking"; Groceries mode's filter (passed as
      // CatalogFlowType.grocery) is unaffected.
      if (flowFilter != null) {
        final matches = flowFilter == CatalogFlowType.grocery
            ? item.service.flowType == CatalogFlowType.grocery
            : item.service.flowType != CatalogFlowType.grocery;
        if (!matches) continue;
      }
      if (seenServiceIds.add(item.service.id)) {
        result.add(item.service);
        if (result.length == 6) return result;
      }
    }
  }
  return result;
}

/// Awaits [future] but swallows any error — used by Home's pull-to-refresh
/// (see `onRefresh` in `_HomeScreenState.build`) so one section failing to
/// refresh (e.g. a network blip on the coupons call) never stops the
/// `RefreshIndicator` from completing or blocks the other sections' own
/// refreshed data from showing.
Future<void> _refreshIgnoringErrors(Future<dynamic> future) =>
    future.then((_) {}, onError: (_) {});

/// Which [HomeFlowMode] a quick-access card represents, if any — matches
/// [_quickAccessFallbackIcon]/[_quickAccessFallbackColor]'s existing
/// keyword convention. A card that matches switches Home's mode in place
/// instead of navigating away (see [_HomeScreenState.build]'s quick-access
/// onTap); a card that matches neither (any extra admin-added card beyond
/// the original Groceries/Services pair) keeps the old navigate-away
/// behavior via [_handleQuickAccessTap].
HomeFlowMode? _flowModeForCard(MobileTopCardItem card) {
  final key = '${card.id} ${card.label}'.toLowerCase();
  if (key.contains('grocer') || key.contains('vegetable') || key.contains('fresh')) {
    return HomeFlowMode.groceries;
  }
  if (key.contains('service') || key.contains('repair') || key.contains('appliance')) {
    return HomeFlowMode.services;
  }
  return null;
}

/// Screen 6: Home Screen
/// Reference-driven UI layout with location header, hero promo, "Essential
/// Picks" / "Recommended Services" strips, "Why Choose SEVO?" trust
/// features, and promotional coupons.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Fixed 2026-09-21 per explicit bug report ("In starting of the
    // application it request to turn the GPS then detect the current
    // location but it does not fix the current location at all"): GPS
    // detection used to run exactly once, inside LocationAccessScreen
    // during first-time onboarding only. SplashScreen sends every
    // subsequent app open straight past onboarding to Home
    // (hasSeenOnboarding == true), so LocationAccessScreen — the ONLY
    // caller of detectAndSetCurrentLocation() — became unreachable after
    // the first run, permanently freezing customerLocationProvider at
    // whatever it last held (often still the hardcoded default). Home now
    // re-triggers a fresh GPS read itself on every mount, so live location
    // stays current instead of only ever being set once. Runs post-frame
    // (not directly in initState) since it reads/writes provider state and
    // the permission dialog needs a built widget tree behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(customerLocationProvider.notifier).detectAndSetCurrentLocation();
    });
  }

  @override
  Widget build(BuildContext context) {
    final groceryEssentialsAsync = ref.watch(groceryProduceProvider);
    final groceryHubCategories = ref.watch(groceryHubCategoriesProvider);
    final popularServicesAsync = ref.watch(popularServicesProvider);
    final myBookingsAsync = ref.watch(myBookingsProvider(null));
    final liveCategories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final groceryQuickAccessCategory = liveCategories
        .where((c) => c.flowType == CatalogFlowType.grocery)
        .firstOrNull;
    // Fixed 2026-09-19: strict `== serviceBooking` silently dropped Goods &
    // Transport the moment CatalogFlowType.logistics was added as its own
    // value — this is meant to mean "a non-grocery category", not
    // specifically "a serviceBooking category".
    final serviceQuickAccessCategory = liveCategories
        .where((c) => c.flowType != CatalogFlowType.grocery && c.isActive)
        .firstOrNull;
    // Fixed 2026-09-18 per explicit request ("Top cards 'Groceries' and
    // 'Services' could be editable like add new, delete and make text also
    // editable from admin panel"): the fixed groceryTopCard/serviceTopCard
    // pair is gone — the admin's "Mobile App ▸ Top Cards" tab now manages a
    // free-form list (any count, any label) via HomepageConfig.topCards.
    // When the admin hasn't published anything there yet, fall back to the
    // original 2-item Groceries/Services list built from the live catalog,
    // so the row is never empty on a fresh install.
    final homepageConfigForTopCards = ref.watch(homepageConfigProvider).valueOrNull;
    final adminTopCards = homepageConfigForTopCards?.topCards ?? const [];
    final quickAccessCards = adminTopCards.isNotEmpty
        ? adminTopCards
        : [
            MobileTopCardItem(
              id: 'groceries',
              label: 'Groceries',
              imageUrl: groceryQuickAccessCategory?.image,
              link: '/categories/vegetables_groceries',
            ),
            MobileTopCardItem(
              id: 'services',
              label: 'Services',
              imageUrl: serviceQuickAccessCategory?.image,
              link: '/categories',
            ),
          ];
    // The Groceries/Services pair (the cards [_flowModeForCard] recognizes)
    // drives Home's mode switch and renders first, at the top of the
    // screen — see _buildTopCardsRow below. Any OTHER admin-added card
    // (one that isn't recognized as either flow) still needs a home, so it
    // keeps its own separate pill row lower down ("Tiles"), just above
    // Banners — see _buildQuickAccessPillRow.
    final switcherCards =
        quickAccessCards.where((c) => _flowModeForCard(c) != null).toList();
    final extraQuickAccessCards =
        quickAccessCards.where((c) => _flowModeForCard(c) == null).toList();
    final selectedAddress = ref.watch(selectedAddressProvider);
    final customerLocation = ref.watch(customerLocationProvider);
    final screenWidth = MediaQuery.of(context).size.width;

    // Added 2026-09-19 ("like amazon and flipkart... by choosing the top
    // category like Groceries and Services let us render two different
    // home page cards, color theme and all"): the single switch everything
    // below reads from. Tapping the Groceries/Services quick-access card
    // sets this instead of navigating away — see _flowModeForCard and the
    // quick-access onTap below.
    final flowMode = ref.watch(homeFlowModeProvider);
    final flowTheme = HomeFlowTheme.of(flowMode);
    final groceryCategoryForShopByCategory = groceryQuickAccessCategory;

    // Added 2026-09-19 per explicit request ("below the location just show
    // the categories tiles... like the uploaded image" — a reference
    // screenshot of a website nav's icon+label category strip): a compact
    // horizontally-scrolling row of real, live catalog categories (never
    // fabricated ones), icon-on-top/label-below, directly under the
    // location bar. Built from real data only — Services mode uses the
    // live service categories, Groceries mode uses the grocery category's
    // own real subcategories — mirroring exactly what each mode's deeper
    // "Browse/Shop by Category" section already uses.
    final topCategoryTiles = flowMode == HomeFlowMode.groceries
        ? (groceryQuickAccessCategory?.subcategories ?? const [])
            .map((s) => (
                  label: s.name,
                  image: s.image,
                  slug: s.slug,
                  onTap: () => context.push(
                      '/categories/${groceryQuickAccessCategory!.slug}',
                      extra: groceryQuickAccessCategory),
                ))
            .toList()
        // Fixed 2026-09-19: same non-grocery fix as serviceQuickAccessCategory
        // above — Goods & Transport must still appear in this Services-mode
        // category strip.
        : (liveCategories
                .where((c) =>
                    c.isActive && c.flowType != CatalogFlowType.grocery)
                .toList()
              ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)))
            .map((c) => (
                  label: c.name,
                  image: c.image,
                  slug: c.slug,
                  onTap: () =>
                      context.push('/categories/${c.slug}', extra: c),
                ))
            .toList();

    // Resolve display location.
    // Fixed 2026-09-19 per explicit bug report ("even i doesnot login with
    // any account... it is showig 'Hosur, Tamilnadu' even i am in different
    // city") — a saved/selected address is only meaningful once someone is
    // actually signed in with a real account; a guest browsing session
    // should always see their live, current GPS location here, never a
    // saved address (this is now also enforced at the source in
    // AddressListNotifier, which returns no addresses at all for guests —
    // this check is a second, cheap guard against the same class of bug).
    //
    // REVISED 2026-09-21 per explicit follow-up ("eventhough logged in with
    // an acount wich has default addresses the system should give high
    // priority to the currecnt locaiton of the user"): a signed-in
    // customer's saved default address used to always win over live GPS.
    // Now live location is shown first for everyone — signed in or guest —
    // and a saved address is only the fallback for the rare case GPS
    // genuinely can't be read yet (permission just denied, no fix yet on a
    // brand-new device, etc.), never the default choice over a real fix.
    final isAuthenticated = ref.watch(isUserAuthenticatedProvider);
    final displayLocation = customerLocation.address.isNotEmpty
        ? customerLocation.address
        : (isAuthenticated && selectedAddress != null)
            ? '${selectedAddress.addressType.toUpperCase()}: ${selectedAddress.addressLine1.isNotEmpty ? selectedAddress.addressLine1 : selectedAddress.city}'
            : customerLocation.address;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Dark-to-light backdrop: the mode's own accent-dark color at the
          // very top, fading down into the screen's normal light
          // background. Used to be a fixed navy — now themed per mode
          // (deep green for Groceries) so the two "home pages" read as
          // visually distinct from the very first pixel, not just their
          // content further down.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // Sized for compact top cards and search bar
            height: 185,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    flowTheme.gradientTop,
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              color: flowTheme.accent,
              // Added 2026-09-19, REDONE same day per explicit feedback
              // ("it supposed to be the reloading stating showing in
              // skeleton reload... after user swipe down") — an earlier
              // version restarted the whole app (flashing the Splash
              // screen), which read as "the app relaunching," not "Home
              // refreshing." This now invalidates every data source Home
              // reads and awaits fresh results while STAYING on Home —
              // each section's own loading state (shimmer skeleton below,
              // or a spinner where a skeleton doesn't fit the shape) shows
              // during that window, then reveals the refreshed content.
              onRefresh: () async {
                ref.invalidate(categoriesProvider);
                ref.invalidate(groceryProduceProvider);
                ref.invalidate(popularServicesProvider);
                ref.invalidate(homepageConfigProvider);
                ref.invalidate(myBookingsProvider(null));
                ref.invalidate(availableCouponsProvider);
                await Future.wait([
                  _refreshIgnoringErrors(ref.read(categoriesProvider.future)),
                  _refreshIgnoringErrors(ref.read(groceryProduceProvider.future)),
                  _refreshIgnoringErrors(ref.read(popularServicesProvider.future)),
                  _refreshIgnoringErrors(ref.read(homepageConfigProvider.future)),
                  _refreshIgnoringErrors(ref.read(myBookingsProvider(null).future)),
                  _refreshIgnoringErrors(ref.read(availableCouponsProvider.future)),
                ]);
              },
              child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── 0/1. SEVO logo + Location bar (logo inside the pill) ──
            // Combined 2026-09-28 per explicit request, shown via annotated
            // screenshots ("can we place the logo at the place of
            // anotation?"), then refined per direct follow-up ("get it
            // inside the location container" — the logo sitting beside the
            // white pill, on the green backdrop, wasn't what was wanted).
            // The logo is now the first element INSIDE the same white pill
            // as the location pin/text/chevron, sharing its background —
            // one solid container, not two elements side by side. The
            // location pill's own tap target, icon, text and chevron are
            // unchanged. Order is still Logo+Location → Search → Top Cards
            // per the 2026-09-28 section order fix above.
            //
            // The notification bell that used to share this row was
            // removed 2026-09-19 per explicit request — this is now just
            // the location pin/text, nothing else.
            //
            // Fixed 2026-09-19 ("make the location visible"): this row's
            // white-on-dark styling (from when it always sat right under
            // the gradient) is nearly invisible once it lands past the end
            // of the dark gradient backdrop (which only covers the first
            // 260px). It's a self-contained solid pill with its own
            // background and dark navy text, so it reads clearly no matter
            // what's behind it or how the sections above are reordered.
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: GestureDetector(
                  onTap: () => context.push('/addresses?select=true'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SevoLogo(height: 18),
                        const SizedBox(width: 10),
                        Container(
                            width: 1,
                            height: 18,
                            color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.location_on_rounded,
                          size: 18,
                          color: flowTheme.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayLocation,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.navy,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 2. Search Bar ──
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: GestureDetector(
                  onTap: () => context.push('/search'),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
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
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            color: AppColors.textHint, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            // Themed per mode ("Search groceries..." vs
                            // "Search services...") — added 2026-09-19.
                            flowTheme.searchPlaceholder,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textHint,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: flowTheme.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: flowTheme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 3. Top Cards: Groceries / Services quick-access ──
            // Reverted 2026-09-19 back to the original full-bleed
            // photo-banner card style (explicit request: "the top card
            // return back to the old"), and each card now takes exactly an
            // equal Expanded share of the row so the pair together spans
            // the entire device width edge-to-edge (explicit request:
            // "make its width 50% each to occupy entire user device
            // width"), rather than the small centered icon tile that
            // replaced it earlier this session.
            if (switcherCards.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: _buildTopCardsRow(
                    cards: switcherCards,
                    onTap: (card) {
                      final mode = _flowModeForCard(card);
                      if (mode != null) {
                        ref.read(homeFlowModeProvider.notifier).state = mode;
                      }
                    },
                    isSelected: (card) => _flowModeForCard(card) == flowMode,
                    indicatorColor: (card) =>
                        _flowModeForCard(card) == HomeFlowMode.groceries
                            ? AppColors.groceryGreen
                            : AppColors.serviceBlue,
                  ),
                ),
              ),

            // ── 3.5 Category tiles (icon+label strip below Location) ──
            // Row height grown to 100 (from 92) 2026-09-19 to make room for
            // the tile label's second wrapped line — see _CategoryQuickTile.
            // "View All" moved to the FIRST slot 2026-09-19 per explicit
            // request ("View all category to first") — it used to trail
            // the row.
            if (topCategoryTiles.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: topCategoryTiles.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _CategoryQuickTile(
                          label: 'View All',
                          icon: Icons.apps_rounded,
                          color: flowTheme.accent,
                          onTap: () => context.push('/categories'),
                        );
                      }
                      final tile = topCategoryTiles[index - 1];
                      // imageUrl restored 2026-09-19 per explicit request
                      // ("place there the images like before i wanted is
                      // images should smaller like icons") — the real
                      // category photo is back, just at the smaller,
                      // icon-sized 40px _CategoryQuickTile now renders it
                      // at.
                      return _CategoryQuickTile(
                        label: tile.label,
                        imageUrl: tile.image,
                        icon: ImageUrlHelper.mapCategoryIcon(
                            tile.label, tile.slug),
                        color: flowTheme.accent,
                        onTap: tile.onTap,
                      );
                    },
                  ),
                ),
              ),

            // ── 4. Quick-access tiles (pill-shaped, sit just above Banners) ──
            // Any admin-added card that ISN'T recognized as Groceries or
            // Services (see _flowModeForCard) doesn't fit the mode-switch
            // row above — it keeps its own row here, directly above
            // Banners. Rendered as pill-shaped chips per explicit request
            // ("still it presentd as pills"), with the active one (if any)
            // marked by an underline rather than a border ring.
            if (extraQuickAccessCards.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _buildQuickAccessPillRow(
                    cards: extraQuickAccessCards,
                    onTap: (card) => _handleQuickAccessTap(context, card, liveCategories),
                  ),
                ),
              ),

            // ── 5. Banners ──
            // Lifted out of each mode's own content-slivers builder and up
            // to this fixed top-level slot 2026-09-19, per the explicit
            // section order requested (Top cards → Search bar → location
            // → Tiles → banners → everything else) — still themed per
            // mode via `flowMode` exactly as it was inside those builders.
            // Edge-to-edge full width 2026-09-19 per explicit request
            // ("occupy the entire width of the user mobile screen") — no
            // horizontal inset here anymore, unlike every other section on
            // this screen.
            SliverToBoxAdapter(
              child: _PromoBannerCarousel(
                mode: flowMode,
                aspectRatio: flowTheme.bannerAspectRatio,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── 6+ Mode-specific content ──
            // Added 2026-09-19 ("let's redesign from scratch... render two
            // different home page cards, color theme and all"): everything
            // below the search bar now comes from one of two completely
            // separate section lists, per the confirmed plan — Groceries
            // mode never shows service content (Recommended Services,
            // service categories) and vice versa, a clean Amazon/Flipkart
            // -style split rather than one page with both mixed together.
            ...(flowMode == HomeFlowMode.groceries
                ? _buildGroceriesContentSlivers(
                    context: context,
                    groceryCategory: groceryCategoryForShopByCategory,
                    groceryEssentialsAsync: groceryEssentialsAsync,
                    groceryHubCategories: groceryHubCategories,
                    adminBestsellers: homepageConfigForTopCards?.bestsellers ?? const [],
                    myBookingsAsync: myBookingsAsync,
                    screenWidth: screenWidth,
                  )
                : _buildServicesContentSlivers(
                    context: context,
                    liveCategories: liveCategories,
                    popularServicesAsync: popularServicesAsync,
                    myBookingsAsync: myBookingsAsync,
                    screenWidth: screenWidth,
                  )),
          ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  /// Renders the Groceries/Services top-cards row as full-bleed photo
  /// -banner cards (the original style, restored 2026-09-19 per explicit
  /// request: "the top card return back to the old") — an image filling
  /// the whole card, a bottom gradient scrim, and the label overlaid in
  /// white, rather than a small centered icon. Each card takes an equal
  /// `Expanded` share of the row so the pair spans the entire device width
  /// edge-to-edge (explicit request: "make its width 50% each to occupy
  /// entire user device width"); if more cards are ever added than fit
  /// legibly at that even split, the row falls back to a fixed card width
  /// and scrolls horizontally instead, same adaptive idea as before.
  Widget _buildTopCardsRow({
    required List<MobileTopCardItem> cards,
    required void Function(MobileTopCardItem card) onTap,
    bool Function(MobileTopCardItem card)? isSelected,
    Color? Function(MobileTopCardItem card)? indicatorColor,
  }) {
    const cardGap = 10.0;
    // Fixed 2026-09-28 per explicit request ("there are three cards can you
    // reduce the cars width to fit into the device width without scroll
    // after three... Reduce the size of the card"): the admin's
    // "Vegetables & Fruits" card now also matches [_flowModeForCard]'s
    // grocery keywords, so this row can hold 3 cards (not just the
    // original Groceries/Services pair) — a fixed 140px minimum width no
    // longer reliably fit 3 across a phone's width, forcing an unwanted
    // horizontal scroll. Smaller height too, matching the request.
    const cardHeight = 70.0;
    const visibleCount = 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Always sized as if exactly 3 cards share the row — evenly
        // stretched to fill it when there are 3 or fewer (1 and 2 cards
        // still fill the full width, same as before), or at that same
        // fixed per-card width when there are more, so a 4th+ card scrolls
        // in at the same size instead of shrinking every card to fit.
        final perCardWidth =
            (constraints.maxWidth - cardGap * (visibleCount - 1)) / visibleCount;

        Widget bannerFor(MobileTopCardItem card) => _TopCardBanner(
              card: card,
              onTap: () => onTap(card),
              isSelected: isSelected?.call(card) ?? false,
              indicatorColor: indicatorColor?.call(card),
            );

        if (cards.length <= visibleCount) {
          return SizedBox(
            height: cardHeight,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: cardGap),
                  Expanded(child: bannerFor(cards[i])),
                ],
              ],
            ),
          );
        }

        return SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: cardGap),
            itemBuilder: (context, index) => SizedBox(
              width: perCardWidth,
              child: bannerFor(cards[index]),
            ),
          ),
        );
      },
    );
  }

  /// Renders any admin-added quick-access card that isn't the Groceries
  /// /Services pair as a pill-shaped chip — explicit request ("still it
  /// presentd as pills") — a small circular thumbnail plus label inside a
  /// rounded-full white capsule, with the active one (if any) marked by an
  /// underline beneath the pill rather than a border ring.
  Widget _buildQuickAccessPillRow({
    required List<MobileTopCardItem> cards,
    required void Function(MobileTopCardItem card) onTap,
    bool Function(MobileTopCardItem card)? isSelected,
    Color? Function(MobileTopCardItem card)? indicatorColor,
  }) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final card = cards[index];
          return _QuickAccessPillTile(
            card: card,
            onTap: () => onTap(card),
            isSelected: isSelected?.call(card) ?? false,
            indicatorColor: indicatorColor?.call(card),
          );
        },
      ),
    );
  }

  /// Services-mode content: category grid (services only), service
  /// -flavored promo carousel, Book Again (services only), "Recommended
  /// Services", and a services-themed trust-badge row. This is what Home
  /// showed before the two-mode redesign, unchanged in substance — just
  /// extracted out of [build] so each mode's section list can be read (and
  /// maintained) independently of the other.
  List<Widget> _buildServicesContentSlivers({
    required BuildContext context,
    required List<Category> liveCategories,
    required AsyncValue<List<ServiceItem>> popularServicesAsync,
    required AsyncValue<List<Booking>> myBookingsAsync,
    required double screenWidth,
  }) {
    const theme = HomeFlowTheme.services;
    return [
      // ── Book Again (Recent Reservations, services only) ──
      // Real reorder history from the customer's own past bookings —
      // filtered to services only so Groceries mode's own Book Again
      // strip doesn't repeat the exact same list.
      myBookingsAsync.when(
        loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
        error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        data: (bookings) {
          final recentItems = _recentBookAgainItems(
            bookings,
            flowFilter: CatalogFlowType.serviceBooking,
          );
          if (recentItems.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }

          final cardWidth = (screenWidth - 32 - 30) / 4;

          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Book Again',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'From your recent orders',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < recentItems.length; i++) ...[
                          _BookAgainTile(
                            service: recentItems[i],
                            width: cardWidth,
                          ),
                          if (i != recentItems.length - 1)
                            const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 14)),

      // ── Services Advertisement ──
      const SliverToBoxAdapter(
        child: _MobileAdCard(mode: HomeFlowMode.services),
      ),

      // ── Recommended Services ──
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recommended Services',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              GestureDetector(
                onTap: () => context.push('/categories'),
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 12)),

      popularServicesAsync.when(
        loading: () => const SliverToBoxAdapter(
          child: SizedBox(
            height: 228,
            child: _HorizontalShimmerRow(height: 228),
          ),
        ),
        error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        data: (services) {
          if (services.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

          return SliverToBoxAdapter(
            child: SizedBox(
              height: 228,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: services.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => SizedBox(
                  width: 165,
                  child: RepaintBoundary(
                    child: ProductCard(service: services[i]),
                  ),
                ),
              ),
            ),
          );
        },
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 14)),

      _buildTrustSection(theme),

      const SliverToBoxAdapter(child: SizedBox(height: 14)),

      // ── Offers & Coupons Banner ──
      const SliverToBoxAdapter(child: _LiveCouponBanner()),

      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  /// Groceries-mode content: "Shop by Category" (the grocery category's own
  /// real subcategories — Vegetables, Fruits, Dairy, etc., never a
  /// hardcoded list), a grocery-flavored promo carousel, Book Again
  /// (groceries only), "Essential Picks", and a groceries-themed
  /// trust-badge row.
  List<Widget> _buildGroceriesContentSlivers({
    required BuildContext context,
    required Category? groceryCategory,
    required AsyncValue<List<ServiceItem>> groceryEssentialsAsync,
    required List<GroceryHubCategoryGroup> groceryHubCategories,
    required List<MobileBestsellerItem> adminBestsellers,
    required AsyncValue<List<Booking>> myBookingsAsync,
    required double screenWidth,
  }) {
    const theme = HomeFlowTheme.groceries;

    return [
      // ── Book Again (groceries only) ──
      myBookingsAsync.when(
        loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
        error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        data: (bookings) {
          final recentItems = _recentBookAgainItems(
            bookings,
            flowFilter: CatalogFlowType.grocery,
          );
          if (recentItems.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }

          final cardWidth = (screenWidth - 32 - 30) / 4;

          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Book Again',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'From your recent orders',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < recentItems.length; i++) ...[
                          _BookAgainTile(
                            service: recentItems[i],
                            width: cardWidth,
                          ),
                          if (i != recentItems.length - 1)
                            const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 14)),

      // ── Browse Groceries by Category (Seller Hub) ──
      // Added 2026-09-25 per explicit request: a real, nested department
      // tree ("Superadmin Console → Seller Hub → Categories" on the
      // vendor's own admin) now exists for packaged groceries, browsable
      // via [SellerHubGroceriesScreen] the same way Vegetable Inventory
      // already is on the catalog screen. This banner is the entry point —
      // it doesn't replace Bestsellers or Essential Picks below, which keep
      // reading their own existing data sources untouched.
      // SliverToBoxAdapter(
      //   child: Padding(
      //     padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      //     child: GestureDetector(
      //       onTap: () => context.push('/groceries/seller-hub'),
      //       child: Container(
      //         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      //         decoration: BoxDecoration(
      //           color: AppColors.groceryGreenLight,
      //           borderRadius: BorderRadius.circular(12),
      //           border: Border.all(color: AppColors.groceryGreen.withValues(alpha: 0.3)),
      //         ),
      //         child: Row(
      //           children: [
      //             Container(
      //               width: 40,
      //               height: 40,
      //               decoration: const BoxDecoration(
      //                 color: Colors.white,
      //                 shape: BoxShape.circle,
      //               ),
      //               child: const Icon(Icons.storefront_rounded, color: AppColors.groceryGreenDark, size: 22),
      //             ),
      //             const SizedBox(width: 12),
      //             const Expanded(
      //               child: Column(
      //                 crossAxisAlignment: CrossAxisAlignment.start,
      //                 children: [
      //                   Text(
      //                     'Browse Groceries by Category',
      //                     style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy),
      //                   ),
      //                   SizedBox(height: 2),
      //                   Text(
      //                     'Oils, dairy, pantry & more — shop by department',
      //                     style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
      //                   ),
      //                 ],
      //               ),
      //             ),
      //             const Icon(Icons.chevron_right_rounded, color: AppColors.groceryGreenDark),
      //           ],
      //         ),
      //       ),
      //     ),
      //   ),
      // ),

      // ── Bestsellers ──
      // Added 2026-09-19 per the user-supplied Grocery Hub integration
      // guide + reference screenshots ("group like this and present those
      // data into our application aesthetic"): real packaged-grocery
      // products (dairy, chips, bakery, oil, ice cream, etc.) from the
      // separate Vendor Grocery Hub backend, grouped into the same
      // 2x2-thumbnail "+N more" category tiles shown in the reference. This
      // never touches fresh Vegetables & Fruits (still "Essential Picks"
      // below, from the existing catalog) or anything in Services mode.
      //
      // Fixed 2026-09-23 per explicit request ("make the 'Best Seller' has
      // reliable data and the counts... give privilege to admin to update
      // this from the admin panel"): these tiles used to be built ENTIRELY
      // from the auto-grouped vendor feed above, with no admin control over
      // which tiles showed or what count each one displayed. The admin's
      // own "Mobile Bestsellers" list (see [MobileBestsellerItem]) is now
      // preferred whenever it's non-empty; the auto-grouped vendor tiles
      // only render as a fallback while the admin hasn't configured any —
      // so this section still never blanks out.
      if (adminBestsellers.isNotEmpty) ...[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Bestsellers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: adminBestsellers.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, i) => _AdminBestsellerTile(
                item: adminBestsellers[i],
                onTap: () => _handleAdminLinkTap(
                  context,
                  adminBestsellers[i].link,
                  fallbackPath: '/categories/vegetables_groceries',
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
      ] else if (groceryHubCategories.isNotEmpty) ...[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Bestsellers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: groceryHubCategories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, i) => _GroceryHubBestsellerTile(
                group: groceryHubCategories[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroceryHubCategoryScreen(
                      group: groceryHubCategories[i],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
      ],

      // ── Groceries & Vegetables Advertisement ──
      const SliverToBoxAdapter(
        child: _MobileAdCard(mode: HomeFlowMode.groceries),
      ),

      // ── Essential Picks ──
      // Blinkit-style "Essentials" strip — real Farm-Fresh produce from the
      // live catalog, not a category grid.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Essential Picks',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              GestureDetector(
                onTap: () =>
                    context.push('/categories/vegetables_groceries'),
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 12)),

      groceryEssentialsAsync.when(
        loading: () => const SliverToBoxAdapter(
          child: SizedBox(
            height: 308,
            child: _HorizontalShimmerRow(height: 308),
          ),
        ),
        error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        data: (produce) {
          if (produce.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

          return SliverToBoxAdapter(
            child: SizedBox(
              height: 308,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: produce.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => SizedBox(
                  width: 165,
                  child: RepaintBoundary(
                    child: ProductCard(service: produce[i]),
                  ),
                ),
              ),
            ),
          );
        },
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 14)),

      _buildTrustSection(theme),

      const SliverToBoxAdapter(child: SizedBox(height: 14)),

      const SliverToBoxAdapter(child: _LiveCouponBanner()),

      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  /// The trust-badge row shared by both modes — same layout, different
  /// copy/icons/color per [theme] (see [HomeFlowTheme]).
  Widget _buildTrustSection(HomeFlowTheme theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              theme.trustSectionTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < theme.trustBadges.length; i++) ...[
                  Expanded(
                    child: _WhyChooseItem(
                      icon: theme.trustBadges[i].$1,
                      label: theme.trustBadges[i].$2,
                      color: theme.accent,
                    ),
                  ),
                  if (i != theme.trustBadges.length - 1)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Keyword-matched fallback icon for a quick-access card that has no admin
/// image yet — mirrors the `_styleFor`/`_heroCopyFor` keyword-mapping
/// pattern already used in all_services_screen.dart / category_detail_
/// screen.dart, so a newly admin-added card (anything beyond the original
/// Groceries/Services pair) still gets a sensible icon instead of a blank
/// tile. Falls back to a generic storefront icon for anything unrecognized.
IconData _quickAccessFallbackIcon(String labelOrId) {
  final key = labelOrId.toLowerCase();
  if (key.contains('grocer') || key.contains('vegetable') || key.contains('fresh')) {
    return Icons.eco_rounded;
  }
  if (key.contains('service') || key.contains('repair') || key.contains('appliance')) {
    return Icons.home_repair_service_rounded;
  }
  if (key.contains('clean')) return Icons.cleaning_services_rounded;
  if (key.contains('electric')) return Icons.electrical_services_rounded;
  if (key.contains('plumb')) return Icons.plumbing_rounded;
  if (key.contains('paint')) return Icons.format_paint_rounded;
  return Icons.storefront_rounded;
}

/// Keyword-matched fallback accent color, same mapping rule as
/// [_quickAccessFallbackIcon].
Color _quickAccessFallbackColor(String labelOrId) {
  final key = labelOrId.toLowerCase();
  if (key.contains('grocer') || key.contains('vegetable') || key.contains('fresh')) {
    return AppColors.groceryGreen;
  }
  if (key.contains('clean')) return const Color(0xFF0EA5E9);
  if (key.contains('electric')) return const Color(0xFFF59E0B);
  if (key.contains('plumb')) return const Color(0xFF2563EB);
  if (key.contains('paint')) return const Color(0xFFDB2777);
  return AppColors.serviceBlue;
}

/// Resolves a quick-access card's tap destination. Admin-configured `link`
/// wins when present (either a bare category slug/path like
/// "/categories/vegetables_groceries" or a "?category=slug" query shape,
/// both of which the web admin's other link fields already use); otherwise
/// falls back to the original hardcoded behavior for the two built-in ids
/// so existing Groceries/Services taps keep working unchanged.
/// Resolves an admin-entered click-through link (e.g. "?category=cleaning"
/// or a full app path) the same way [_handleQuickAccessTap] does for the
/// quick-access cards — added 2026-09-23 alongside [MobileBestsellerItem]
/// so the Bestsellers tiles' links behave identically instead of each
/// admin-link field growing its own slightly different parsing.
// Fixed 2026-09-28 per explicit report (a Bestseller click-through to
// "/marketplace?category=mkt-dairy-eggs" showing unrelated "random data"
// instead of the Dairy & Eggs products the same URL shows on the website):
// an admin link's `category=<slug>` can belong to either of two completely
// separate catalogs — the Vegetable Inventory tree (`/categories/:slug`,
// CategoryDetailScreen) or the Seller Hub Marketplace tree
// (`/groceries/seller-hub`, SellerHubGroceriesScreen,
// MarketplaceCategory.slug). Sending a marketplace slug to the Vegetable
// Inventory endpoint doesn't fail loudly — the backend just ignores the
// unmatched filter and returns an unrelated default set, which is exactly
// the "random data" that was reported. The two catalogs' slugs aren't
// distinguishable by shape alone, but the admin's marketplace links always
// carry the "/marketplace" path segment (matching the web app's own
// `/marketplace?category=...` route) — checked first, before falling back
// to the Vegetable Inventory route for every other category link.
String _resolveCategoryLinkRoute(String link, String slug) {
  return link.contains('/marketplace')
      ? '/groceries/seller-hub?category=$slug'
      : '/categories/$slug';
}

void _handleAdminLinkTap(BuildContext context, String? rawLink, {required String fallbackPath}) {
  final link = rawLink?.trim() ?? '';
  if (link.isNotEmpty) {
    final categoryMatch = RegExp(r'category=([\w-]+)').firstMatch(link);
    if (categoryMatch != null) {
      context.push(_resolveCategoryLinkRoute(link, categoryMatch.group(1)!));
      return;
    }
    if (link.startsWith('/')) {
      context.push(link);
      return;
    }
  }
  context.push(fallbackPath);
}

// Fixed 2026-09-28 per explicit report (tapping the admin's "Groceries" /
// "Vegetables & Fruits" quick-access cards — left with no click-through
// link configured, see Card #1/#3 in the admin's "Mobile Quick Access
// Cards" screen — opened an empty page, unlike "Services" which always
// worked): this used to push a hardcoded GUESSED slug
// ('/categories/vegetables_groceries') straight into the router with no
// live data behind it. That guess silently stops matching the moment the
// admin renames or restructures the real category — CategoryDetailScreen
// then can't resolve `currentCategory`, queries the backend with a slug
// nothing recognizes, and correctly comes back empty. Every other
// grocery-aware surface in this app ([Category.flowType]) already
// classifies categories off the LIVE list instead of a fixed slug guess —
// reused here, with the real [Category] passed as `extra` so
// CategoryDetailScreen never has to re-resolve it by slug at all.
void _handleQuickAccessTap(
  BuildContext context,
  MobileTopCardItem card,
  List<Category> liveCategories,
) {
  final link = card.link?.trim() ?? '';
  if (link.isNotEmpty) {
    final categoryMatch = RegExp(r'category=([\w-]+)').firstMatch(link);
    if (categoryMatch != null) {
      context.push(_resolveCategoryLinkRoute(link, categoryMatch.group(1)!));
      return;
    }
    if (link.startsWith('/')) {
      context.push(link);
      return;
    }
  }

  final key = '${card.id} ${card.label}'.toLowerCase();
  if (key.contains('grocer') || key.contains('vegetable') || key.contains('fruit')) {
    final match = liveCategories.where((c) => c.flowType == CatalogFlowType.grocery).firstOrNull;
    if (match != null) {
      context.push('/categories/${match.slug}', extra: match);
      return;
    }
    // No matching Vegetable Inventory category is live — the Seller Hub
    // Marketplace catalog is a real grocery surface too, and a better
    // fallback than a guaranteed-empty guessed slug.
    context.push('/groceries/seller-hub');
    return;
  }
  context.push('/categories');
}

/// Skeleton placeholder for a horizontal row of product/service cards
/// while their data is loading — added 2026-09-19 per explicit correction
/// ("supposed to be the reloading stating showing in skeleton reload"):
/// pull-to-refresh now re-fetches in place rather than restarting the app,
/// so these loading branches needed a real skeleton instead of a bare
/// centered spinner to actually read as "reloading," not "something
/// broke." Mirrors the 165-wide card shape used once data arrives.
class _HorizontalShimmerRow extends StatelessWidget {
  const _HorizontalShimmerRow({this.height = 228});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) => SizedBox(
        width: 165,
        child: ProductCardSkeleton(height: height, width: 165, borderRadius: 14),
      ),
    );
  }
}

/// Groceries/Services top-cards row tile — redesigned 2026-09-28 per
/// explicit reference (a Swiggy-style Food / Instamart / Dineout mode
/// switcher): a rounded dark card with a circular icon badge up top and
/// the label beneath, where the ACTIVE card alone gets a bold gradient
/// fill and a soft glow, and every inactive card sits flat and dark beside
/// it — so which mode is active reads at a glance without a border ring
/// or checkmark badge. The gradient/dark colors are still driven by the
/// mode's own brand accent ([indicatorColor]: green for Groceries, blue
/// for Services) rather than the reference's literal red, so the row
/// stays visually part of this app rather than another product's palette.
/// The circular badge shows the card's own real uploaded photo when the
/// admin has set one (same [AppRemoteImage] used everywhere else in this
/// app — never a fabricated photo), and only falls back to a plain
/// keyword-matched icon when there isn't one yet.
class _TopCardBanner extends StatelessWidget {
  const _TopCardBanner({
    required this.card,
    required this.onTap,
    this.isSelected = false,
    this.indicatorColor,
  });

  final MobileTopCardItem card;
  final VoidCallback onTap;

  /// True when this card is the one currently driving Home's mode (see
  /// [_flowModeForCard]/homeFlowModeProvider) — shown here as a colored
  /// border ring around the whole banner.
  final bool isSelected;

  /// The matched mode's own brand color (green for Groceries, blue for
  /// Services) used for the selected-state ring — not necessarily
  /// [fallbackColor], since a card can have its own uploaded image with a
  /// totally different dominant color.
  final Color? indicatorColor;

  /// Bundled fallback photo for the Groceries/Services pair specifically —
  /// added 2026-09-19 from images the user supplied directly (a grocery
  /// bag and a home-cleaning photo) so these two cards always show a real
  /// photo even before the admin uploads their own via "Mobile App ▸ Top
  /// Cards". Any OTHER admin-added card that doesn't match either flow
  /// still falls back to the flat keyword-matched color, unchanged.
  String? _bundledFallbackAsset() {
    switch (_flowModeForCard(card)) {
      case HomeFlowMode.groceries:
        return 'assets/images/top_card_fresh.webp';
      case HomeFlowMode.services:
        return 'assets/images/top_card_services.webp';
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackColor = _quickAccessFallbackColor('${card.id} ${card.label}');
    final fallbackIcon = _quickAccessFallbackIcon('${card.id} ${card.label}');
    final accent = indicatorColor ?? fallbackColor;
    final bundledAsset = _bundledFallbackAsset();
    // A darker stop for the active card's gradient — same brand color the
    // rest of the app already keys per mode (groceryGreenDark/
    // serviceBlueDark), so the gradient never introduces a color the app
    // doesn't already use elsewhere for this mode.
    final accentDark = accent == AppColors.groceryGreen
        ? AppColors.groceryGreenDark
        : accent == AppColors.serviceBlue
            ? AppColors.serviceBlueDark
            : Color.lerp(accent, Colors.black, 0.35)!;

    // Fixed 2026-09-28 per explicit request ("Reduce the size of the card
    // and fit the image as background"): back to a full-bleed photo
    // background (like the pre-2026-09-19 design) rather than a small
    // icon badge — the real uploaded card photo now fills the whole tile,
    // with a bottom gradient scrim for the label and, on the active card
    // only, a colored wash + soft glow using the mode's own brand accent.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppRemoteImage(
              imageUrl: card.imageUrl,
              rawPath: card.imageUrl,
              title: card.label,
              fit: BoxFit.cover,
              fallbackWidget: bundledAsset != null
                  ? Image.asset(bundledAsset, fit: BoxFit.cover)
                  : Container(color: fallbackColor.withValues(alpha: 0.85)),
            ),
            // Bottom gradient scrim so the label stays legible over any
            // photo, then — active card only — a full-card color wash in
            // the mode's own brand gradient, so the active card visibly
            // "pops" against the plain inactive ones next to it.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.3, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: isSelected ? 0.45 : 0.55),
                  ],
                ),
              ),
            ),
            if (isSelected)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.55),
                      accentDark.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(fallbackIcon, size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      card.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill-shaped quick-access chip for any admin-added card that isn't the
/// Groceries/Services pair — explicit request ("still it presentd as
/// pills"): a small circular thumbnail plus the label inside a
/// rounded-full white capsule. An active card (if the caller ever marks
/// one selected) is indicated by an underline beneath the pill rather
/// than a border ring, keeping the pill's own shape undisturbed.
class _QuickAccessPillTile extends StatelessWidget {
  const _QuickAccessPillTile({
    required this.card,
    required this.onTap,
    this.isSelected = false,
    this.indicatorColor,
  });

  final MobileTopCardItem card;
  final VoidCallback onTap;
  final bool isSelected;
  final Color? indicatorColor;

  @override
  Widget build(BuildContext context) {
    final fallbackColor = _quickAccessFallbackColor('${card.id} ${card.label}');
    final fallbackIcon = _quickAccessFallbackIcon('${card.id} ${card.label}');
    final accent = indicatorColor ?? fallbackColor;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: AppRemoteImage(
                      imageUrl: card.imageUrl,
                      rawPath: card.imageUrl,
                      title: card.label,
                      fit: BoxFit.cover,
                      fallbackWidget: Container(
                        color: fallbackColor.withValues(alpha: 0.14),
                        child: Icon(fallbackIcon,
                            size: 14, color: fallbackColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  card.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? accent : AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Active indicator: an underline beneath the pill, not a border
          // ring around it — per explicit request ("make it tile
          // active:underline").
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isSelected ? 20 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tile in the "Browse by Category" grid below the search bar — a small
/// rounded icon (the category's own live catalog image, falling back to a
/// keyword-matched icon exactly like the Services screen does) with the
/// category's real name underneath. Unlike [_TopCardBanner] above, this
/// grid sits below the dark navy-to-light gradient backdrop (past where
/// that gradient ends), so its label uses the app's normal dark navy text
/// rather than white-on-dark.
class _CategoryQuickTile extends StatelessWidget {
  const _CategoryQuickTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.imageUrl,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shrunk 2026-09-19 per explicit request ("images should smaller
          // like icons") — the real category image is back (it had been
          // removed for a bare-icon look), but sized down to a genuinely
          // icon-sized 40px thumbnail rather than the larger 54px photo
          // tile it used to be.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AppRemoteImage(
                imageUrl: imageUrl,
                rawPath: imageUrl,
                title: label,
                fit: BoxFit.cover,
                fallbackWidget: Container(
                  color: color.withValues(alpha: 0.12),
                  child: Center(
                    child: Icon(icon, color: color, size: 18),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Grown to 2 lines 2026-09-19 per explicit request ("if the
          // name/title is long break after a word and place under it") —
          // a long category name now wraps onto a second line at a normal
          // word boundary instead of being cut short with an ellipsis on
          // the first line.
          SizedBox(
            width: 64,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One "Bestsellers" category tile — a 2x2 grid of the category's first
/// four real product photos (from the Grocery Hub) with a "+N more" pill
/// overlapping its bottom-right corner, and the category name below.
/// Matches the reference screenshot's layout exactly. When the category
/// has fewer than 4 products, the remaining grid cells repeat/clip the
/// available images rather than showing empty gaps, and the "+N more"
/// pill is simply omitted once every product actually fits in the 2x2
/// preview.
class _GroceryHubBestsellerTile extends StatelessWidget {
  const _GroceryHubBestsellerTile({required this.group, required this.onTap});

  final GroceryHubCategoryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final products = group.products;
    final previewCount = products.length < 4 ? products.length : 4;
    final remaining = products.length - 4;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemBuilder: (context, i) {
                      final product = previewCount == 0
                          ? null
                          : products[i % previewCount];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          color: Colors.white,
                          child: product == null
                              ? null
                              : AppRemoteImage(
                                  imageUrl: product.image,
                                  title: product.name,
                                  fit: BoxFit.contain,
                                ),
                        ),
                      );
                    },
                  ),
                ),
                if (remaining > 0)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        '+$remaining more',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            group.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin-authored Bestsellers tile (config['mobile']['bestsellers']) — the
/// exact same 2x2-thumbnail-grid-plus-"+N more"-badge look as
/// [_GroceryHubBestsellerTile] above, but built from up to 4 admin-uploaded
/// photos ([MobileBestsellerItem.thumbnails]) and a manually-entered count
/// instead of a live grid of real vendor product thumbnails, since the
/// whole point of this tile is that the admin controls exactly what it
/// shows.
///
/// Fixed 2026-09-23 (real-device screenshot vs. the reference screenshot,
/// "the best seller should have been updated like this by the admin"): the
/// first cut of this tile rendered one flat image, not the reference's 2x2
/// grid — see [MobileBestsellerItem.thumbnails] doc comment.
class _AdminBestsellerTile extends StatelessWidget {
  const _AdminBestsellerTile({required this.item, required this.onTap});

  final MobileBestsellerItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnails = item.thumbnails ?? const <String>[];
    final previewCount = thumbnails.length < 4 ? thumbnails.length : 4;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: previewCount == 0
                      ? const Center(
                          child: Icon(
                            Icons.local_grocery_store_rounded,
                            color: AppColors.groceryGreenDark,
                            size: 32,
                          ),
                        )
                      : GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 4,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemBuilder: (context, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              color: Colors.white,
                              child: AppRemoteImage(
                                imageUrl: thumbnails[i % previewCount],
                                title: item.title,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                ),
                if (item.productCount > 0)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        '+${item.productCount} more',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// One "Book Again" reorder tile: a square thumbnail of a real prior-booking
/// service/grocery item plus its name — deliberately minimal (no price, no
/// rating) since this is a quick-glance shortcut back to something already
/// booked before, not another full product listing.
class _BookAgainTile extends ConsumerWidget {
  const _BookAgainTile({required this.service, required this.width});

  final ServiceItem service;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGrocery = service.flowType == CatalogFlowType.grocery;
    // Rewritten 2026-09-19 — the previous fix only patched the tile's own
    // thumbnail image; tapping through still passed the booking's own
    // echoed item (from cart_data) as `extra`, and ServiceDetailScreen
    // skips its network fetch whenever `extra` is present (see
    // service_detail_screen.dart's `initialService` check). Cart_data is
    // schemaless and, in practice, is frequently missing far more than
    // just the image — description, "What's Included", price accuracy,
    // categoryId (needed for the Related Items strip) — so the detail
    // page was rendering an incomplete/stale snapshot instead of the real
    // catalog record. Fixed properly here: look the same service id up in
    // whichever live catalog strip is already loaded (fetched for
    // Essential Picks / Recommended Services anyway, so this is free) and
    // prefer that FULL, current record over the echoed one for
    // everything — thumbnail, navigation slug, and the `extra` passed
    // through.
    final live = isGrocery
        ? ref.watch(groceryProduceProvider).valueOrNull
        : ref.watch(popularServicesProvider).valueOrNull;
    final liveMatch = live?.where((s) => s.id == service.id).firstOrNull;
    final displayService = liveMatch ?? service;
    final displayImageUrl = displayService.imageUrl;
    final accent = isGrocery ? AppColors.groceryGreen : AppColors.serviceBlue;

    // A real slug (from the live catalog match, or from the echoed item
    // if it happened to carry one) lets ServiceDetailScreen fetch the
    // full record itself — the right fix, since it's guaranteed current.
    // Only when NEITHER has a real slug (the service was perhaps removed
    // from the live catalog since this booking was made) do we fall back
    // to passing whatever record we have as `extra`, which skips the
    // fetch — better an old snapshot than a broken "Page Not Found".
    final hasRealSlug = displayService.slug.isNotEmpty;
    final routeSlug =
        hasRealSlug ? displayService.slug : 'svc-${service.id}';

    return GestureDetector(
      onTap: () => context.push(
        '/services/$routeSlug',
        extra: hasRealSlug ? null : displayService,
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: AppRemoteImage(
                  imageUrl: displayImageUrl,
                  rawPath: displayImageUrl,
                  title: displayService.title,
                  categoryName: displayService.categoryName,
                  slug: displayService.slug,
                  semanticIcon: ImageUrlHelper.mapCategoryIcon(
                      displayService.categoryName, displayService.slug),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              displayService.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Book Again',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Why Choose SEVO item badge
class _WhyChooseItem extends StatelessWidget {
  const _WhyChooseItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;

  /// Added 2026-09-19: used to hardcode AppColors.primary/primaryLight
  /// (the app's general brand green) regardless of which mode's trust
  /// section this badge was in — now themed per mode ([HomeFlowTheme]'s
  /// accent) so Groceries mode's trust row and Services mode's trust row
  /// are visually distinct too, not just their content.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AppColors.navy,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

/// Home screen's "Offers & Coupons" card — shows the real top active
/// coupon from GET /customer/coupons/ (the same live coupon list the
/// checkout coupon sheet uses), and renders nothing at all when the admin
/// currently has no active coupons, rather than a fabricated always-on
/// promo. See coupon_repository.dart's doc comment for the backend detail.
class _LiveCouponBanner extends ConsumerWidget {
  const _LiveCouponBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponsAsync = ref.watch(availableCouponsProvider);
    final coupon = couponsAsync.valueOrNull?.firstOrNull;
    if (coupon == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => context.push('/categories'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.chipGreenBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        coupon.code,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.chipGreenText,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      coupon.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      coupon.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Content for one advertisement banner slide. Falls back to this static
/// marketing copy whenever the live homepage CMS (settings_hub's
/// offers.items — see homepage_repository.dart) has nothing published yet,
/// so the carousel is never blank; never touches the carousel widget itself.
///
/// Fixed 2026-09-01: `route` used to be a hardcoded category slug guessed
/// to exist ('ac_appliance', 'electrician_plumbing_carpentry',
/// 'deep-cleaning', 'vegetables_groceries') — those are the same
/// hand-enumerated category names flagged elsewhere as the "hardcoded
/// categories" problem, and if the admin renames or removes that category
/// in the Service Catalog portal, tapping the card pushed a slug that no
/// longer exists anywhere. `routeKeywords` replaces that: at tap time,
/// _PromoBannerSlide looks up the LIVE category list and matches by these
/// keywords, falling back to the "Browse Services" grid (never a guessed,
/// possibly-dead slug) if nothing currently live matches.
class _PromoBanner {
  const _PromoBanner({
    required this.eyebrow,
    required this.title,
    required this.ctaLabel,
    required this.routeKeywords,
    required this.icon,
    required this.gradientColors,
    required this.accentColor,
    this.imageUrl,
    this.mediaType = 'image',
  });

  final String eyebrow;
  final String title;
  final String ctaLabel;
  final List<String> routeKeywords;
  final IconData icon;
  final List<Color> gradientColors;
  final Color accentColor;

  /// The real admin-uploaded banner image OR video (HomeOffer.imageUrl)
  /// for this slide, when one exists. Null for the static fallback
  /// templates below, and null for a live offer that hasn't had media
  /// uploaded yet — _PromoBannerSlide keeps rendering the gradient/icon/
  /// text design in that case so the carousel is never blank.
  final String? imageUrl;

  /// Added 2026-09-21: 'image' or 'video' — which kind of asset [imageUrl]
  /// points at (see HomeOffer.mediaType / BannerMedia).
  final String mediaType;
}

// Blue gradients = service bookings, Green gradient = grocery bookings —
// same flow-accent rule applied across catalog, checkout & bookings.
const _promoBanners = <_PromoBanner>[
  _PromoBanner(
    eyebrow: 'Reliable. Fast. SEVO.',
    title: 'Quality services\nat your doorstep',
    ctaLabel: 'Book Now',
    routeKeywords: ['appliance', 'ac'],
    icon: Icons.engineering_rounded,
    gradientColors: [Color(0xFF0D253A), Color(0xFF1D4ED8)],
    accentColor: Color(0xFF93C5FD),
  ),
  _PromoBanner(
    eyebrow: 'Farm-Fresh, Same Day',
    title: 'Groceries delivered\nfast & fresh',
    ctaLabel: 'Shop Now',
    routeKeywords: ['vegetable', 'grocer', 'farm', 'produce'],
    icon: Icons.eco_rounded,
    gradientColors: [Color(0xFF14532D), Color(0xFF16A34A)],
    accentColor: Color(0xFF86EFAC),
  ),
  _PromoBanner(
    eyebrow: 'Certified Professionals',
    title: 'Electrician, plumbing\n& carpentry, on call',
    ctaLabel: 'Book Now',
    routeKeywords: ['electric', 'plumb', 'carpent'],
    icon: Icons.build_rounded,
    gradientColors: [Color(0xFF1E3A5F), Color(0xFF2563EB)],
    accentColor: Color(0xFF93C5FD),
  ),
  _PromoBanner(
    eyebrow: 'Spotless Guarantee',
    title: 'Deep cleaning for\nevery corner of home',
    ctaLabel: 'Book Now',
    routeKeywords: ['clean'],
    icon: Icons.cleaning_services_rounded,
    gradientColors: [Color(0xFF0D253A), Color(0xFF1D4ED8)],
    accentColor: Color(0xFF93C5FD),
  ),
];

/// Added 2026-09-19 as part of the two-themed-home-pages redesign: the same
/// grocery keyword set the static templates already use for their own
/// `routeKeywords`, reused here to classify which static templates (and,
/// by matching their tag/title text, which real admin-uploaded offers)
/// belong in Groceries mode's carousel vs Services mode's. An admin offer
/// whose text matches neither set is treated as flow-neutral and shown in
/// both — there's no per-offer "flow" field in the backend to sort it by,
/// so hiding it from one mode on a guess would risk hiding a real
/// promotion the admin meant everyone to see.
const _groceryPromoKeywords = ['vegetable', 'grocer', 'farm', 'produce', 'fresh'];

bool _looksGroceryText(String text) {
  final lower = text.toLowerCase();
  return _groceryPromoKeywords.any(lower.contains);
}

bool _looksGroceryKeywords(List<String> routeKeywords) =>
    routeKeywords.any((k) => _groceryPromoKeywords.contains(k));

/// Auto-sliding advertisement banner shown on Home below the search bar.
/// Advances one slide every 5 seconds; also swipeable by hand, and the
/// auto-timer resets on manual swipe so it doesn't fight the user.
///
/// Fixed 2026-09-16: the slide copy (eyebrow/headline/CTA) used to be a
/// fully static, hand-written `_promoBanners` list — this file's own
/// earlier comment already flagged that as temporary ("swap this list for
/// a live promotions/banners provider whenever the backend exposes one").
/// That provider now exists (settings_hub's homepage CMS, GET
/// /api/settings/homepage/, offers.items) — when the admin has published
/// real offers there, this carousel shows THAT copy instead, cycling
/// through the same gradient/icon visual templates below. It still falls
/// back to the static copy whenever the live config is loading, errored,
/// or has no offers configured, so the carousel is never blank.
class _PromoBannerCarousel extends ConsumerStatefulWidget {
  const _PromoBannerCarousel({required this.mode, required this.aspectRatio});

  /// Added 2026-09-19: which mode's carousel this is, so it shows only the
  /// grocery-flavored static template (plus grocery-matching real offers)
  /// in Groceries mode, and only the service-flavored ones in Services
  /// mode — part of making the two "home pages" actually feel separate.
  final HomeFlowMode mode;

  /// Added 2026-09-19 — from [HomeFlowTheme.bannerAspectRatio]: each mode
  /// now gets its own banner shape instead of one ratio shared by both.
  final double aspectRatio;

  @override
  ConsumerState<_PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends ConsumerState<_PromoBannerCarousel> {
  late final PageController _pageController;
  Timer? _autoSlideTimer;
  int _currentPage = 0;
  int _slideCount = _promoBanners.length;

  @override
  void initState() {
    super.initState();
    // Changed 2026-09-19 per explicit request ("occupy the entire width of
    // the user mobile screen") — was 0.88 for a peeking-neighbor-card look;
    // now a full 1.0 so each banner spans the whole device width edge-to
    // -edge, like a real ad banner strip rather than an inset carousel card.
    _pageController = PageController(viewportFraction: 1.0);
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pageController.hasClients || _slideCount == 0) return;
      final next = (_currentPage + 1) % _slideCount;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// Real admin offers merged onto the static gradient/icon templates
  /// (cycled by index so there's always a visual regardless of how many
  /// offers the admin has published).
  ///
  /// CHANGED 2026-09-21 per explicit request ("it shows the older
  /// templete/promo banner insteas og skeleton loading so remove those
  /// predefault banners and all"): this used to return [templates]
  /// unchanged whenever there were no live offers — which is exactly what
  /// showed during homepageConfigProvider's brief initial-load window (no
  /// live offers yet because nothing has loaded), reading as stale
  /// hardcoded content instead of a loading state. That load-in-progress
  /// case is now handled separately in build() with a real skeleton, and
  /// this returns an empty list whenever there are no live offers for this
  /// mode — [templates] now only supplies the gradient/icon/color visual
  /// shell for a real admin offer, never content on its own. See build()'s
  /// skeleton/hidden-carousel handling right after this is called.
  List<_PromoBanner> _effectiveBanners(
    List<HomeOffer> liveOffers,
    List<_PromoBanner> templates,
  ) {
    if (liveOffers.isEmpty || templates.isEmpty) return const [];
    return List.generate(liveOffers.length, (i) {
      final offer = liveOffers[i];
      final template = templates[i % templates.length];
      final headline = [
        if (offer.discount.isNotEmpty) offer.discount,
        offer.title,
      ].join('\n');
      return _PromoBanner(
        eyebrow: offer.tag.isNotEmpty ? offer.tag : template.eyebrow,
        title: headline.isNotEmpty ? headline : template.title,
        ctaLabel: offer.cta.replaceAll('→', '').trim().isNotEmpty
            ? offer.cta.replaceAll('→', '').trim()
            : template.ctaLabel,
        routeKeywords: template.routeKeywords,
        icon: template.icon,
        gradientColors: template.gradientColors,
        accentColor: template.accentColor,
        imageUrl: offer.imageUrl,
        mediaType: offer.mediaType,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final homepageConfigAsync = ref.watch(homepageConfigProvider);
    final homepageConfig = homepageConfigAsync.valueOrNull;
    // Fixed 2026-09-17 per explicit request ("add a side section 'Mobile'
    // ... give the access to upload the banners"): the admin's new
    // mobile-only banner uploads now take priority over the web's
    // "Promotional Offers" section for this carousel, falling back to
    // `offers` (previous behavior) and then the static templates so the
    // carousel is never blank at any stage of adoption.
    // Fixed 2026-09-19 per explicit request ("i want separate banner for
    // mobile application even separate for services and groceries...
    // give access to admin panel to update dynamically"): the admin's
    // "Mobile App ▸ App Banners" tab now has a real "Show On" field
    // (services / groceries / both — HomePageCustomizerPage.jsx) instead
    // of the earlier keyword-guess-from-the-link workaround. `title` still
    // carries the link too, purely so the keyword-guess fallback below
    // still works for any banner saved before this field existed.
    final liveOffers = (homepageConfig?.mobileBanners.isNotEmpty ?? false)
        ? homepageConfig!.mobileBanners
              .map((m) => HomeOffer(
                    id: m.id,
                    tag: '',
                    discount: '',
                    title: m.link ?? '',
                    cta: '',
                    imageUrl: m.imageUrl,
                    link: m.link,
                    flow: m.flow,
                    mediaType: m.mediaType,
                  ))
              .toList()
        : homepageConfig?.offers ?? const [];

    // Added 2026-09-19: mode-filter both the static templates and the real
    // admin offers, so Groceries mode's carousel never shows a service
    // -flavored slide (or vice versa). An offer/template that doesn't
    // clearly match either keyword set is shown in both — see
    // _looksGroceryText's doc comment for why.
    final modeTemplates = _promoBanners
        .where((t) => _looksGroceryKeywords(t.routeKeywords) ==
            (widget.mode == HomeFlowMode.groceries))
        .toList();
    final modeOffers = liveOffers.where((o) {
      // The admin's explicit "Show On" choice always wins when set — no
      // guessing needed. Only falls through to the keyword guess below for
      // items with no flow set at all (the web `offers` section, or a
      // mobile banner/ad saved before this field existed).
      if (o.flow == 'services') return widget.mode == HomeFlowMode.services;
      if (o.flow == 'groceries') return widget.mode == HomeFlowMode.groceries;

      final text = '${o.tag} ${o.title}';
      if (text.trim().isEmpty) return true;
      final isGroceryOffer = _looksGroceryText(text);
      final isServiceOffer = _promoBanners
          .where((t) => !_looksGroceryKeywords(t.routeKeywords))
          .any((t) => t.routeKeywords.any((k) => text.toLowerCase().contains(k)));
      if (isGroceryOffer && !isServiceOffer) {
        return widget.mode == HomeFlowMode.groceries;
      }
      if (isServiceOffer && !isGroceryOffer) {
        return widget.mode == HomeFlowMode.services;
      }
      return true;
    }).toList();

    final banners = _effectiveBanners(modeOffers, modeTemplates);
    _slideCount = banners.length;
    if (_currentPage >= _slideCount) _currentPage = 0;

    // Added 2026-09-21 alongside the _effectiveBanners change above: while
    // homepageConfigProvider is still on its very first fetch (no cached
    // value yet at all), show a real loading skeleton instead of any
    // banner content — this is the exact window that used to flash the
    // hardcoded static templates.
    if (homepageConfigAsync.isLoading && homepageConfig == null) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: const ShimmerCard(borderRadius: 0),
      );
    }

    // Loaded, but genuinely no admin banner configured for this mode —
    // per the same request, nothing renders here at all rather than
    // falling back to a hardcoded template ad.
    if (banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Fixed 2026-08-27: originally set to a literal 9:16 (~1080×1920)
        // portrait ratio per the earlier spec, via AspectRatio rather than
        // a guessed fixed height so it can never overflow. Against the
        // Amazon home screen supplied as a reference, a pure 9:16 single
        // full-width card reads noticeably taller/heavier than that
        // reference's promo card. Kept the AspectRatio approach (still
        // exactly right at any screen width, never a guessed height that
        // clips or overflows) but eased the ratio to ~0.66 — portrait, but
        // closer to what the reference actually shows once you account for
        // its card only occupying part of the screen width via peeking.
        //
        // Shortened further 2026-09-16 per explicit request ("resize those
        // banners little bit shorter length") and to actually fit the real
        // admin-uploaded banner images now rendered here (see
        // _PromoBannerSlide below) — the reference web app's own
        // "Promotional Offers Row" renders each admin banner at a 4:3
        // (`aspect-[4/3]`) shape, not a tall portrait card, since a real ad
        // banner is photographed/exported landscape-ish, not portrait.
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: PageView.builder(
            controller: _pageController,
            itemCount: banners.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              // A manual swipe shouldn't fight the timer — restart the
              // 5-second countdown from the slide the user just landed on.
              _startAutoSlide();
            },
            // No peek-gap padding anymore — full-bleed, edge-to-edge.
            // Fixed 2026-09-21 alongside the video-banner autoplay report:
            // this had no key at all, so Flutter's default (type + slot)
            // reconciliation could reuse a slide's Element/State across a
            // rebuild even when the underlying banner at that index had
            // actually changed (or vice versa) — for a video banner that
            // meant its BannerMedia/VideoPlayerController state could get
            // silently kept or torn down independent of whether the real
            // content changed. A key derived from the banner's own image
            // URL (falling back to its title, which is always unique
            // enough here) makes identity explicit and deterministic.
            itemBuilder: (context, index) {
              final banner = banners[index];
              return _PromoBannerSlide(
                key: ValueKey(banner.imageUrl ?? banner.title),
                banner: banner,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(banners.length, (index) {
            final isActive = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// A single extra promotional/ad card, admin-managed from "Mobile App ▸
/// Advertisement" — added 2026-09-17 per explicit request ("add a side
/// section 'Mobile' ... give the access to upload the banners,
/// advertisement, top cards"). Renders nothing when the admin hasn't
/// configured (or has disabled) an ad, rather than showing a placeholder.
///
/// [mode]-matched 2026-09-19 per explicit request ("this too seperate to
/// both services and grocery... give access to admin panel to update
/// dynamically"): picks the first ad the admin explicitly set to this
/// mode via the "Mobile App ▸ Advertisement" tab's "Show On" field
/// (services / groceries / both). Falls back to a `link`-keyword guess,
/// then to the first ad with neither, for any ad saved before this field
/// existed — so nothing already published silently disappears.
class _MobileAdCard extends ConsumerWidget {
  const _MobileAdCard({required this.mode});

  final HomeFlowMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads =
        ref.watch(homepageConfigProvider).valueOrNull?.mobileAds ?? const [];
    if (ads.isEmpty) return const SizedBox.shrink();

    final wantsGrocery = mode == HomeFlowMode.groceries;
    final explicitMatch = ads.where((a) {
      if (a.flow == 'services') return !wantsGrocery;
      if (a.flow == 'groceries') return wantsGrocery;
      return false;
    }).toList();
    final keywordMatch = ads.where((a) {
      if (a.flow != null) return false; // already covered/excluded above
      final link = (a.link ?? '').toLowerCase();
      if (link.isEmpty) return false;
      final isGrocery = _groceryPromoKeywords.any(link.contains);
      return isGrocery == wantsGrocery;
    }).toList();
    final matched = explicitMatch.isNotEmpty ? explicitMatch : keywordMatch;
    final ad = matched.isNotEmpty ? matched.first : ads.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: GestureDetector(
        onTap: () {
          // Fixed 2026-09-21 — root cause of "groceries and vegetables also
          // redirect to the service categories": this unconditionally
          // pushed '/categories' (the SERVICES grid) no matter which ad was
          // actually showing, so a Groceries-mode ad landed the customer on
          // the Services listing instead of Groceries. `wantsGrocery` above
          // already tells us which mode this card is showing for (it's what
          // picked `ad` in the first place) — route to the live grocery
          // category when that's the case, and only fall back to the
          // services grid otherwise. Still never a guessed/dead slug: it
          // reads the real, currently-active category list, same as
          // _PromoBannerSlide._handleTap above.
          if (wantsGrocery) {
            final liveCategories =
                ref.read(categoriesProvider).valueOrNull ?? const [];
            final groceryCategory = liveCategories
                .where((c) => c.isActive && c.flowType == CatalogFlowType.grocery)
                .firstOrNull;
            if (groceryCategory != null) {
              context.push('/categories/${groceryCategory.slug}', extra: groceryCategory);
              return;
            }
          }
          context.push('/categories');
        },
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: BannerMedia(
              url: ad.imageUrl,
              mediaType: ad.mediaType,
              title: 'Advertisement',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoBannerSlide extends ConsumerWidget {
  const _PromoBannerSlide({super.key, required this.banner});

  final _PromoBanner banner;

  // Resolves this banner's tap destination against the LIVE, admin-managed
  // category list — never a hardcoded slug. Falls back to the full
  // "Browse Services" grid (a route that always exists) when no currently
  // -active category matches, e.g. the admin hasn't created that category
  // yet or has since removed/renamed it.
  void _handleTap(BuildContext context, List<Category> liveCategories) {
    for (final category in liveCategories) {
      if (!category.isActive) continue;
      final haystack = '${category.slug} ${category.name}'.toLowerCase();
      if (banner.routeKeywords.any((k) => haystack.contains(k))) {
        context.push('/categories/${category.slug}', extra: category);
        return;
      }
    }
    context.push('/categories');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveCategories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    // Fixed 2026-08-27: this slide used to be laid out for a wide,
    // landscape-ish banner — text on the left with a decorative icon
    // absolutely positioned on the right. Now that the carousel is a
    // taller portrait shape, that old layout would leave most of the
    // height empty. Rebuilt as a plain top-to-bottom Column with a Spacer instead
    // of Positioned/Stack: a Column with a flexible Spacer can never
    // overflow its parent regardless of content length or text-scale
    // setting (the fixed-size children just get less Spacer, never a
    // negative one), which is the actual fix for "bottom being somewhat
    // bigger" — not a scroll-view band-aid over a layout that could still
    // overflow.
    // Real admin-uploaded banner image: rendered exactly like the reference
    // web app's offer cards — the photo IS the banner, full-bleed, tappable,
    // with no code-drawn eyebrow/title/icon/CTA text stacked on top of it
    // (see LandingPage.jsx's own comment: "each card is a single
    // admin-uploaded banner image (like a real ad), no code-drawn
    // discount/countdown/coupon text on top of it"). Falls back to the
    // gradient/icon/text design below whenever this specific offer has no
    // image yet, so the carousel is never a blank/broken tile.
    if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty) {
      return GestureDetector(
        onTap: () => _handleTap(context, liveCategories),
        child: Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: BannerMedia(
            url: banner.imageUrl,
            mediaType: banner.mediaType,
            title: banner.title,
            semanticIcon: banner.icon,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Fixed 2026-09-19 — root cause of the logged "RenderFlex overflowed by
    // 123 pixels" crash: this Column was designed for the carousel's OLD
    // tall/portrait banner shape (a 138px icon circle + two Spacers +
    // 3-line title all stacked vertically). When bannerAspectRatio was
    // widened/shortened earlier this session ("reduce the height...
    // occupy the entire width"), the available height shrank to ~150px —
    // far too little for that fixed vertical content to fit even with
    // both Spacers collapsed to zero, which is exactly the overflow the
    // logs caught. Rebuilt as a horizontal Row (icon beside text) to
    // actually fit a short, wide banner shape, with no Spacer relying on
    // height it no longer has.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: banner.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: banner.accentColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  banner.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _handleTap(context, liveCategories),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          banner.ctaLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: AppColors.navy,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: Icon(
              banner.icon,
              size: 34,
              color: banner.accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

