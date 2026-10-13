import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/navigation/web_link_mapper.dart';
import '../../features/home/domain/home_flow_mode.dart';

/// Shared interpreter for every admin-configured "link" field across the
/// Home screen's admin-authored content (Bestsellers tiles, Quick Access
/// cards, and — added 2026-10-05 — the Banner + Product Rail grocery
/// section's banner CTA).
///
/// Extracted 2026-10-05 from `home_screen.dart`'s private
/// `_handleAdminLinkTap`/`_resolveCategoryLinkRoute` (which still exist
/// there as thin wrappers delegating here, so every existing call site and
/// its behavior is unchanged) so the new banner CTA in
/// `grocery_section_layouts.dart` reuses the exact same interpretation
/// instead of a second, slightly-different copy of this regex. This is the
/// only place this logic lives now.
///
/// Link format: a raw string, not a structured object — the same
/// convention every other admin-configured link in this app already uses
/// (Bestsellers tile `link`, Quick Access card `link`, the seed config's
/// `/booking?category=...` entries). Recognized shapes, checked in order:
///   1. Contains `category=<slug>` anywhere — routes to the matching
///      category browse screen ([resolveAdminCategoryLinkRoute]).
///   2. Starts with `http://` or `https://` — opens externally via
///      `url_launcher` (added 2026-10-05; the package was already a
///      pubspec dependency and already used this exact
///      `launchUrl(uri, mode: LaunchMode.externalApplication)` call style
///      elsewhere in the app, e.g. support_screen.dart's WhatsApp link —
///      reused verbatim, not a new pattern).
///   3. Starts with `/` — pushed as an in-app route path.
///   4. Anything else (empty, unrecognized) — falls back to [fallbackPath].
/// A category slug that belongs to the OLD vegetable-inventory grocery category
/// ("vegetables_groceries", "farm-fresh…"). That page is empty now — Groceries
/// live in the Seller Hub marketplace — so links to it are sent there instead.
bool _isLegacyGrocerySlug(String slug) {
  final s = slug.toLowerCase().replaceAll('-', '_');
  return s.contains('vegetable') || s.contains('grocer') || s.contains('farm_fresh');
}

String resolveAdminCategoryLinkRoute(String link, String slug) {
  if (link.contains('/marketplace')) return '/groceries/seller-hub?category=$slug';
  if (_isLegacyGrocerySlug(slug)) return '/groceries/seller-hub';
  return '/categories/$slug';
}

/// Opens an admin-configured link. Besides the shapes listed at the top of this
/// file it understands the website's own paths (via [resolveWebLink]):
/// `/vegetables`, `/marketplace/combo/<id>`, `/booking/services?category=…`,
/// `/trucks/…`, `/bookings` and so on. `#`, empty and unknown values go to
/// [fallbackPath].
void handleAdminLinkTap(BuildContext context, String? rawLink, {required String fallbackPath}) {
  var link = rawLink?.trim() ?? '';
  if (link == '#') link = '';
  if (link.isNotEmpty) {
    final categoryMatch = RegExp(r'category=([\w-]+)').firstMatch(link);
    if (categoryMatch != null) {
      context.push(resolveAdminCategoryLinkRoute(link, categoryMatch.group(1)!));
      return;
    }

    // Website paths (and sevo.co.in URLs) map onto app screens.
    final web = resolveWebLink(link);
    if (web.groceriesHome) {
      ProviderScope.containerOf(context).read(homeFlowModeProvider.notifier).state =
          HomeFlowMode.groceries;
      context.go('/');
      return;
    }
    if (web.route != null) {
      context.push(web.route!);
      return;
    }

    if (link.startsWith('http://') || link.startsWith('https://')) {
      final uri = Uri.tryParse(link);
      if (uri != null) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (link.startsWith('/')) {
      context.push(link);
      return;
    }
  }
  context.push(fallbackPath);
}
