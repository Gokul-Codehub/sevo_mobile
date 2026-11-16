import 'package:flutter/material.dart';

/// Shared size helpers so phone layouts scale cleanly onto tablets.
abstract final class AppResponsive {
  AppResponsive._();

  /// Material tablet breakpoint (shortest side in logical pixels).
  static const double tabletShortestSide = 600;

  static Size sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isTablet(BuildContext context) =>
      sizeOf(context).shortestSide >= tabletShortestSide;

  static bool isWide(BuildContext context) => sizeOf(context).width >= 900;

  /// Keeps phone-first screens readable on large tablets instead of stretching edge-to-edge.
  static double contentMaxWidth(BuildContext context) {
    final w = sizeOf(context).width;
    if (w >= 1200) return 1100;
    if (w >= 900) return 960;
    if (w >= 600) return 760;
    return double.infinity;
  }

  /// Floating bottom nav stays a comfortable pill width on tablets.
  static double navMaxWidth(BuildContext context) {
    if (!isTablet(context)) return double.infinity;
    return isWide(context) ? 640.0 : 560.0;
  }

  /// Product / grocery card grids.
  static int productColumns(double width) {
    if (width >= 1100) return 4;
    if (width >= 700) return 3;
    return 2;
  }

  /// Category browse grids (services, baskets).
  static int categoryColumns(double width) {
    if (width >= 1000) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  /// Home bestsellers / quick category tiles.
  static int bestsellerColumns(double width) {
    if (width >= 1000) return 6;
    if (width >= 700) return 5;
    if (width >= 600) return 4;
    return 3;
  }

  /// Admin-chosen column count for Home Studio grids, widened on tablets so
  /// phone-sized tiles do not look sparse in a 760-1100px column.
  static int sectionColumns(BuildContext context, int base, {int max = 6}) {
    final w = sizeOf(context).width.clamp(0.0, contentMaxWidth(context));
    var extra = 0;
    if (w >= 900) {
      extra = 2;
    } else if (w >= 600) {
      extra = 1;
    }
    return (base + extra).clamp(base, base > max ? base : max).toInt();
  }

  /// Banners are flatter on tablets so they do not become huge.
  static double bannerAspect(BuildContext context, double phoneAspect) =>
      isTablet(context) ? phoneAspect * 1.4 : phoneAspect;

  /// User's text scale (1.0 = default), from the system font-size setting.
  static double textScale(BuildContext context) {
    final s = MediaQuery.textScalerOf(context).scale(14) / 14;
    return s < 1 ? 1.0 : s;
  }

  /// A fixed rail / strip height that still fits its text when the user has
  /// raised the system font size. [textShare] is roughly how much of the
  /// height is text (the rest, e.g. images, does not grow).
  static double scaledHeight(BuildContext context, double h, {double textShare = 0.5}) =>
      h * (1 + (textScale(context) - 1) * textShare);

  /// Grid childAspectRatio that gets taller (smaller ratio) as the system
  /// font grows, so text tiles keep room instead of overflowing.
  static double scaledAspect(BuildContext context, double ratio, {double textShare = 0.4}) =>
      ratio / (1 + (textScale(context) - 1) * textShare);

  static int columnsFor(
    BuildContext context, {
    required int Function(double width) picker,
    double horizontalInset = 0,
  }) {
    final w = (sizeOf(context).width - horizontalInset)
        .clamp(0.0, contentMaxWidth(context));
    return picker(w);
  }
}

/// Centers [child] and caps its width on tablets / wide screens while
/// still filling the available height (so Scaffold bodies layout correctly).
class AdaptiveWidth extends StatelessWidget {
  const AdaptiveWidth({
    super.key,
    required this.child,
    this.maxWidth,
    this.alignment = Alignment.center,
    this.fillHeight = true,
  });

  final Widget child;
  final double? maxWidth;
  final AlignmentGeometry alignment;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final cap = maxWidth ?? AppResponsive.contentMaxWidth(context);
    if (!cap.isFinite) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, cap).toDouble()
            : cap;
        final media = MediaQuery.of(context);
        final inner = SizedBox(
          width: width,
          height: (fillHeight && constraints.hasBoundedHeight)
              ? constraints.maxHeight
              : null,
          child: child,
        );
        return Align(
          alignment: alignment,
          // Without a heightFactor, Align grows to the full bounded height. For bars in a loose-but-tall slot
          // (Scaffold.bottomNavigationBar) that pushed the page body off screen on tablets.
          heightFactor: fillHeight ? null : 1.0,
          // Descendants see the capped width so grids pick columns for the visible column.
          child: MediaQuery(
            data: media.copyWith(
              size: Size(
                width,
                constraints.hasBoundedHeight ? constraints.maxHeight : media.size.height,
              ),
            ),
            child: inner,
          ),
        );
      },
    );
  }
}
