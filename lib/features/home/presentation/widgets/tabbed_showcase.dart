import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_remote_image.dart';
import '../../../catalog/data/marketplace_catalog_repository.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../data/home_studio_repository.dart';
import 'studio_title.dart';
import 'home_studio_block.dart' show openStudioDestination;

/// Home Studio "Tabbed Showcase": a themed heading (title + emoji + subtitle),
/// a row of category tabs, a horizontally scrolling product / service rail for
/// the selected tab, and a "See All" button. Everything is admin-driven
/// (settings.tabs, colours, labels); products and services are always live.
class TabbedShowcase extends ConsumerStatefulWidget {
  const TabbedShowcase({super.key, required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  ConsumerState<TabbedShowcase> createState() => _TabbedShowcaseState();
}

Color _hex(dynamic raw, Color fallback) {
  final h = (raw ?? '').toString().trim().replaceAll('#', '');
  if (h.length != 6 && h.length != 8) return fallback;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return fallback;
  return Color(h.length == 6 ? (0xFF000000 | v) : v);
}

String _money(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

class _TabbedShowcaseState extends ConsumerState<TabbedShowcase> {
  int _index = 0;

  List<Map<String, dynamic>> get _tabs {
    final raw = widget.section.settings['tabs'];
    if (raw is! List) return const [];
    return [
      for (final t in raw)
        if (t is Map && t['enabled'] != false && (t['label'] ?? '').toString().trim().isNotEmpty)
          Map<String, dynamic>.from(t),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final st = section.settings;
    final tabs = _tabs;
    if (tabs.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, tabs.length - 1).toInt();
    final tab = tabs[index];

    final accent = _hex(st['accent_color'], const Color(0xFF9A4A0F));
    final bg = _hex(st['background'], Colors.transparent);
    final title = section.title.isNotEmpty ? section.title : 'Specials';
    final emoji = (st['title_emoji'] ?? '').toString().trim();
    final subtitle = (st['subtitle'] ?? '').toString().trim();
    final seeAllLabel = (st['see_all_label'] ?? '').toString().trim().isEmpty ? 'See All' : st['see_all_label'].toString().trim();
    final showSeeAll = section.flag('see_all', fallback: true);
    final isServices = widget.pageKey != 'grocery_home';
    final limit = section.intSetting('items_per_tab', 8).clamp(1, 20).toInt();

    StudioDestination seeAllDest() {
      final custom = StudioDestination.fromJson(st['see_all_destination']);
      if (custom.type != 'none') return custom;
      final slug = (tab['category_slug'] ?? '').toString();
      return slug.isEmpty ? const StudioDestination() : StudioDestination(type: 'category', value: slug, slug: slug);
    }

    final dest = seeAllDest();

    return Container(
      color: bg,
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Flexible(
                  child: StudioTitle(
                    text: title,
                    imageUrl: section.titleImage,
                    font: section.titleFont,
                    imageHeight: 44,
                    style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w900, color: accent),
                  ),
                ),
                if (emoji.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                ],
              ],
            ),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Flexible(
                    child: Text(subtitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Container(height: 1, color: accent.withOpacity(0.25))),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Tabs
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: accent.withOpacity(0.25)))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _index = i),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: i == index ? Colors.white.withOpacity(0.85) : Colors.transparent,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          border: i == index
                              ? Border(
                                  top: BorderSide(color: accent),
                                  left: BorderSide(color: accent),
                                  right: BorderSide(color: accent),
                                )
                              : null,
                        ),
                        child: Text(
                          tabs[i]['label'].toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                            color: i == index ? accent : const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TabRail(
            key: ValueKey('tab-rail-${section.id}-$index'),
            section: section,
            tab: tab,
            isServices: isServices,
            limit: limit,
            accent: accent,
          ),
          if (showSeeAll && dest.type != 'none')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => openStudioDestination(context, dest, widget.pageKey),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF2F6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDDE3EA)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(seeAllLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_right, size: 22, color: Color(0xFF1A1A1A)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabRail extends ConsumerWidget {
  const _TabRail({super.key, required this.section, required this.tab, required this.isServices, required this.limit, required this.accent});

  final StudioSection section;
  final Map<String, dynamic> tab;
  final bool isServices;
  final int limit;
  final Color accent;

  static const double _railHeight = 246;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryId = int.tryParse((tab['category_id'] ?? '').toString());
    final slug = (tab['category_slug'] ?? '').toString();

    Widget rail(List<ServiceItem> items) {
      if (items.isEmpty) {
        return const SizedBox(
          height: 90,
          child: Center(child: Text('Nothing here yet', style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)))),
        );
      }
      final shown = items.take(limit).toList();
      return SizedBox(
        height: _railHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: shown.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _ShowcaseCard(
            item: shown[i],
            isServices: isServices,
            showImage: section.flag('show_image', fallback: true),
            showName: section.flag('show_name', fallback: true),
            showPrice: section.flag('show_price', fallback: true),
            showDiscount: section.flag('show_discount', fallback: true),
            showAdd: section.flag('show_add_button', fallback: true),
            showUnit: section.flag('show_unit', fallback: true),
          ),
        ),
      );
    }

    final loading = SizedBox(
      height: _railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, __) => Container(
          width: _ShowcaseCard.width,
          decoration: BoxDecoration(color: const Color(0x14000000), borderRadius: BorderRadius.circular(28)),
        ),
      ),
    );

    if (isServices) {
      if (slug.isEmpty) return const SizedBox.shrink();
      final async = ref.watch(categoryServicesProvider(CategoryServicesParam(categoryId: categoryId, categorySlug: slug)));
      return async.when(
        data: (items) => rail(items),
        loading: () => loading,
        error: (_, __) => const SizedBox.shrink(),
      );
    }

    if (categoryId == null) return const SizedBox.shrink();
    final async = ref.watch(marketplaceMergedProductsProvider('$categoryId'));
    return async.when(
      data: (products) => rail([for (final p in products) p.toServiceItem()]),
      loading: () => loading,
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ShowcaseCard extends StatelessWidget {
  const _ShowcaseCard({
    required this.item,
    required this.isServices,
    this.showImage = true,
    this.showName = true,
    this.showPrice = true,
    this.showDiscount = true,
    this.showAdd = true,
    this.showUnit = true,
  });

  final ServiceItem item;
  final bool isServices;
  final bool showImage;
  final bool showName;
  final bool showPrice;
  final bool showDiscount;
  final bool showAdd;
  final bool showUnit;

  static const double width = 172;
  static const double height = 224;

  @override
  Widget build(BuildContext context) {
    final slug = item.slug.isNotEmpty ? item.slug : 'svc-${item.id}';
    final unit = (item.unit ?? '').trim();
    final pack = (isServices || !showUnit) ? '' : unit;
    final pct = showDiscount ? item.discountPercent : null;

    // The card has a fixed height, so it ignores the phone's font scaling.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.0,
      child: GestureDetector(
        onTap: () => context.push(isServices ? '/services/$slug' : '/products/$slug', extra: item),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              // Image with the offer % and pack size laid over it (Add sits beside the price).
              SizedBox(
                height: showImage ? 122 : 30,
                width: double.infinity,
                child: Stack(
                  children: [
                    if (showImage)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: (item.imageUrl ?? '').isEmpty
                            ? const Center(child: Icon(Icons.image_outlined, size: 40, color: Color(0xFF9CA3AF)))
                            : AppRemoteImage(imageUrl: item.imageUrl!, fit: BoxFit.cover),
                      ),
                    ),
                    if (pct != null && pct > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE11D48),
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(18), bottomRight: Radius.circular(12)),
                          ),
                          child: Text('$pct% OFF', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                      ),
                    if (pack.isNotEmpty)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 54),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(10)),
                          child: Text(pack, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (showName)
              SizedBox(
                height: 34,
                child: Center(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.25, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                  ),
                ),
              ),
              const Spacer(),
              if (showPrice || showAdd)
              Row(
                children: [
                  Expanded(
                    child: showPrice
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '₹${_money(item.effectivePrice.toDouble())}',
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
                                  ),
                                  if (showDiscount && item.hasDiscount) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '₹${_money(item.price.toDouble())}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), decoration: TextDecoration.lineThrough),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (showAdd)
                    isServices
                        ? GestureDetector(
                            onTap: () => context.push('/services/$slug', extra: item),
                            child: Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(18)),
                              child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                            ),
                          )
                        : QuickAddControl(service: item),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
