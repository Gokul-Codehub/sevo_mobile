import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../domain/catalog_models.dart';
import '../../domain/catalog_providers.dart';

/// "Browse Services" screen — every scheduled-service category (AC &
/// Appliances, Electrician/Plumbing/Carpentry, Deep Cleaning, Goods &
/// Transport, Mason, Paintings, etc), excluding the grocery catalog which
/// has its own direct entry point from Home. Reached by tapping the
/// "Services" quick-access tile on Home.
///
/// Redesigned 2026-09-17 per a supplied reference screenshot: an intro
/// hero banner above the grid, and each category tile rebuilt as a
/// photo-top / white-body card (icon badge, subtitle, colored tagline pill)
/// instead of the previous full-bleed image + text-on-gradient tile.
class AllServicesScreen extends ConsumerWidget {
  const AllServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Services'),
      ),
      // Fixed 2026-10-06 ("remove the white space at every card"): every
      // tile used one hardcoded `childAspectRatio: 0.62` regardless of how
      // tall its actual content was. GridView gives each cell that exact
      // fixed height, but _ServiceCategoryTile's white card wraps its
      // content with `mainAxisSize: MainAxisSize.min` and top-aligns it —
      // so whenever the real content was shorter than the guessed 0.62
      // ratio implied, the leftover showed as blank white space at the
      // bottom of the card. Same root cause/fix class as the grocery
      // product card and grid overflow fixes: measure the real cell width
      // via LayoutBuilder and derive the aspect ratio FROM
      // _ServiceCategoryTile's own declared content height
      // (_ServiceCategoryTile.cardHeight) instead of a guessed ratio that
      // can drift out of sync with the tile's actual layout.
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Must stay in sync with this GridView's own padding (20+20) and
          // crossAxisSpacing (14) below — this is what turns the
          // available width into the real on-screen width of one cell.
          final cellWidth = (constraints.maxWidth - 40 - 14) / 2;
          final cardAspectRatio =
              cellWidth / _ServiceCategoryTile.cardHeight(cellWidth);

          return categoriesAsync.when(
            loading: () => GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              itemCount: 6,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: cardAspectRatio,
              ),
              itemBuilder: (context, index) =>
                  ShimmerCard(height: _ServiceCategoryTile.cardHeight(cellWidth)),
            ),
            error: (err, st) => Center(
              child: ErrorStateWidget(
                message: 'Could not load services.',
                onRetry: () => ref.refresh(categoriesProvider),
              ),
            ),
            data: (categories) {
              // Fixed 2026-09-19: strict `== serviceBooking` silently
              // dropped Goods & Transport off this entire screen the
              // moment CatalogFlowType.logistics became its own distinct
              // value — this grid is meant to show "every non-grocery
              // category" (grocery has its own dedicated flow/screens),
              // not specifically serviceBooking ones.
              final services = categories
                  .where((c) => c.flowType != CatalogFlowType.grocery)
                  .toList();

              if (services.isEmpty) {
                return const EmptyStateWidget(
                  title: 'No Services Found',
                  subtitle: 'We are currently expanding our service offerings.',
                  emoji: '🛠️',
                );
              }

              // A fixed "Need Help Choosing a Service?" card always closes
              // the grid (matches the reference screenshot's last cell) —
              // not a category, so it isn't counted against the admin's
              // real category list, just appended after it.
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                itemCount: services.length + 1,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: cardAspectRatio,
                ),
                itemBuilder: (context, index) {
                  if (index == services.length) {
                    return const _NeedHelpTile();
                  }
                  return _ServiceCategoryTile(category: services[index]);
                },
              );
            },
          );
        },
      ),
    );
  }
}


/// The look (icon/accent color) and generic marketing copy (subtitle +
/// tagline pill) for a category tile. Client-side keyword mapping, exactly
/// like the pre-existing `_mapIcon` heuristic this replaces — the backend
/// has no such marketing-copy fields, and a category the admin hasn't
/// specifically been styled for still gets a sensible generic look via the
/// fallback at the end, rather than the grid breaking for it.
class _CategoryStyle {
  const _CategoryStyle({
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.tagline,
  });

  final IconData icon;
  final Color color;
  final String subtitle;
  final String tagline;
}

