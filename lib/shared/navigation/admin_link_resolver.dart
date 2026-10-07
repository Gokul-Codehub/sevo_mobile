import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
String resolveAdminCategoryLinkRoute(String link, String slug) {
  return link.contains('/marketplace')
      ? '/groceries/seller-hub?category=$slug'
      : '/categories/$slug';
}

void handleAdminLinkTap(BuildContext context, String? rawLink, {required String fallbackPath}) {
  final link = rawLink?.trim() ?? '';
  if (link.isNotEmpty) {
    final categoryMatch = RegExp(r'category=([\w-]+)').firstMatch(link);
    if (categoryMatch != null) {
      context.push(resolveAdminCategoryLinkRoute(link, categoryMatch.group(1)!));
      return;
    }
    if (link.startsWith('http://') || link.startsWith('https://')) {
      final uri = Uri.tryParse(link);
      if (uri != null) {
        // Fire-and-forget, matching the existing url_launcher call sites in
        // this app (e.g. support_screen.dart) — onTap handlers here are
        // synchronous VoidCallbacks, not awaited.
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
