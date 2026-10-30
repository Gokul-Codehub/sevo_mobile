import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// SEVO / CalServices Material 3 theme matching reference mobile design.
///
/// Colour code (2026-10-27):
/// * [light] — the app-wide default = Services: all navy (buttons, links,
///   focus, selection — 2026-10-28). Logistics (Goods Transport, Packers &
///   Movers) is a service and uses this too.
/// * [grocery] — Groceries & Vegetables: green main buttons, links and
///   selection. Applied to the grocery screens through `GroceryTheme`
///   (see app_router.dart), so default widgets turn green there without
///   each screen setting colours by hand.
/// The Home page header colours are NOT decided here — the admin sets
/// them (Mobile App Theme); see HomeFlowTheme / ColorContrast.
abstract final class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(_FlowSwatch.services);

  /// Cached — the grocery routes wrap themselves in this on every build.
  static final ThemeData grocery = _build(_FlowSwatch.groceries);

  static ThemeData _build(_FlowSwatch s) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: s.primary,
          brightness: Brightness.light,
          primary: s.primary,
          onPrimary: AppColors.textOnPrimary,
          primaryContainer: s.container,
          onPrimaryContainer: s.onContainer,
          secondary: AppColors.navy,
          onSecondary: AppColors.textOnPrimary,
          error: AppColors.error,
          onError: AppColors.textOnPrimary,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: _textTheme,
        appBarTheme: _appBarTheme,
        elevatedButtonTheme: _elevatedButtonTheme(s),
        filledButtonTheme: _filledButtonTheme(s),
        outlinedButtonTheme: _outlinedButtonTheme(s),
        textButtonTheme: _textButtonTheme(s),
        inputDecorationTheme: _inputDecorationTheme(s),
        cardTheme: _cardTheme,
        chipTheme: _chipTheme(s),
        bottomNavigationBarTheme: _bottomNavTheme(s),
        progressIndicatorTheme: ProgressIndicatorThemeData(color: s.primary),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 0.8,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      );

  // ── Typography ──────────────────────────────────────────────────────────────
  static TextTheme get _textTheme => GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          headlineLarge: TextStyle(
            fontSize: 19.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          headlineMedium: TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          headlineSmall: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleSmall: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          bodyLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          bodySmall: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textOnPrimary,
            letterSpacing: 0.1,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
          labelSmall: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textHint,
          ),
        ),
      );

  // ── AppBar ──────────────────────────────────────────────────────────────────
  static const AppBarTheme _appBarTheme = AppBarTheme(
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    scrolledUnderElevation: 0.5,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    iconTheme: IconThemeData(color: AppColors.textPrimary),
  );

  // ── Buttons ─────────────────────────────────────────────────────────────────
  static ElevatedButtonThemeData _elevatedButtonTheme(_FlowSwatch s) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.cta,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      );

  static FilledButtonThemeData _filledButtonTheme(_FlowSwatch s) =>
      FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: s.cta,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(_FlowSwatch s) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: s.primary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: s.primary, width: 1.5),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  static TextButtonThemeData _textButtonTheme(_FlowSwatch s) => TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: s.primary,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  // ── Inputs ──────────────────────────────────────────────────────────────────
  static InputDecorationTheme _inputDecorationTheme(_FlowSwatch s) =>
      InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.border),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: s.primary, width: 2),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.error, width: 2),
    ),
    hintStyle: const TextStyle(
      color: AppColors.textHint,
      fontSize: 13,
    ),
    errorStyle: const TextStyle(color: AppColors.error, fontSize: 11.5),
  );

  // ── Cards ───────────────────────────────────────────────────────────────────
  static const CardThemeData _cardTheme = CardThemeData(
    color: AppColors.cardSurface,
    elevation: 0,
    shadowColor: AppColors.cardShadow,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      side: BorderSide(color: AppColors.borderSubtle, width: 0.8),
    ),
    margin: EdgeInsets.zero,
  );

  // ── Chips ───────────────────────────────────────────────────────────────────
  static ChipThemeData _chipTheme(_FlowSwatch s) => ChipThemeData(
    backgroundColor: AppColors.surface,
    selectedColor: s.container,
    disabledColor: AppColors.divider,
    labelStyle: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
    ),
    secondaryLabelStyle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: s.onContainer,
    ),
    side: const BorderSide(color: AppColors.border, width: 0.8),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    iconTheme: const IconThemeData(size: 16, color: AppColors.textSecondary),
  );

  // ── Bottom Navigation ───────────────────────────────────────────────────────
  static BottomNavigationBarThemeData _bottomNavTheme(_FlowSwatch s) =>
      BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: s.primary,
    unselectedItemColor: AppColors.textSecondary,
    selectedLabelStyle:
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    unselectedLabelStyle: const TextStyle(fontSize: 11),
    type: BottomNavigationBarType.fixed,
    elevation: 8,
  );
}

/// One flow's colours. Every pair here passes 4.5:1 with its text.
class _FlowSwatch {
  const _FlowSwatch({
    required this.primary,
    required this.cta,
    required this.container,
    required this.onContainer,
  });

  /// Links, focus rings, selected states, spinners.
  final Color primary;

  /// Main (filled) button background — white text on it.
  final Color cta;

  /// Selected chip / tinted background, and the text on it.
  final Color container;
  final Color onContainer;

  /// Services (and logistics): all navy (2026-10-28).
  static const services = _FlowSwatch(
    primary: AppColors.primary, // navy 0xFF0D253A — 15.6:1 on white
    cta: AppColors.navy, // 15.6:1 with white text
    container: AppColors.primaryLight,
    onContainer: AppColors.primaryDark,
  );

  /// Groceries & Vegetables: green buttons and accents.
  static const groceries = _FlowSwatch(
    primary: AppColors.groceryGreen, // 0xFF15803D — 5.0:1 on white
    cta: AppColors.groceryGreen,
    container: AppColors.groceryGreenLight,
    onContainer: AppColors.groceryGreenDark,
  );
}
