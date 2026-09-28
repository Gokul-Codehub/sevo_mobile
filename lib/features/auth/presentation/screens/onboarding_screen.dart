import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';

/// Screen 2: Onboarding
/// Multi-slide introduction with floating service badges matching reference screen 2.
///
/// Fixed 2026-09-19: this screen (and the LocationAccessScreen it now leads
/// into) used to be unreachable — SplashScreen always skipped straight to
/// Home. See SplashScreen's doc comment for the fix; this screen's own
/// change is just where "Skip"/"Get Started" go next (LocationAccessScreen
/// instead of Home directly) and marking onboarding as seen so it's a
/// once-per-install experience, not shown again on future launches.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final _slides = const [
    _OnboardingSlideData(
      title: 'Everything your\nhome needs',
      subtitle: 'Cleaning, AC, Plumbing,\nElectrical & more.',
      badges: [
        (Icons.cleaning_services_rounded, 'Cleaning'),
        (Icons.chair_rounded, 'Sofa Care'),
        (Icons.ac_unit_rounded, 'AC Service'),
        (Icons.bolt_rounded, 'Electrical'),
        (Icons.build_rounded, 'Plumbing'),
      ],
    ),
    _OnboardingSlideData(
      title: 'Verified Experts\nat Your Doorstep',
      subtitle: 'Trained, background-verified\nand insured professionals.',
      badges: [
        (Icons.verified_user_rounded, 'Verified'),
        (Icons.shield_rounded, 'Warranty'),
        (Icons.timer_rounded, 'On-Time'),
        (Icons.star_rounded, 'Top Rated'),
        (Icons.price_check_rounded, 'Fixed Price'),
      ],
    ),
    _OnboardingSlideData(
      title: 'Real-Time Tracking\n& Easy Payment',
      subtitle: 'Live technician GPS tracking\nand secure Razorpay checkout.',
      badges: [
        (Icons.location_on_rounded, 'Live Map'),
        (Icons.lock_rounded, 'Secure'),
        (Icons.credit_card_rounded, 'UPI / Card'),
        (Icons.headset_mic_rounded, 'Support'),
        (Icons.receipt_long_rounded, 'Invoice'),
      ],
    ),
  ];

  void _handleNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    await ref.read(secureStorageProvider).setOnboardingSeen();
    if (!mounted) return;
    context.go(AppRoutes.locationAccess);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentPage];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar with Skip ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Title & Subtitle ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    slide.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                      height: 1.25,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    slide.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // ── Center Technician Illustration with Floating Badges ──
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  return _TechnicianGraphicWidget(badges: _slides[index].badges);
                },
              ),
            ),

            // ── Bottom Progress Dots & Next Button ──
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? AppColors.primary
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Next / Get Started Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _handleNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPage == _slides.length - 1
                            ? 'Get Started'
                            : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.title,
    required this.subtitle,
    required this.badges,
  });

  final String title;
  final String subtitle;
  final List<(IconData, String)> badges;
}

class _TechnicianGraphicWidget extends StatelessWidget {
  const _TechnicianGraphicWidget({required this.badges});

  final List<(IconData, String)> badges;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 320,
        height: 320,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Center circular glow
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryLight.withValues(alpha: 0.7),
              ),
            ),

            // Center avatar / technician graphic
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.navy,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.engineering_rounded,
                size: 88,
                color: Colors.white,
              ),
            ),

            // Floating badge 1: Top Left
            if (badges.isNotEmpty)
              Positioned(
                top: 24,
                left: 16,
                child: _FloatingBadge(
                  icon: badges[0].$1,
                  color: AppColors.primary,
                ),
              ),

            // Floating badge 2: Top Right
            if (badges.length > 1)
              Positioned(
                top: 20,
                right: 20,
                child: _FloatingBadge(
                  icon: badges[1].$1,
                  color: const Color(0xFF3B82F6),
                ),
              ),

            // Floating badge 3: Middle Left
            if (badges.length > 2)
              Positioned(
                top: 130,
                left: 0,
                child: _FloatingBadge(
                  icon: badges[2].$1,
                  color: const Color(0xFFF59E0B),
                ),
              ),

            // Floating badge 4: Middle Right
            if (badges.length > 3)
              Positioned(
                top: 130,
                right: 0,
                child: _FloatingBadge(
                  icon: badges[3].$1,
                  color: const Color(0xFF8B5CF6),
                ),
              ),

            // Floating badge 5: Bottom Center-Right
            if (badges.length > 4)
              Positioned(
                bottom: 24,
                right: 32,
                child: _FloatingBadge(
                  icon: badges[4].$1,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBadge extends StatelessWidget {
  const _FloatingBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
