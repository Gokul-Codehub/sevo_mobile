import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/navigation/admin_link_resolver.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/banner_media.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../catalog/data/marketplace_catalog_repository.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../data/home_studio_repository.dart';
import '../../data/homepage_repository.dart';
import '../../domain/grocery_section_layout.dart';
import 'grocery_section_layouts.dart';

const _kGroceryPage = 'grocery_home';

/// The part of Home that Sevo Home Studio controls (everything under the
/// search bar and rotating greeting: hero video, banners, rails …).
///
/// While the page loads it reserves the banner height so nothing jumps.
/// Whenever Studio has nothing to show — flag off, nothing published,
/// network failure with no cached copy — it renders [fallback], which is the
/// exact legacy layout, so Home can never end up blank.
class HomeStudioBlock extends ConsumerWidget {
  const HomeStudioBlock({
    super.key,
    required this.pageKey,
    required this.aspectRatio,
    required this.fallback,
  });

  final String pageKey;
  final double aspectRatio;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeStudioPageProvider(pageKey));
    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(aspectRatio: aspectRatio, child: const ShimmerBox(borderRadius: 0)),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: ShimmerBox(height: 84, borderRadius: 14)),
                SizedBox(width: 10),
                Expanded(child: ShimmerBox(height: 84, borderRadius: 14)),
                SizedBox(width: 10),
                Expanded(child: ShimmerBox(height: 84, borderRadius: 14)),
              ],
            ),
          ),
        ],
      ),
      error: (_, __) => fallback,
      data: (page) {
        if (page == null || page.useLegacy || page.sections.isEmpty) return fallback;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in page.sections) ...[
              StudioSectionView(key: ValueKey(section.id), section: section, pageKey: pageKey),
            ],
          ],
        );
      },
    );
  }
}

/// Slivers for the area BELOW the wave banner, or `null` when Studio has
/// nothing to show (flag off, nothing published, still loading with no cache,
/// network failure) so the caller renders the legacy sections instead.
List<Widget>? homeStudioContentSlivers(WidgetRef ref, String pageKey, {Widget? footer}) {
  final page = ref.watch(homeStudioPageProvider(pageKey)).valueOrNull;
  if (page == null || page.useLegacy || page.sections.isEmpty) return null;
  return [
    SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in page.sections)
            StudioSectionView(key: ValueKey(section.id), section: section, pageKey: pageKey),
        ],
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 14)),
    if (footer != null) SliverToBoxAdapter(child: footer),
  ];
}

// ───────────────────────── destinations ─────────────────────────

void openStudioDestination(BuildContext context, StudioDestination d, String pageKey) {
  final grocery = pageKey == _kGroceryPage;
  final v = d.value;
  switch (d.type) {
    case 'url':
      handleAdminLinkTap(context, v, fallbackPath: '/');
    case 'route':
      handleAdminLinkTap(context, v.startsWith('/') || v.startsWith('http') ? v : '/$v', fallbackPath: '/');
    case 'category':
      final slug = d.slug.isNotEmpty ? d.slug : v;
      if (slug.isEmpty) return;
      context.push(grocery ? '/groceries/seller-hub?category=$slug' : '/categories/$slug');
    case 'product':
      if (v.isNotEmpty) context.push('/products/$v');
    case 'service':
    case 'package':
      if (v.isNotEmpty) context.push('/services/$v');
    case 'collection':
      if (v.isNotEmpty) context.push('/baskets/$v');
    case 'search':
      context.push('/search?mode=${grocery ? 'groceries' : 'services'}${v.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(v)}'}');
    default:
      break; // none / offer: nothing to open
  }
}

