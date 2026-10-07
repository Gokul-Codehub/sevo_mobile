import 'dart:async';

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
///
/// Fixed 2026-10-07 ("The notification like product added to cart, negative
/// messages pop up all should be shown top of the screen not at bottom"):
/// [SnackBar]/[ScaffoldMessenger] is always bottom-anchored in Flutter —
/// there's no "show at top" option for it — so this no longer uses a
/// SnackBar at all. It now inserts its own small banner directly into the
/// app's root [Overlay], positioned just below the status bar/safe area
/// instead. The public API ([show]/[addedToCart]/[bookingSuccessful]) is
/// unchanged, so every existing call site moves to the top automatically
/// with no changes needed at the call site.
class AppToast {
  const AppToast._();

  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.success,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Only one toast on screen at a time — a fast second call (e.g. rapid
    // tapping) replaces whatever's currently showing instead of stacking.
    _activeEntry?.remove();
    _activeEntry = null;

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

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastBanner(
        message: message,
        background: background,
        icon: icon,
        onFinished: () {
          if (_activeEntry == entry) {
            _activeEntry = null;
          }
          entry.remove();
        },
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
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

/// The actual top-anchored popup content, rendered into the root [Overlay]
/// by [AppToast.show]. Fades + slides in from above the safe area, holds
/// briefly, then removes itself.
class _ToastBanner extends StatefulWidget {
  const _ToastBanner({
    required this.message,
    required this.background,
    required this.icon,
    required this.onFinished,
  });

  final String message;
  final Color background;
  final IconData icon;
  final VoidCallback onFinished;

  @override
  State<_ToastBanner> createState() => _ToastBannerState();
}

class _ToastBannerState extends State<_ToastBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controller.forward();
    _dismissTimer = Timer(
      const Duration(milliseconds: 1600),
      widget.onFinished,
    );
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 8,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOut,
          )),
          child: FadeTransition(
            opacity: _controller,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.background,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
