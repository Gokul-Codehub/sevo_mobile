import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Visual style for [AppToast.show] — picks the accent color and default
/// icon for the popup.
enum AppToastType { success, error, info }

/// A single shared "toast"-style popup for quick, non-blocking confirmation
/// messages across the app — e.g. "Added to cart", "Booking successful".
///
/// Added 2026-09-18 per explicit request ("For every product added to
/// cart/ booking for anything need to notify the user use a simple pop up
/// message like 'added to cart' 'booking successful' like this..."). Before
/// this, every screen called `ScaffoldMessenger.of(context).showSnackBar(...)`
/// ad hoc with its own one-off styling (plain default SnackBar in most
/// places, a nicer floating/rounded one only in service_card.dart, and no
/// feedback at all in several add-to-cart/booking-success spots). This
/// widget is now the one place that decides how a confirmation popup looks,
/// modeled on that best existing style (floating, rounded, short-lived,
/// colored by outcome) — every call site should go through this instead of
/// building its own SnackBar.
class AppToast {
  const AppToast._();

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.success,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final Color background;
    final IconData icon;
    switch (type) {
      case AppToastType.success:
        background = AppColors.primary;
        icon = Icons.check_circle_rounded;
        break;
      case AppToastType.error:
        background = AppColors.error;
        icon = Icons.error_rounded;
        break;
      case AppToastType.info:
        background = AppColors.navy;
        icon = Icons.info_rounded;
        break;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: background,
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  /// Convenience for the app's most common confirmation: an item/service
  /// was just added to the cart.
  static void addedToCart(BuildContext context, String itemName) {
    show(context, '$itemName added to cart');
  }

  /// Convenience for a successfully created booking.
  static void bookingSuccessful(BuildContext context) {
    show(context, 'Booking successful');
  }
}
