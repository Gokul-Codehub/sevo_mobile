import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../../logistics/domain/logistics_providers.dart';
import '../../../../shared/utils/app_toast.dart';

/// Screen 3: Location Access
/// Redesigned 2026-10-22: map-pin photo hero over a curved white sheet, same
/// layout language as the sign-in prompt. Behaviour is unchanged.
class LocationAccessScreen extends ConsumerStatefulWidget {
  const LocationAccessScreen({super.key});

  @override
  ConsumerState<LocationAccessScreen> createState() =>
      _LocationAccessScreenState();
}

class _LocationAccessScreenState extends ConsumerState<LocationAccessScreen> {
  bool _isLoadingGps = false;

  /// Added 2026-09-19 per explicit request ("we dont ask to login there
  /// when user is new to the applicaiotn... ask user to logn also give
  /// access to skip") — a first-time, still-logged-out customer sees the
  /// skippable [AuthPromptScreen] once, right after this screen, instead of
  /// landing straight on Home. Already-logged-in customers (or anyone who's
  /// been through this once and skipped/signed in before) go straight to
  /// Home exactly as before — this only inserts one extra, skippable step
  /// into the very first run.
  void _proceedFromLocation() {
    if (!mounted) return;
    final isAuthenticated = ref.read(isUserAuthenticatedProvider);
    context.go(isAuthenticated ? AppRoutes.home : AppRoutes.authPrompt);
  }

  Future<void> _handleUseCurrentLocation() async {
    setState(() => _isLoadingGps = true);
    var detected = false;
    try {
      final notifier = ref.read(customerLocationProvider.notifier);
      detected = await notifier.detectAndSetCurrentLocation(openSettingsIfBlocked: true);
    } catch (_) {
      // Fallback is handled safely inside notifier
    }
    if (!mounted) return;
    setState(() => _isLoadingGps = false);
    if (detected) {
      _proceedFromLocation();
    } else {
      // "No thanks" / permission denied: stay here so the customer can turn
      // location on (tap the button again) or enter the place by hand.
      AppToast.show(
        context,
        'Location is off. Turn it on, or enter your location manually.',
        type: AppToastType.error,
      );
    }
  }

  /// Fixed 2026-09-19: this used to fire-and-forget `context.push(...)`, so
  /// picking an address manually left the customer stranded back on THIS
  /// screen instead of continuing into the app — now awaits the picked
  /// [Address] and only continues (to the auth prompt or Home) once one was
  /// actually selected, same as the GPS path above.
  Future<void> _handleEnterManually() async {
    // Logged-in users pick a saved address (an Address); guests get the
    // no-login picker (true). Either way, a non-null result means a location is set.
    final picked = await context.push<Object?>('/addresses?select=true');
    if (picked != null) _proceedFromLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: LayoutBuilder(
        builder: (context, c) {
          final heroH = c.maxHeight * 0.44;
          return Stack(
            children: [
              // ── Hero photo ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: heroH + 40, // runs under the sheet's rounded corners
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/location_hero.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0.35, 0),
                      errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.navy),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.black.withValues(alpha: 0.45),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 0, 0),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.go(AppRoutes.home);
                                }
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(Icons.arrow_back_rounded, color: AppColors.navy, size: 20),
                              ),
                            ),
                          ),
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
                          'Where do you need\nthe service?',
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
                          "We'll show services near your location, with the right slots and prices for your area.",
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _isLoadingGps ? null : _handleUseCurrentLocation,
                            icon: _isLoadingGps
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.my_location_rounded, size: 20),
                            label: Text(
                              _isLoadingGps ? 'Locating...' : 'Use Current Location',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.6),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton.icon(
                            onPressed: _handleEnterManually,
                            icon: const Icon(Icons.search_rounded, size: 20, color: AppColors.navy),
                            label: const Text(
                              'Enter Location Manually',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.navy, width: 1.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textHint),
                            SizedBox(width: 6),
                            Text(
                              'Your location is only used to find nearby services',
                              style: TextStyle(fontSize: 11, color: AppColors.textHint),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
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