/// Home Studio destination -> the raw link string the legacy banner CTA
/// (MobileGrocerySection.bannerCtaLink) already understands.
String _destinationLink(StudioDestination d, {required bool grocery}) {
  final v = d.value;
  switch (d.type) {
    case 'url':
      return v;
    case 'route':
      return v.startsWith('/') || v.startsWith('http') ? v : '/$v';
    case 'category':
      final slug = d.slug.isNotEmpty ? d.slug : v;
      if (slug.isEmpty) return '';
      return grocery ? '/marketplace?category=$slug' : '?category=$slug';
    case 'product':
      return v.isEmpty ? '' : '/products/$v';
    case 'service':
    case 'package':
      return v.isEmpty ? '' : '/services/$v';
    case 'collection':
      return v.isEmpty ? '' : '/baskets/$v';
    case 'search':
      return '/search?mode=${grocery ? 'groceries' : 'services'}${v.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(v)}'}';
    default:
      return '';
  }
}

// ───────────────────────── section dispatcher ─────────────────────────

class StudioSectionView extends ConsumerWidget {
  const StudioSectionView({super.key, required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (section.template) {
      case 'ad_carousel':
      case 'single_banner':
        return _spaced(StudioBannerCarousel(section: section, pageKey: pageKey));
      case 'quick_access_cards':
        return _spaced(_QuickAccessCards(section: section, pageKey: pageKey));
      case 'banner_product_rail':
        return _spaced(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (section.slides.isNotEmpty) StudioBannerCarousel(section: section, pageKey: pageKey),
            if (section.slides.isNotEmpty) const SizedBox(height: 10),
            _GroceryDriven(section: section),
          ],
        ));
      case 'bestseller_tiles':
        return _spaced(_BestsellerTiles(section: section, pageKey: pageKey));
      case 'service_category_grid':
        return _spaced(_ServiceCategoryGrid(section: section, pageKey: pageKey));
      case 'service_collection':
      case 'service_packages':
        return _spaced(_ServiceDriven(section: section));
      default:
        final type = (section.content['type'] ?? '').toString();
        if (type == 'manual_services' || type == 'service_category') {
          return _spaced(_ServiceDriven(section: section));
        }
        // Services page: category rails/grids must resolve against SERVICE
        // categories, never the grocery (Seller Hub) category tree.
        if (pageKey != _kGroceryPage &&
            (type == 'manual_categories' || type == 'all_categories' || type == 'category' || type.isEmpty) &&
            _isCategoryTemplate(section.template)) {
          return _spaced(_ServiceCategoryGrid(
            section: section,
            pageKey: pageKey,
            circular: section.template == 'circular_category_rail',
          ));
        }
        return _spaced(_GroceryDriven(section: section));
    }
  }

  Widget _spaced(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 14), child: child);
}

bool _isCategoryTemplate(String t) =>
    t == 'circular_category_rail' || t == 'category_tile_grid' || t == 'category_grid' || t == 'masonry_category_grid' || t.contains('category');

// ───────────────────────── banners ─────────────────────────

double _aspect(String? key) {
  switch (key) {
    case 'wide':
      return 14 / 5;
    case 'square':
      return 1;
    case 'portrait':
      return 4 / 5;
    default:
      return 2;
  }
}

