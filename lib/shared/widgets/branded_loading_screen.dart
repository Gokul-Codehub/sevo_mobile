import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'sevo_logo.dart';

/// Full-screen branded loading state — the SEVO equivalent of the
/// reference screenshot the user shared (Zepto's own splash-style loader:
/// centered brand icon + tagline, with a bottom banner strip).
///
/// Added 2026-09-30 per explicit request ("For entire page redirection
/// during the loading of data show a splash screen like uploaded image...
/// only for more delay/large loading otherwise use skeleton loading").
/// This is deliberately NOT shown for every load — see [SlowLoadGate],
/// which is what decides whether a given wait is long enough to earn this
/// screen instead of the caller's normal skeleton.
class BrandedLoadingScreen extends StatelessWidget {
  const BrandedLoadingScreen({
    super.key,
    this.tagline = 'Good things, on the way',
  });

  /// Short line under the loader — callers can pass something contextual
  /// ("Finding the best technicians near you", "Loading your groceries...")
  /// instead of the generic default.
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SevoLogo(height: 34),
                    const SizedBox(height: 32),
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        tagline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Trusted Home Services & Groceries',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Only on SEVO',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
