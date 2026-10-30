import 'package:flutter/material.dart';

import '../../data/homepage_repository.dart' show MobileHomeTheme;
import '../../domain/home_flow_mode.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/color_contrast.dart';

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
    // Switched 2026-10-09 from the dark navy palette to a light-blue one
    // ("shall we use light blue for services as like uploaded reference
    // image?") — a saturated mid-blue accent for links/icons/active
    // states, with a pale sky-blue gradientTop for the backdrop. Text that
    // used to be white-on-navy (greeting, category labels, active tab) now
    // reads dark on this light backdrop — see home_screen.dart's
    // _UnifiedActiveModeSection.
    accent: Color(0xFF1D6FD6),
    accentDark: Color(0xFF0D3B7A),
    gradientTop: Color(0xFF8EC3F2),
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
    accent: AppColors.groceryGreenDark,
    accentDark: Color(0xFF14532D),
    // Warm golden yellow backdrop (2026-10-09, Blinkit-style Groceries
    // look). The accent stays green so "See all" links, ADD buttons and
    // cart CTAs keep their fresh-grocery green on top of the yellow.
    gradientTop: Color(0xFFF9C93A),
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

  // ── Readable header colours (2026-10-27) ────────────────────────────────
  // The header backdrop ([gradientTop]) and the switcher panel colours are
  // the ADMIN's choice (Mobile App Theme) and may change at any time, so the
  // app never fixes them. What the app does guarantee is that the text and
  // icons drawn ON them stay readable: each getter keeps the admin/default
  // colour when it already reads well, and only darkens/lightens it as far
  // as needed when it doesn't.

  /// Icons on the header backdrop (location pin, chevron, bell) — 3:1.
  Color get headerIcon =>
      ColorContrast.readable(accent, gradientTop, minRatio: 3.0);

  /// Small accent text on the header backdrop ("DELIVERING TO") — 4.5:1.
  Color get headerAccentText => ColorContrast.readable(accent, gradientTop);

  /// Normal text on the header backdrop (the address line) — 4.5:1.
  /// Navy on light backdrops, white on dark ones.
  Color get headerText => ColorContrast.inkOn(gradientTop);

  /// The switcher panel's gradient: the admin's card colours, or the
  /// built-in defaults for any the admin left empty.
  static List<Color> panelColors(HomeFlowMode mode, MobileHomeTheme admin) {
    final groceries = mode == HomeFlowMode.groceries;
    return [
      admin.cardColorTop ??
          (groceries ? const Color(0xFFF9C93A) : const Color(0xFF8EC3F2)),
      admin.cardColorBottom ??
          (groceries ? const Color(0xFFFFE98A) : const Color(0xFFE4F1FE)),
    ];
  }

  static HomeFlowTheme of(HomeFlowMode mode) =>
      mode == HomeFlowMode.groceries ? groceries : services;

  /// The built-in look with the admin's "Mobile App Theme" colours / video
  /// size laid over it (any field the admin left empty keeps its default).
  static HomeFlowTheme withAdmin(HomeFlowMode mode, MobileHomeTheme admin) {
    final base = of(mode);
    return HomeFlowTheme(
      mode: base.mode,
      // Admin's accent kept as-is unless it is too pale to read on the
      // white cards below the header (then darkened just enough, 3:1).
      accent: ColorContrast.readable(
        admin.accentColor ?? base.accent,
        Colors.white,
        minRatio: 3.0,
      ),
      accentDark: base.accentDark,
      gradientTop: admin.backgroundColor ?? base.gradientTop,
      searchPlaceholder: base.searchPlaceholder,
      categoryGridTitle: base.categoryGridTitle,
      trustSectionTitle: base.trustSectionTitle,
      trustBadges: base.trustBadges,
      bannerAspectRatio: base.bannerAspectRatio,
    );
  }
}
