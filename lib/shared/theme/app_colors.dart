import 'package:flutter/material.dart';

/// SEVO / CalServices brand color tokens.
/// Extracted from the reference mobile application design.
abstract final class AppColors {
  // ── Primary brand ──
  // Changed 2026-10-27 (colour-code plan): the app-wide default used to be
  // a green (0xFF05A357), so every screen that didn't pick its own colour —
  // services checkout, booking detail, login links — showed green, clashing
  // with "blue + navy = Services". The default is now the Services blue;
  // grocery screens get green through AppTheme.grocery / GroceryTheme.
  // Logistics (Goods Transport, Packers & Movers) is a service, so it uses
  // this same colour.
  // 2026-10-28: Services is ALL NAVY (Divya's choice) — links, selection,
  // focus and spinners are navy too, not blue. Light tints are a cool
  // navy-grey so selected chips still stand out.
  static const Color primary = Color(0xFF0D253A);
  static const Color primaryDark = Color(0xFF0A192F);
  static const Color primaryLight = Color(0xFFEAEFF5);
  static const Color primaryTint = Color(0xFFF4F6F9);
  static const Color accent = Color(0xFF1E3A5F);

  // ── Flow accent: Services = Blue, Groceries = Green ──
  // Blinkit/Amazon/Flipkart-style split so the customer can tell at a
  // glance which kind of order they're in — a scheduled home service
  // (AC, electrician, plumbing, cleaning) vs. a grocery-supply order.
  // Used wherever a screen/widget already knows its own flow type
  // (ServiceItem.flowType / Category.flowType) — never a global override,
  // so shared screens (Home shell, nav bar) stay on the neutral brand
  // color and only flow-specific surfaces switch.
  // 2026-10-28: Services is all navy — these keep their old names (used
  // across the services screens) but now hold the navy family.
  static const Color serviceBlue = Color(0xFF0D253A);
  static const Color serviceBlueDark = Color(0xFF0A192F);
  static const Color serviceBlueLight = Color(0xFFF4F6F9);
  static const Color serviceBlueTint = Color(0xFFEAEFF5);

  // Darkened 2026-10-27: white text on the old 0xFF16A34A was 3.3:1 (below
  // the 4.5:1 readability minimum); 0xFF15803D is 5.0:1. The dark shade
  // reads at 4.6:1 even on the yellow Groceries header.
  static const Color groceryGreen = Color(0xFF15803D);
  static const Color groceryGreenDark = Color(0xFF166534);
  static const Color groceryGreenLight = Color(0xFFF0FDF4);
  static const Color groceryGreenTint = Color(0xFFDCFCE7);

  // ── Dark Navy (Headings, Login/OTP primary CTAs) ──
  static const Color navy = Color(0xFF0D253A);
  static const Color navyDark = Color(0xFF0A192F);
  static const Color navyLight = Color(0xFF1E3A5F);

  // ── Surfaces ──
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color cardSurface = Color(0xFFFFFFFF);

