import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/sevo_logo.dart';

/// Sign-in prompt, shown once right after Location Access to a first-time
/// customer who hasn't logged in yet.
///
/// Redesigned 2026-10-22: delivery illustration hero with the SEVO logo on a
/// curved white sheet; Sign In (navy), Continue as Guest, and Skip.
/// Still skippable - Checkout, the Grocery Cart and Goods & Transport hard-block
/// booking for guests themselves, so this is only a friendly nudge.
class AuthPromptScreen extends ConsumerWidget {
  const AuthPromptScreen({super.key});

  static const _benefits = <(IconData, String, String)>[
    (Icons.location_on_rounded, 'Saved addresses', 'Book in a couple of taps'),
    (Icons.route_rounded, 'Live tracking', 'Follow your technician in real time'),
    (Icons.receipt_long_rounded, 'All bookings in one place', 'Invoices and history, always handy'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: LayoutBuilder(
        builder: (context, c) {
          final heroH = c.maxHeight * 0.40;
          return Stack(
        children: [
          // ── Hero: delivery illustration with the logo on top ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH + 40, // runs under the sheet's rounded corners
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/auth_hero.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerLeft,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.navy),
                ),
                // Soft darkening at the top so the status bar and Skip stay readable.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        AppColors.navy.withValues(alpha: 0.45),
                        AppColors.navy.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const SevoLogo(width: 84, height: 32),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.go(AppRoutes.home),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sheet ──
          Positioned(
            top: heroH,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sign in for a faster\nbooking experience',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                        height: 1.2,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "You can browse without an account - you'll only need to sign in when you're ready to book.",
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final b in _benefits) ...[
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9EEF4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(b.$1, size: 20, color: AppColors.navy),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.$2,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.navy,
                                  ),
                                ),
                                Text(
                                  b.$3,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () => context.go(AppRoutes.login),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Sign In',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: () => context.go(AppRoutes.home),
                        child: const Text(
                          'Continue as Guest',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
          );
        },
      ),
    );
  }
}
