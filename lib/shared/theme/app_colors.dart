import 'package:flutter/material.dart';

/// SEVO / CalServices brand color tokens.
/// Extracted from the reference mobile application design.
abstract final class AppColors {
  // ── Primary brand ──
  static const Color primary = Color(0xFF05A357);
  static const Color primaryDark = Color(0xFF038043);
  static const Color primaryLight = Color(0xFFE8F8F0);
  static const Color primaryTint = Color(0xFFF0FAF5);
  static const Color accent = Color(0xFF10B981);

  // ── Flow accent: Services = Blue, Groceries = Green ──
  // Blinkit/Amazon/Flipkart-style split so the customer can tell at a
  // glance which kind of order they're in — a scheduled home service
  // (AC, electrician, plumbing, cleaning) vs. a grocery-supply order.
  // Used wherever a screen/widget already knows its own flow type
  // (ServiceItem.flowType / Category.flowType) — never a global override,
  // so shared screens (Home shell, nav bar) stay on the neutral brand
  // color and only flow-specific surfaces switch.
  static const Color serviceBlue = Color(0xFF2563EB);
  static const Color serviceBlueDark = Color(0xFF1D4ED8);
  static const Color serviceBlueLight = Color(0xFFEFF6FF);
  static const Color serviceBlueTint = Color(0xFFDBEAFE);

  static const Color groceryGreen = Color(0xFF16A34A);
  static const Color groceryGreenDark = Color(0xFF15803D);
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
}