class StudioBannerCarousel extends StatefulWidget {
  const StudioBannerCarousel({super.key, required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  State<StudioBannerCarousel> createState() => _StudioBannerCarouselState();
}

class _StudioBannerCarouselState extends State<StudioBannerCarousel> {
  late final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  List<StudioSlide> get _slides => widget.section.slides;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  void _startAutoplay() {
    _timer?.cancel();
    final s = widget.section;
    if (_slides.length < 2 || !s.flag('autoplay', fallback: true)) return;
    final seconds = s.intSetting('interval_seconds', 4).clamp(2, 15);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted || !_controller.hasClients) return;
      // Respect the OS "remove animations" setting: still advance, no slide.
      final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      final next = (_index + 1) % _slides.length;
      if (reduce) {
        _controller.jumpToPage(next);
      } else {
        _controller.animateToPage(next, duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) return const SizedBox.shrink();
    // Advertisement Carousel: coverflow style (big centre card, smaller
    // neighbours tucked behind it). Other banner templates are unchanged.
    if (widget.section.template == 'ad_carousel' && _slides.length >= 2) {
      return _StudioCoverflow(key: ValueKey('cf-${widget.section.id}'), section: widget.section, pageKey: widget.pageKey);
    }
    final ratio = _aspect(widget.section.settings['aspect']?.toString());
    final showDots = _slides.length > 1 && widget.section.flag('indicators', fallback: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Edge to edge: the banner uses the phone's full width (no side
        // margins, no rounded corners).
        SizedBox(
          width: double.infinity,
          child: ClipRect(
            child: AspectRatio(
              aspectRatio: ratio,
              child: Listener(
                // A touch pauses autoplay until the next page change.
                onPointerDown: (_) => _timer?.cancel(),
                onPointerUp: (_) => _startAutoplay(),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final slide = _slides[i];
                    return Semantics(
                      button: slide.destination.type != 'none',
                      label: slide.alt.isNotEmpty ? slide.alt : slide.title,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openStudioDestination(context, slide.destination, widget.pageKey),
                        child: BannerMedia(url: slide.imageUrl, title: slide.title.isEmpty ? null : slide.title),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (showDots) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: i == _index ? 18 : 6,
                  decoration: BoxDecoration(
                    color: i == _index ? const Color(0xFF1A1A1A) : const Color(0x551A1A1A),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ───────────────── coverflow ad carousel ─────────────────

/// Advertisement Carousel animation: the centre card is large, the previous /
/// next cards are smaller and sit partly behind it. Swiping or autoplay makes
/// the cards scale and slide over each other. Loops endlessly.
class _StudioCoverflow extends StatefulWidget {
  const _StudioCoverflow({super.key, required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  State<_StudioCoverflow> createState() => _StudioCoverflowState();
}

class _StudioCoverflowState extends State<_StudioCoverflow> {
  static const double _fraction = 0.74; // card width as a share of the screen
  static const double _sideScale = 0.84; // neighbour size relative to centre
  static const double _tuck = 0.16; // how far neighbours slide behind centre

  List<StudioSlide> get _slides => widget.section.slides;
  int get _n => _slides.length;

  late final int _initial = _n * 1000;
  late final PageController _c = PageController(viewportFraction: _fraction, initialPage: _initial);
  late int _cur = _initial;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  void _startAutoplay() {
    _timer?.cancel();
    if (!widget.section.flag('autoplay', fallback: true)) return;
    final seconds = widget.section.intSetting('interval_seconds', 4).clamp(2, 15);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted || !_c.hasClients) return;
      final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduce) {
        _c.jumpToPage(_cur + 1);
      } else {
        _c.nextPage(duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Widget _card(int k, double page, double cardW, double cardH) {
    final signed = k - page;
    final double d = signed.abs().clamp(0.0, 1.0).toDouble();
    final scale = 1 - (1 - _sideScale) * d;
    final dx = signed * cardW - (signed == 0 ? 0 : signed.sign) * _tuck * cardW * d;
    final slide = _slides[k % _n];
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: cardW,
          height: cardH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.15 * (1 - d)), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BannerMedia(url: slide.imageUrl, title: slide.title.isEmpty ? null : slide.title),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Coverflow cards are ~18% taller than the plain banner shape.
    final double ratio = (_aspect(widget.section.settings['aspect']?.toString()) / 1.18).clamp(0.8, 2.4).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cardW = box.maxWidth * _fraction;
            final cardH = cardW / ratio;
            final fogW = (box.maxWidth - cardW) / 2 + box.maxWidth * 0.03;
            return SizedBox(
              height: cardH + 12,
              child: Listener(
                onPointerDown: (_) => _timer?.cancel(),
                onPointerUp: (_) => _startAutoplay(),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) {
                          final page = (_c.hasClients && _c.position.haveDimensions)
                              ? (_c.page ?? _initial.toDouble())
                              : _initial.toDouble();
                          final base = page.round();
                          // Paint farthest first so the centre card is on top.
                          final ks = [for (var k = base - 2; k <= base + 2; k++) k]
                            ..sort((x, y) => (y - page).abs().compareTo((x - page).abs()));
                          return Stack(
                            alignment: Alignment.center,
                            children: [for (final k in ks) _card(k, page, cardW, cardH)],
                          );
                        },
                      ),
                    ),
                    // Soft fog at the far left / right: side cards keep their own
                    // colours but dissolve toward the edges, so the front card
                    // stands out.
                    Positioned(
                      left: 0, top: 0, bottom: 0, width: fogW,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0, top: 0, bottom: 0, width: fogW,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Invisible pages: swipe + tap handling only.
                    Positioned.fill(
                      child: PageView.builder(
                        controller: _c,
                        onPageChanged: (k) => setState(() => _cur = k),
                        itemBuilder: (context, k) => Semantics(
                          button: true,
                          label: _slides[k % _n].alt.isNotEmpty ? _slides[k % _n].alt : _slides[k % _n].title,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (k == _cur) {
                                openStudioDestination(context, _slides[k % _n].destination, widget.pageKey);
                              } else {
                                _c.animateToPage(k, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
                              }
                            },
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ───────────────────────── quick access cards ─────────────────────────

class _QuickAccessCards extends StatelessWidget {
  const _QuickAccessCards({required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  Widget build(BuildContext context) {
    final slides = section.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < slides.length && i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                button: true,
                label: slides[i].alt.isNotEmpty ? slides[i].alt : slides[i].title,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => openStudioDestination(context, slides[i].destination, pageKey),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 40,
                          width: 40,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AppRemoteImage(imageUrl: slides[i].imageUrl, fit: BoxFit.cover),
                          ),
                        ),
                        if (slides[i].title.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            slides[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── product / category templates ─────────────────────────

const _layoutByTemplate = {
  'product_carousel': 'horizontal',
  'bestsellers': 'horizontal',
  'compact_product_list': 'compact_list',
  'quick_add_list': 'quick_add_list',
  'deal_cards': 'deal_cards',
  'featured_hero': 'featured_hero',
  'banner_product_rail': 'horizontal',
  'category_grid': 'category_tile_grid',
  'circular_category_rail': 'circular_category_rail',
};

Map<String, String> _slugMap(dynamic raw) => raw is Map
    ? {for (final e in raw.entries) e.key.toString(): (e.value ?? '').toString()}
    : const {};

List<int> _ints(dynamic raw) => raw is List
    ? raw.map((v) => int.tryParse(v.toString())).whereType<int>().toList()
    : const <int>[];

/// Renders a Studio product/category section with the app's existing
/// grocery section renderer, so cards, add-to-cart and prices behave exactly
/// like the rest of Home (live data, never copied into the page).
class _GroceryDriven extends ConsumerWidget {
  const _GroceryDriven({required this.section});

  final StudioSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = section.template;
    final c = section.content;
    final type = (c['type'] ?? '').toString();

    var categoryIds = <int>[];
    var productIds = <int>[];
    if (type == 'manual_categories') {
      categoryIds = _ints(c['ids']);
    } else if (type == 'all_categories') {
      final tree = ref.watch(marketplaceCategoryTreeProvider).valueOrNull ?? const [];
      categoryIds = [for (final root in tree) root.id];
    } else if (type == 'category') {
      final id = int.tryParse((c['category_id'] ?? '').toString());
      if (id != null) categoryIds = [id];
    } else if (type == 'manual') {
      productIds = _ints(c['ids']);
    } else {
      // Rule-based sources (bestselling, new arrivals …) are not resolved in
      // the app yet — hide rather than show an arbitrary product list.
      debugPrint('[HomeStudio] source "$type" for ${section.template} not supported in the app yet');
      return const SizedBox.shrink();
    }
    if (categoryIds.isEmpty && productIds.isEmpty) return const SizedBox.shrink();

    var layout = _layoutByTemplate[t];
    if (t == 'product_grid') layout = section.settings['columns']?.toString() == '3' ? 'grid' : 'grid_2';
    // "Grocery Section" template = the same 12 layouts as Mobile Grocery Sections.
    if (t == 'grocery_section') layout = (section.settings['layout'] ?? 'horizontal').toString();
    layout ??= 'horizontal';

    final limit = int.tryParse((c['limit'] ?? '').toString()) ?? 10;
    final columns = int.tryParse(section.settings['columns']?.toString() ?? '') ?? 3;

    final mapped = MobileGrocerySection(
      id: section.id,
      title: section.title,
      layout: GrocerySectionLayoutX.fromRaw(layout),
      categoryIds: categoryIds,
      productIds: productIds,
      maxProducts: limit > 0 ? limit : 10,
      configuredMaxProducts: limit > 0 ? limit : null,
      showSeeAll: section.flag('see_all'),
      showProductImage: section.flag('show_image', fallback: true),
      showProductPrice: section.flag('show_price', fallback: true),
      showProductDiscount: section.flag('show_discount', fallback: true),
      showAddButton: section.flag('show_add_button', fallback: true),
      showCategoryImage: section.flag('show_category_image', fallback: true),
      showCategoryName: section.flag('show_category_name', fallback: true),
      showCategoryProductCount: section.flag('show_category_count', fallback: true),
      categoryTileColumns: (columns >= 2 && columns <= 4) ? columns : 3,
      // Banner + Product Rail (Grocery Section template): the banner is the
      // section's slide; subtitle / button text come from its settings.
      bannerImageUrl: (t == 'grocery_section' && section.slides.isNotEmpty) ? section.slides.first.imageUrl : null,
      bannerTitle: (t == 'grocery_section' && section.slides.isNotEmpty) ? section.slides.first.title : '',
      bannerSubtitle: t == 'grocery_section' ? (section.settings['banner_subtitle'] ?? '').toString() : '',
      bannerCtaText: t == 'grocery_section' ? (section.settings['banner_cta_text'] ?? '').toString() : '',
      bannerCtaLink: (t == 'grocery_section' && section.slides.isNotEmpty)
          ? _destinationLink(section.slides.first.destination, grocery: true)
          : '',
    );
    return GrocerySectionResolver(section: mapped);
  }
}

// ───────────────────────── bestseller tiles ─────────────────────────

MarketplaceCategory? _findCategory(List<MarketplaceCategory> nodes, String id) {
  for (final n in nodes) {
    if (n.id.toString() == id) return n;
    final hit = _findCategory(n.children, id);
    if (hit != null) return hit;
  }
  return null;
}

/// Bestsellers: the same tile as the old Mobile Bestsellers (title, 2x2 photo
/// grid, "+N more" badge) but the four photos are the live photos of products
/// the admin picked inside the tile's category, and "+N more" is worked out
/// from the category's real product count.
class _BestsellerTiles extends ConsumerWidget {
  const _BestsellerTiles({required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = section.settings['tiles'];
    final tiles = raw is List
        ? [for (final t in raw) if (t is Map && t['enabled'] != false) Map<String, dynamic>.from(t)]
        : <Map<String, dynamic>>[];
    if (tiles.isEmpty) return const SizedBox.shrink();
    final cols = section.intSetting('columns', 3).clamp(2, 4);
    final tree = ref.watch(marketplaceCategoryTreeProvider).valueOrNull ?? const <MarketplaceCategory>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              section.title.isNotEmpty ? section.title : 'Bestsellers',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tiles.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: cols == 2 ? 0.92 : (cols == 4 ? 0.7 : 0.82),
            ),
            itemBuilder: (context, i) => _BestsellerTileCard(
              key: ValueKey('studio-bestseller-${tiles[i]['id'] ?? i}'),
              tile: tiles[i],
              tree: tree,
              pageKey: pageKey,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestsellerTileCard extends ConsumerWidget {
  const _BestsellerTileCard({super.key, required this.tile, required this.tree, required this.pageKey});

  final Map<String, dynamic> tile;
  final List<MarketplaceCategory> tree;
  final String pageKey;

  void _open(BuildContext context) {
    final dest = StudioDestination.fromJson(tile['destination']);
    if (dest.type != 'none' && dest.type.isNotEmpty) {
      final link = _destinationLink(dest, grocery: pageKey == _kGroceryPage);
      if (link.isNotEmpty) {
        handleAdminLinkTap(context, link, fallbackPath: '/');
        return;
      }
    }
    final slug = (tile['category_slug'] ?? '').toString();
    if (slug.isNotEmpty) context.push('/groceries/seller-hub?category=$slug');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = (tile['title'] ?? '').toString();
    final ids = <String>[
      if (tile['product_ids'] is List)
        for (final v in tile['product_ids'] as List) v.toString(),
    ].where((s) => int.tryParse(s) != null).take(4).toList();
    final products = ids.isEmpty
        ? const <MarketplaceProduct>[]
        : (ref.watch(marketplaceProductsByIdsProvider(ids.join(','))).valueOrNull ?? const <MarketplaceProduct>[]);
    final thumbs = <String>[
      for (final p in products)
        if (p.galleryImages.isNotEmpty) p.galleryImages.first else if ((p.primaryImage ?? '').isNotEmpty) p.primaryImage!,
    ];
    final cat = _findCategory(tree, (tile['category_id'] ?? '').toString());
    final total = cat == null ? 0 : (cat.totalProductCount > 0 ? cat.totalProductCount : cat.productCount);
    final more = total - ids.length;

    return GestureDetector(
      onTap: () => _open(context),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
                  child: thumbs.isEmpty
                      ? const Center(child: Icon(Icons.local_grocery_store_rounded, color: AppColors.groceryGreenDark, size: 32))
                      : GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 4,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 3,
                            mainAxisSpacing: 3,
                          ),
                          itemBuilder: (context, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              color: Colors.white,
                              child: SizedBox.expand(child: AppRemoteImage(imageUrl: thumbs[i % thumbs.length], title: title, fit: BoxFit.cover)),
                            ),
                          ),
                        ),
                ),
                if (more > 0)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4)],
                      ),
                      child: Text('+$more more',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.2),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── service categories ─────────────────────────

class _ServiceCategoryGrid extends ConsumerWidget {
  const _ServiceCategoryGrid({required this.section, required this.pageKey, this.circular = false});

  final StudioSection section;
  final String pageKey;
  final bool circular;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);
    return async.maybeWhen(
      data: (all) {
        final type = (section.content['type'] ?? '').toString();
        final wanted = _ints(section.content['ids']);
        var list = all.where((c) => c.isActive).toList();
        if (type == 'manual_categories' && (wanted.isNotEmpty || _slugMap(section.content['slugs']).isNotEmpty)) {
          // Match by slug first (stable across id spaces), then by id.
          final slugs = _slugMap(section.content['slugs']);
          final picked = <Category>[];
          final rawIds = (section.content['ids'] is List) ? (section.content['ids'] as List) : const [];
          for (final raw in rawIds) {
            final slug = slugs[raw.toString()];
            final hit = (slug != null && slug.isNotEmpty)
                ? list.where((c) => c.slug == slug)
                : list.where((c) => c.id.toString() == raw.toString());
            for (final c in hit) {
              if (!picked.contains(c)) picked.add(c);
            }
          }
          list = picked;
        }
        final limit = int.tryParse((section.content['limit'] ?? '').toString()) ?? 8;
        if (list.length > limit) list = list.sublist(0, limit);
        if (list.isEmpty) return const SizedBox.shrink();
        final cols = (int.tryParse(section.settings['columns']?.toString() ?? '') ?? 3).clamp(2, 4);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(section.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                ),
              if (circular)
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(40),
                        onTap: () => context.push('/categories/${c.slug}'),
                        child: SizedBox(
                          width: 72,
                          child: Column(
                            children: [
                              ClipOval(
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: (c.image ?? '').isNotEmpty
                                      ? AppRemoteImage(imageUrl: c.image!, fit: BoxFit.cover)
                                      : Container(color: Colors.white, child: const Icon(Icons.category_rounded, color: AppColors.navy)),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(c.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.9,
                children: [
                  for (final c in list)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.push('/categories/${c.slug}'),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.divider),
                        ),
                        // Image fills the top 3/4 edge to edge (cover); the
                        // name sits in the bottom 1/4.
                        child: Column(
                          children: [
                            Expanded(
                              flex: 3,
                              child: SizedBox.expand(
                                child: (c.image ?? '').isNotEmpty
                                    ? AppRemoteImage(imageUrl: c.image!, fit: BoxFit.cover)
                                    : Container(
                                        color: const Color(0xFFF1F5F9),
                                        child: const Icon(Icons.category_rounded, color: AppColors.navy),
                                      ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(c.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.15, color: Color(0xFF1A1A1A))),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}


// ───────────────────────── services / packages ─────────────────────────

/// Service Collection, Service Packages and Services-page Bestsellers: the
/// admin's picks (or a whole service category) resolved against the live
/// service catalog, so price and availability are always current.
class _ServiceDriven extends ConsumerWidget {
  const _ServiceDriven({required this.section});

  final StudioSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = section.content;
    final type = (c['type'] ?? '').toString();
    final limit = int.tryParse((c['limit'] ?? '').toString()) ?? 8;

    Widget rail(List<_ServiceEntry> entries) {
      if (entries.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(section.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            ),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => entries[i].item != null
                  ? _ServiceCard(item: entries[i].item!, label: entries[i].label)
                  : _ServiceCardLoader(slug: entries[i].slug, label: entries[i].label),
            ),
          ),
        ],
      );
    }

    if (type == 'service_category') {
      final slug = (c['category_slug'] ?? '').toString();
      if (slug.isEmpty) return const SizedBox.shrink();
      final async = ref.watch(categoryServicesProvider(CategoryServicesParam(categorySlug: slug)));
      return async.maybeWhen(
        data: (items) => rail([for (final i in items.take(limit)) _ServiceEntry(slug: i.slug, item: i)]),
        orElse: () => const SizedBox.shrink(),
      );
    }

    final ids = c['ids'] is List ? (c['ids'] as List).map((e) => e.toString()).toList() : <String>[];
    final slugs = c['slugs'] is Map ? Map<String, dynamic>.from(c['slugs'] as Map) : <String, dynamic>{};
    final labels = c['labels'] is Map ? Map<String, dynamic>.from(c['labels'] as Map) : <String, dynamic>{};
    final entries = <_ServiceEntry>[];
    for (final id in ids) {
      final slug = (slugs[id] ?? '').toString();
      if (slug.isEmpty) continue;
      // Packages share their service's page; show the package name on the card.
      final label = section.template == 'service_packages' ? (labels[id] ?? '').toString() : '';
      entries.add(_ServiceEntry(slug: slug, label: label));
    }
    return rail(entries.take(limit).toList());
  }
}

class _ServiceEntry {
  const _ServiceEntry({required this.slug, this.label = '', this.item});
  final String slug;
  final String label;
  final ServiceItem? item;
}

class _ServiceCardLoader extends ConsumerWidget {
  const _ServiceCardLoader({required this.slug, this.label = ''});
  final String slug;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(serviceDetailProvider(slug));
    return async.when(
      data: (item) => _ServiceCard(item: item, label: label),
      loading: () => Container(
        width: 150,
        decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(14)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.item, this.label = ''});
  final ServiceItem item;
  final String label;

  @override
  Widget build(BuildContext context) {
    final title = label.isNotEmpty ? label : item.title;
    return SizedBox(
      width: 150,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/services/${item.slug}', extra: item),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 100,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: AppRemoteImage(imageUrl: item.imageUrl, fit: BoxFit.cover),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    Text('From ₹${item.effectivePrice.toDouble().toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navy)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
