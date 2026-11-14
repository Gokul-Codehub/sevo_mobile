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
  });

  final Widget child;
  final double? maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final cap = maxWidth ?? AppResponsive.contentMaxWidth(context);
    if (!cap.isFinite) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, cap).toDouble()
            : cap;
        return Align(
          alignment: alignment,
          child: SizedBox(
            width: width,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}
