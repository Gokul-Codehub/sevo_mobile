import 'package:flutter/material.dart';

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
    accent: Color(0xFF1E3A5F),
    accentDark: Color(0xFF0D253A),
    gradientTop: Color(0xFF1E3A5F),
    searchPlaceholder: "Search for 'AC service'",
    categoryGridTitle: 'Browse by Category',
    trustSectionTitle: 'Why Choose SEVO?',
    trustBadges: [
      (Icons.verified_user_rounded, 'Verified\nProfessionals'),
      (Icons.currency_rupee_rounded, 'Transparent\nPricing'),
      (Icons.access_time_filled_rounded, 'On-time\nService'),
      (Icons.security_rounded, 'Service\nWarranty'),
    ],
    bannerAspectRatio: 2.0,
  );

  static const groceries = HomeFlowTheme(
    mode: HomeFlowMode.groceries,
    accent: Color(0xFF15803D),
    accentDark: Color(0xFF14532D),
    gradientTop: Color(0xFF8DC63F),
    searchPlaceholder: "Search for 'fresh vegetables'...",
    categoryGridTitle: 'Shop by Category',
    trustSectionTitle: 'Why Shop With SEVO?',
    trustBadges: [
      (Icons.eco_rounded, 'Farm-Fresh\nQuality'),
      (Icons.local_shipping_rounded, 'Fast\nDelivery'),
      (Icons.currency_rupee_rounded, 'Honest\nPricing'),
      (Icons.replay_rounded, 'Easy\nReplacements'),
    ],
    bannerAspectRatio: 2.0,
  );

  static HomeFlowTheme of(HomeFlowMode mode) =>
      mode == HomeFlowMode.groceries ? groceries : services;
}
