import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/home_flow_mode.dart';

/// Per-mode color palette + copy for Home's two themed variants.
///
/// Added 2026-09-19 as part of the "two different home pages" redesign —
/// every color/placeholder/section-copy choice Home used to hardcode to
/// the services blue/navy palette now reads from here instead, so
/// Groceries mode can look meaningfully different (green-led, Blinkit-style)
/// without duplicating the same logic across every widget.
class HomeFlowTheme {
  const HomeFlowTheme({
    required this.mode,
    required this.accent,
    required this.accentDark,
    required this.gradientTop,
    required this.searchPlaceholder,
    required this.categoryGridTitle,
    required this.trustSectionTitle,
    required this.trustBadges,
    required this.bannerAspectRatio,
  });

  final HomeFlowMode mode;

  /// The mode's single accent color — used for "See all" links, active
  /// indicators, CTA icons, and badge tints throughout this mode's content.
  final Color accent;

  /// A darker shade of [accent], used for the top gradient backdrop (the
  /// same role AppColors.navy played before this mode ever existed).
  final Color accentDark;

  final Color gradientTop;
  final String searchPlaceholder;
  final String categoryGridTitle;
  final String trustSectionTitle;

  /// (icon, label) pairs for the trust-badge row — real, generic service
  /// promises (never invented business metrics like ratings or counts),
  /// just worded and colored for this specific flow.
  final List<(IconData, String)> trustBadges;

  /// Added 2026-09-19 per explicit request ("make separate updation of the
  /// respective size banners from admin panel separately to both services
  /// and groceries"): the promo-banner carousel's shape (width/height, via
  /// `AspectRatio`) is now themed per mode instead of one fixed ratio
  /// shared by both — a first step so each mode's carousel can genuinely
  /// look different. This alone doesn't give the admin panel a way to set
  /// a DIFFERENT ratio per mode from the UI (settings_hub's homepage
  /// config has no such field yet, and that's a backend + admin-frontend
  /// change outside this Flutter app) — until that ships, this constant is
  /// the one place controlling each mode's shape, and the admin should
  /// crop/export banner images to match it per mode.
  final double bannerAspectRatio;

  static const services = HomeFlowTheme(
    mode: HomeFlowMode.services,
    accent: AppColors.serviceBlue,
    accentDark: AppColors.navy,
    // Lightened 2026-09-28 per explicit follow-up ("brighten the
    // background around the logo... lighten the entire background color")
    // — the SEVO logo was reading as low-contrast against the old solid
    // AppColors.navy top backdrop. Uses the palette's own existing lighter
    // navy shade rather than inventing a new color.
    gradientTop: AppColors.navyLight,
    searchPlaceholder: 'Search services...',
    categoryGridTitle: 'Browse by Category',
    trustSectionTitle: 'Why Choose SEVO?',
    trustBadges: [
      (Icons.verified_user_rounded, 'Verified\nProfessionals'),
      (Icons.currency_rupee_rounded, 'Transparent\nPricing'),
      (Icons.access_time_filled_rounded, 'On-time\nService'),
      (Icons.security_rounded, 'Service\nWarranty'),
    ],
    // Widened/shortened 2026-09-19 per explicit request ("reduce the
    // height and occupy the entire width of the user mobile screen") —
    // the carousel is now full-bleed edge-to-edge (see home_screen.dart's
    // _PromoBannerCarousel, viewportFraction 1.0) instead of an inset
    // peeking card, so this ratio only needs to control height for a
    // width that's now the full device width, not ~88% of it.
    bannerAspectRatio: 1.9,
  );

  static const groceries = HomeFlowTheme(
    mode: HomeFlowMode.groceries,
    accent: AppColors.groceryGreen,
    accentDark: Color(0xFF0F4C2E),
    // Lightened 2026-09-28, same reason as Services' gradientTop above —
    // was the same very dark 0xFF0F4C2E as accentDark; now a lighter,
    // still-on-brand green (the palette's own groceryGreenDark) so the
    // logo has real contrast against it.
    gradientTop: AppColors.groceryGreenDark,
    searchPlaceholder: 'Search groceries...',
    categoryGridTitle: 'Shop by Category',
    trustSectionTitle: 'Why Shop With SEVO?',
    trustBadges: [
      (Icons.eco_rounded, 'Farm-Fresh\nQuality'),
      (Icons.local_shipping_rounded, 'Fast\nDelivery'),
      (Icons.currency_rupee_rounded, 'Honest\nPricing'),
      (Icons.replay_rounded, 'Easy\nReplacements'),
    ],
    // Wider/shorter than Services' — grocery promo photography (a produce
    // basket, a delivery bag) tends to read better landscape than the
    // taller shape Services uses. Widened further 2026-09-19 alongside
    // Services' own change, for the same full-bleed, shorter-banner reason.
    bannerAspectRatio: 2.2,
  );

  static HomeFlowTheme of(HomeFlowMode mode) =>
      mode == HomeFlowMode.groceries ? groceries : services;
}
