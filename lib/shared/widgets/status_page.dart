import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Which "negative" situation a [StatusPage] illustrates.
enum StatusKind { noInternet, notFound, error, empty, noResults }

/// The app's one layout for every negative / empty state: a soft illustration
/// on top, an optional small reference line, a bold title, a short message
/// and an outlined pill button ("Try again", "Go home"...).
///
/// Used by the No Internet overlay, the Page Not Found route, the generic
/// error state and the empty-list states so they all look the same, in the
/// app's navy + green palette.
class StatusPage extends StatelessWidget {
  const StatusPage({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.reference,
    this.compact = false,
  });

  final StatusKind kind;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Small grey line under the illustration (e.g. a request id).
  final String? reference;

  /// Smaller illustration for use inside a list / card instead of a full screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final art = compact ? 150.0 : 230.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 16 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusIllustration(kind: kind, size: art),
            if (reference != null && reference!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                reference!,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textHint, letterSpacing: 0.4),
                textAlign: TextAlign.center,
              ),
            ],
            SizedBox(height: compact ? 14 : 26),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 18 : 22,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 16 : 24),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: const BorderSide(color: AppColors.primary, width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen version: white page with the [StatusPage] centred.
class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key, required this.page});

  final StatusPage page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: page),
            ),
          ),
        ),
      ),
    );
  }
}

/// The illustration block: soft clouds, a ground shadow and the subject.
/// "No internet" uses the supplied artwork; the others are drawn in the app's
/// navy / green / warm-yellow palette in the same flat style.
class StatusIllustration extends StatelessWidget {
  const StatusIllustration({super.key, required this.kind, this.size = 230});

  final StatusKind kind;
  final double size;

  static const _warm = Color(0xFFF9C93A);

  @override
  Widget build(BuildContext context) {
    if (kind == StatusKind.noInternet) {
      return SizedBox(
        width: size * 1.1,
        height: size,
        child: Image.asset('assets/images/status_no_internet.png', fit: BoxFit.contain),
      );
    }
    return SizedBox(
      width: size * 1.1,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(left: size * 0.02, top: size * 0.06, child: _cloud(size * 0.34)),
          Positioned(right: size * 0.02, top: size * 0.14, child: _cloud(size * 0.28)),
          // ground shadow
          Positioned(
            bottom: size * 0.1,
            child: Container(
              width: size * 0.78,
              height: size * 0.09,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(size),
              ),
            ),
          ),
          Positioned(bottom: size * 0.17, child: _subject()),
        ],
      ),
    );
  }

  Widget _cloud(double w) => Container(
        width: w,
        height: w * 0.36,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.circular(w),
        ),
      );

  Widget _subject() {
    switch (kind) {
      case StatusKind.notFound:
        return _browserCard(
          child: Text(
            '404',
            style: TextStyle(fontSize: size * 0.2, fontWeight: FontWeight.w900, color: AppColors.navy, letterSpacing: 1),
          ),
          badge: Icons.search_rounded,
        );
      case StatusKind.error:
        return _browserCard(
          child: Icon(Icons.warning_amber_rounded, size: size * 0.26, color: AppColors.navy),
          badge: Icons.close_rounded,
        );
      case StatusKind.noResults:
        return _browserCard(
          child: Icon(Icons.sentiment_neutral_rounded, size: size * 0.26, color: AppColors.navy),
          badge: Icons.search_off_rounded,
        );
      case StatusKind.empty:
      case StatusKind.noInternet:
        return _browserCard(
          child: Icon(Icons.inbox_outlined, size: size * 0.26, color: AppColors.navy),
          badge: Icons.add_rounded,
        );
    }
  }

  /// A little "window" card with three dots, the subject inside and a round
  /// green badge on its corner.
  Widget _browserCard({required Widget child, required IconData badge}) {
    final w = size * 0.62;
    final h = size * 0.5;
    return SizedBox(
      width: w + size * 0.1,
      height: h + size * 0.1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: size * 0.08,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(size * 0.07),
                border: Border.all(color: AppColors.navy, width: 2.2),
                boxShadow: const [BoxShadow(color: Color(0x1A0D253A), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: Column(
                children: [
                  Container(
                    height: h * 0.2,
                    padding: EdgeInsets.symmetric(horizontal: size * 0.04),
                    decoration: BoxDecoration(
                      color: _warm,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(size * 0.05)),
                    ),
                    child: Row(
                      children: List.generate(
                        3,
                        (_) => Container(
                          width: size * 0.028,
                          height: size * 0.028,
                          margin: EdgeInsets.only(right: size * 0.018),
                          decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: Center(child: child)),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.22,
              height: size * 0.22,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(badge, color: Colors.white, size: size * 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
