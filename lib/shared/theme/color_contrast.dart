import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Readability helpers for colours the app does not choose itself — mainly
/// the Home page colours the admin sets in the Mobile App Theme settings.
///
/// The admin keeps full control of backgrounds. These helpers only adjust
/// the TEXT and ICON colours drawn on top of them, so whatever background
/// the admin picks, the words on it stay readable (WCAG AA: 4.5:1 for
/// normal text, 3:1 for icons and large text).
abstract final class ColorContrast {
  /// WCAG contrast ratio between two colours (1.0 – 21.0).
  static double ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Dark or light ink, whichever reads better on [background].
  static Color inkOn(
    Color background, {
    Color dark = AppColors.navy,
    Color light = Colors.white,
  }) =>
      ratio(dark, background) >= ratio(light, background) ? dark : light;

  /// Returns [color] unchanged when it already reaches [minRatio] on
  /// [background]. Otherwise keeps its hue and pushes it darker (on light
  /// backgrounds) or lighter (on dark ones) just far enough to read; if
  /// that still is not enough, falls back to plain dark/light ink.
  static Color readable(
    Color color,
    Color background, {
    double minRatio = 4.5,
  }) {
    if (ratio(color, background) >= minRatio) return color;
    final towards = ratio(Colors.black, background) >= ratio(Colors.white, background)
        ? Colors.black
        : Colors.white;
    for (var step = 1; step <= 9; step++) {
      final candidate = Color.lerp(color, towards, step / 10)!;
      if (ratio(candidate, background) >= minRatio) return candidate;
    }
    return inkOn(background);
  }

  /// Midpoint of a two-colour gradient — the colour text on it mostly sits on.
  static Color middle(List<Color> gradient) =>
      gradient.length < 2 ? gradient.first : Color.lerp(gradient.first, gradient.last, 0.5)!;
}
