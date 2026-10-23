import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
    OverlayState? overlayOverride,
  }) {
    final overlay = overlayOverride ?? Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Only one toast on screen at a time — a fast second call (e.g. rapid
    // tapping) replaces whatever's currently showing instead of stacking.
    _activeEntry?.remove();
    _activeEntry = null;

    // White card with a coloured round icon badge (green / red / navy).
    final Color background;
    final IconData icon;
    switch (type) {
      case AppToastType.success:
        background = AppColors.primary;
        icon = Icons.check_rounded;
        break;
      case AppToastType.error:
        background = AppColors.error;
        icon = Icons.priority_high_rounded;
        break;
      case AppToastType.info:
        background = AppColors.navy;
        icon = Icons.info_outline_rounded;
        break;
    }

    // Fixed 2026-10-13 (QA CME06, "notification disappears in seconds"): the
    // banner used to vanish after 1.6 s, too fast to read. It now stays long
    // enough to read the message: ~3 s base, more for longer text, longer
    // again for errors, capped at 7 s.
    final holdFor = duration ??
        Duration(
          milliseconds: (3000 +
                  (message.length > 30 ? (message.length - 30) * 45 : 0) +
                  (type == AppToastType.error ? 1500 : 0))
              .clamp(3000, 7000),
        );

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastBanner(
        message: message,
        background: background,
        icon: icon,
        holdFor: holdFor,
        actionLabel: actionLabel,
        onAction: onAction,
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
    show(
      context,
      '$itemName added to cart',
      actionLabel: 'View cart',
      onAction: () {
        try {
          GoRouter.of(context).push('/cart');
        } catch (_) {}
      },
    );
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
    required this.holdFor,
    this.actionLabel,
    this.onAction,
  });

  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration holdFor;
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
    _dismissTimer = Timer(widget.holdFor, widget.onFinished);
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onFinished,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < 0) widget.onFinished();
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE6EAF0)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: widget.background,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: 17),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: widget.message,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  height: 1.3,
                                  color: AppColors.navy,
                                ),
                              ),
                              if (widget.actionLabel != null && widget.onAction != null)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: GestureDetector(
                                    onTap: () {
                                      widget.onFinished();
                                      widget.onAction!();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(
                                        '${widget.actionLabel} →',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