  // ── Text ──
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFFCBD5E1);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Semantic ──
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  // ── Star / Rating ──
  static const Color star = Color(0xFFF59E0B);

  // ── Booking status colors ──
  static const Color statusNewRequest = Color(0xFF3B82F6);
  static const Color statusConfirmed = Color(0xFF05A357);
  static const Color statusAssigned = Color(0xFF7C3AED);
  static const Color statusInProgress = Color(0xFFF59E0B);
  static const Color statusCompleted = Color(0xFF10B981);
  static const Color statusCancelled = Color(0xFFEF4444);
  static const Color statusRefundRequested = Color(0xFFD97706);

  // ── Chip / tag backgrounds ──
  static const Color chipPopularBg = Color(0xFFFEF3C7);
  static const Color chipPopularText = Color(0xFF92400E);
  static const Color chipEssentialBg = Color(0xFFE0F2FE);
  static const Color chipEssentialText = Color(0xFF0369A1);
  static const Color chipGreenBg = Color(0xFFDCFCE7);
  static const Color chipGreenText = Color(0xFF15803D);

  // ── Dividers / borders ──
  static const Color divider = Color(0xFFE2E8F0);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFF1F5F9);

  // ── Shimmer ──
  static const Color shimmerBase = Color(0xFFE2E8F0);
  static const Color shimmerHighlight = Color(0xFFF8FAFC);

  // ── Price display ──
  /// Bold price (₹ amount) — used wherever the final price is shown.
  // Dark in every mode (was green — 3.3:1 on white, hard to read).
  // Only the discount is coloured.
  static const Color priceColor = Color(0xFF0F172A);
  /// Struck-through MRP (original price before discount).
  static const Color priceMrp = Color(0xFF94A3B8);

  // ── Discount badge ──
  static const Color discountBadgeBg = Color(0xFFFFEDE0);
  static const Color discountBadgeText = Color(0xFFE05D00);

  // ── Elevation / shadow tint ──
  /// Subtle card shadow color at 8% alpha — use with blurRadius 12–16.
  static const Color cardShadow = Color(0x14000000); // 8% black
  static const Color cardShadowStrong = Color(0x1F000000); // 12% black

  // ── Exact colours that were repeated as literals across screens. Named here so there is one place to audit and
  // change them. Values are unchanged; merge near-duplicates (for example the E3E8xx family) as a design decision. ──
  static const Color amber200 = Color(0xFFFDE68A);
  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber700 = Color(0xFFB45309);
  static const Color amber800 = Color(0xFF92400E);
  static const Color blue300 = Color(0xFF93C5FD);
  static const Color blue900 = Color(0xFF1E3A8A);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald700 = Color(0xFF047857);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);
  static const Color green900 = Color(0xFF14532D);
  static const Color red700 = Color(0xFFB91C1C);
  static const Color red800 = Color(0xFFC62828);
  static const Color slate600 = Color(0xFF475569);
  static const Color swatch0B2337 = Color(0xFF0B2337);
  static const Color swatch1A1A1A = Color(0xFF1A1A1A);
  static const Color swatch1B7F4B = Color(0xFF1B7F4B);
  static const Color swatch6B7280 = Color(0xFF6B7280);
  static const Color swatch6B7788 = Color(0xFF6B7788);
  static const Color swatch7C2D12 = Color(0xFF7C2D12);
  static const Color swatchB26A00 = Color(0xFFB26A00);
  static const Color swatchCFE6D8 = Color(0xFFCFE6D8);
  static const Color swatchD5DAE1 = Color(0xFFD5DAE1);
  static const Color swatchD5DCE8 = Color(0xFFD5DCE8);
  static const Color swatchD6E3F0 = Color(0xFFD6E3F0);
  static const Color swatchE11D48 = Color(0xFFE11D48);
  static const Color swatchE3E8EE = Color(0xFFE3E8EE);
  static const Color swatchE3E8F0 = Color(0xFFE3E8F0);
  static const Color swatchE3F1E8 = Color(0xFFE3F1E8);
  static const Color swatchE6ECF4 = Color(0xFFE6ECF4);
  static const Color swatchE8ECF1 = Color(0xFFE8ECF1);
  static const Color swatchE8EDF7 = Color(0xFFE8EDF7);
  static const Color swatchECFDF5 = Color(0xFFECFDF5);
  static const Color swatchEDF0F5 = Color(0xFFEDF0F5);
  static const Color swatchEEF1F7 = Color(0xFFEEF1F7);
  static const Color swatchF1F6FB = Color(0xFFF1F6FB);
  static const Color swatchF3F6FC = Color(0xFFF3F6FC);
  static const Color swatchF6F8FA = Color(0xFFF6F8FA);
  static const Color swatchF7F9FC = Color(0xFFF7F9FC);
  static const Color swatchF8F4EF = Color(0xFFF8F4EF);
  static const Color swatchF9C93A = Color(0xFFF9C93A);
}
