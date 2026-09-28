import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/image_url_helper.dart';
import '../theme/app_colors.dart';
import 'common_widgets.dart';

/// Resilient remote image widget with a two-tier fallback:
/// Tier 1: Live Production HTTPS Asset (CachedNetworkImage)
/// Tier 2: Branded Semantic Vector Icon Placeholder
///
/// This used to have a "Tier 2: local asset bundle" step in between that
/// tried assets/images/mockups/... before falling back to the icon — but
/// that folder was never actually bundled into the app (verified: it does
/// not exist on disk), so every attempt was a guaranteed failure that only
/// added a wasted decode and a misleading "asset not found" log line for
/// every single image. Removed rather than left as dead weight. The real
/// fix for missing product photography is either the backend serving
/// working media URLs, or real images being bundled as local assets —
/// this widget can't manufacture photos that don't exist anywhere.
class AppRemoteImage extends StatelessWidget {
  // Short-lived memory of URLs that have already failed recently. Nearly
  // every product/service image points at the same handful of dead
  // backend/Unsplash URLs, so without this, every rebuild of every card
  // showing one of those URLs re-attempts the network fetch, fails again,
  // and rebuilds the placeholder again — a constant churn of failed
  // requests and layout/paint work every time the list scrolls or any
  // ancestor rebuilds (e.g. cart quantity changing). That churn is very
  // likely what's been making the app's rare Flutter-framework navigation
  // races (Offstage/ModalScope hit-test errors during route transitions)
  // surface as often as they have — cutting the repeated failed work
  // reduces how often the app is under enough layout/paint pressure to
  // hit that race. Once a URL has failed, this widget skips the network
  // attempt for a cooldown window and renders the placeholder immediately.
  //
  // Fixed 2026-09-17 — root cause of "the same service's photo shows on
  // the Services list but not in Home's Book Again / Recommended Services
  // or the service-detail page's Related Services strip": this used to be
  // a permanent `Set<String>` — the FIRST time a URL failed for ANY
  // reason (including a purely transient one, like the burst of many
  // concurrent image requests Home fires at once on cold app start
  // exhausting the platform's connection pool) it was blacklisted for the
  // rest of the app session, with no retry, even once the network was
  // completely healthy again. Whichever screen happened to render that
  // image first and hit a transient hiccup would poison it everywhere
  // else for the remainder of the session — exactly the "shows here, not
  // there" inconsistency reported. Now a `Map<String, DateTime>` of
  // failure timestamps: still skips an immediate re-fetch storm within
  // the cooldown window (the actual problem the original fix targeted),
  // but a URL that failed once gets a fresh real attempt again shortly
  // after, so a cold-start hiccup doesn't take an image down permanently.
  static final Map<String, DateTime> _recentlyFailedUrls = {};
  static const Duration _failureCooldown = Duration(seconds: 45);

  static bool _isKnownBad(String url) {
    final failedAt = _recentlyFailedUrls[url];
    if (failedAt == null) return false;
    if (DateTime.now().difference(failedAt) >= _failureCooldown) {
      _recentlyFailedUrls.remove(url);
      return false;
    }
    return true;
  }

  const AppRemoteImage({
    super.key,
    required this.imageUrl,
    this.rawPath,
    this.title,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackWidget,
    this.semanticIcon,
    this.categoryName,
    this.slug,
    this.categoryId,
  });

  /// Fully qualified HTTPS image URL (or relative path to resolve).
  final String? imageUrl;

  /// Original raw path from API response (e.g. /mockups/vegetables_realistic.png).
  final String? rawPath;

  /// Title / name of the service or product for contextual photographic lookup.
  final String? title;

  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Custom fallback widget if provided.
  final Widget? fallbackWidget;

  /// Icon to use in the default semantic placeholder.
  final IconData? semanticIcon;

  /// Category name for debug logging and icon mapping.
  final String? categoryName;

  /// Slug for icon mapping.
  final String? slug;

  /// Category ID for flow-specific photographic mapping.
  final int? categoryId;

  bool get _isGrocery {
    final s = '${categoryName ?? ''} ${slug ?? ''}'.toLowerCase();
    return categoryId == 18 || s.contains('veg') || s.contains('grocer');
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = ImageUrlHelper.resolve(
      imageUrl ?? rawPath,
      title: title,
      slug: slug,
      categorySlug: categoryName,
      categoryId: categoryId,
    );

    Widget imageContent;

    if (resolvedUrl == null ||
        resolvedUrl.isEmpty ||
        _isKnownBad(resolvedUrl)) {
      imageContent = _buildPlaceholder();
    } else {
      // Fixed 2026-09-18 (performance pass, "the application is getting
      // lag"): without memCacheWidth/memCacheHeight, CachedNetworkImage
      // decodes every image at its full source resolution and keeps that
      // full-size bitmap in memory even when it's being rendered into a
      // 56px icon tile or a 165px product card — decoding a multi-megapixel
      // photo down to a tiny tile is one of the most common causes of
      // scroll jank in an image-heavy catalog/grocery app like this one,
      // and it gets worse the more images are on screen at once (a grid,
      // a horizontal strip). Capping the decode target to the widget's own
      // display size (scaled up by the device's pixel ratio so it still
      // looks sharp) means the same image only ever gets decoded once, at
      // roughly the size it's actually shown at.
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final targetCacheWidth =
          width != null && width!.isFinite ? (width! * dpr).round() : null;
      final targetCacheHeight =
          height != null && height!.isFinite ? (height! * dpr).round() : null;

      // Primary: Try live production network image
      imageContent = CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: targetCacheWidth,
        memCacheHeight: targetCacheHeight,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (context, url) => ShimmerBox(
          width: width,
          height: height,
          borderRadius: 0,
        ),
        errorWidget: (context, url, error) {
          if (!_recentlyFailedUrls.containsKey(url)) {
            debugPrint('[IMAGE NETWORK FAILED]');
            debugPrint('  Category/Service: ${categoryName ?? slug ?? "unknown"}');
            debugPrint('  URL: $url');
            debugPrint('  -> Using semantic placeholder (will retry after ${_failureCooldown.inSeconds}s)');
          }
          _recentlyFailedUrls[url] = DateTime.now();
          return _buildPlaceholder();
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageContent,
      );
    }

    return imageContent;
  }

  Widget _buildPlaceholder() {
    if (fallbackWidget != null) return fallbackWidget!;

    final iconData = semanticIcon ??
        ImageUrlHelper.mapCategoryIcon(categoryName, slug);
    // Flow-colored placeholder — green for groceries, blue for services —
    // matching the accent used everywhere else a card knows its flow type,
    // instead of a generic teal that doesn't tell the customer anything.
    final accent = _isGrocery ? AppColors.groceryGreen : AppColors.serviceBlue;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.10),
            accent.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          iconData,
          size: (width != null && width! < 60) ? 24 : 32,
          color: accent,
        ),
      ),
    );
  }
}