_CategoryStyle _styleFor(String slug, String name) {
  final s = '$slug $name'.toLowerCase();
  if (s.contains('ac') || s.contains('appliance')) {
    return const _CategoryStyle(
      icon: Icons.ac_unit_rounded,
      color: AppColors.serviceBlue,
      subtitle: 'Installation • Repair • Maintenance',
      tagline: 'Stay Cool, Stay Comfortable',
    );
  }
  if (s.contains('good') || s.contains('transport') || s.contains('truck')) {
    return const _CategoryStyle(
      icon: Icons.local_shipping_rounded,
      color: AppColors.groceryGreen,
      subtitle: 'Home Shifting • Office Moving • Delivery',
      tagline: 'Safe • Fast • Reliable',
    );
  }
  if (s.contains('clean') || s.contains('pest')) {
    return const _CategoryStyle(
      icon: Icons.home_rounded,
      color: Color(0xFF7C3AED),
      subtitle: 'Cleaning • Sanitization • Pest Control',
      tagline: 'Clean Spaces, Healthier Lives',
    );
  }
  if (s.contains('mason') || s.contains('construct')) {
    return const _CategoryStyle(
      icon: Icons.foundation_rounded,
      color: AppColors.warning,
      subtitle: 'Construction • Repairs • Renovation',
      tagline: 'Strong Foundations, Better Homes',
    );
  }
  if (s.contains('paint')) {
    return const _CategoryStyle(
      icon: Icons.format_paint_rounded,
      color: Color(0xFFEC4899),
      subtitle: 'Interior • Exterior • Texture Finish',
      tagline: 'Color Your Dreams',
    );
  }
  if (s.contains('plumb') || s.contains('electric') || s.contains('carpenter')) {
    return const _CategoryStyle(
      icon: Icons.build_rounded,
      color: AppColors.serviceBlue,
      subtitle: 'Repairs • Installations • Fittings',
      tagline: 'Fixed Right, First Time',
    );
  }
  return const _CategoryStyle(
    icon: Icons.home_repair_service_rounded,
    color: AppColors.primary,
    subtitle: 'Trusted Professionals',
    tagline: 'Quality You Can Trust',
  );
}

class _ServiceCategoryTile extends StatelessWidget {
  const _ServiceCategoryTile({required this.category});

  final Category category;

  // Every size literal below mirrors one actually used in build() —
  // kept in sync by hand since Flutter has no way to ask a widget for
  // its own natural height before laying it out. [cardHeight] is the
  // single source of truth AllServicesScreen's LayoutBuilder uses to
  // derive the grid's childAspectRatio, so the cell height always
  // matches this card's real content height instead of a guessed ratio.
  static const double _imageAspectRatio = 16 / 11;
  static const double _contentTopPadding = 22; // Padding(12, 22, ...)
  static const double _contentBottomPadding = 12; // Padding(..., 12)
  // fontSize 14 * height 1.2 * 2 lines, rounded up — see the name Text's
  // fixed-height SizedBox below, which guarantees this regardless of
  // whether the real category name wraps to 1 or 2 lines.
  static const double _nameBlockHeight = 34;
  static const double _nameSubtitleGap = 4; // SizedBox(height: 4)
  // fontSize 10.5 * height 1.2 * 2 lines, rounded up — same fixed-height
  // guarantee as the name block, for the same reason.
  static const double _subtitleBlockHeight = 26;
  static const double _subtitleTaglineGap = 8; // SizedBox(height: 8)
  // Tagline pill: vertical padding 3+3 plus its single text line — always
  // exactly 1 line (maxLines: 1), so this is already deterministic.
  static const double _taglineBlockHeight = 20;
  // Rounding/line-height-estimate slack, same safety-margin convention
  // used by ProductCard.groceryCardHeight.
  static const double _safetyMargin = 6;

  static double cardHeight(double cellWidth) {
    final imageHeight = cellWidth / _imageAspectRatio;
    return imageHeight +
        _contentTopPadding +
        _nameBlockHeight +
        _nameSubtitleGap +
        _subtitleBlockHeight +
        _subtitleTaglineGap +
        _taglineBlockHeight +
        _contentBottomPadding +
        _safetyMargin;
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(category.slug, category.name);

    return GestureDetector(
      onTap: () => context.push('/categories/${category.slug}', extra: category),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: AspectRatio(
                    aspectRatio: 16 / 11,
                    child: AppRemoteImage(
                      imageUrl: category.image,
                      rawPath: category.image,
                      title: category.name,
                      categoryName: category.name,
                      slug: category.slug,
                      semanticIcon: style.icon,
                      fit: BoxFit.cover,
                      fallbackWidget: Container(
                        color: style.color.withValues(alpha: 0.12),
                        child: Center(
                          child: Icon(style.icon, color: style.color, size: 30),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: -16,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: style.color,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: Icon(style.icon, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 22, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: _nameBlockHeight,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              category.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceVariant,
                        ),
                        child: const Icon(Icons.chevron_right_rounded, size: 15, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: _subtitleBlockHeight,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        style.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      style.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: style.color,
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

/// Fixed CTA tile always closing the grid — matches the reference
/// screenshot's "Need Help Choosing a Service?" card. Routes to Support,
/// the app's existing real help/chat destination.
class _NeedHelpTile extends StatelessWidget {
  const _NeedHelpTile();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/support'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.groceryGreenLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Need Help Choosing a Service?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Our team is here to assist you.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.headset_mic_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Chat with Us',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
