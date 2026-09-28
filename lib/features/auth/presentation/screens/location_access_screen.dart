import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../addresses/domain/address_models.dart';
import '../../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../../logistics/domain/logistics_providers.dart';

/// Screen 3: Location Access
/// Allows customer to enable GPS or enter location manually matching reference screen 3.
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
    try {
      final notifier = ref.read(customerLocationProvider.notifier);
      await notifier.detectAndSetCurrentLocation();
    } catch (_) {
      // Fallback is handled safely inside notifier
    } finally {
      if (mounted) {
        setState(() => _isLoadingGps = false);
        _proceedFromLocation();
      }
    }
  }

  /// Fixed 2026-09-19: this used to fire-and-forget `context.push(...)`, so
  /// picking an address manually left the customer stranded back on THIS
  /// screen instead of continuing into the app — now awaits the picked
  /// [Address] and only continues (to the auth prompt or Home) once one was
  /// actually selected, same as the GPS path above.
  Future<void> _handleEnterManually() async {
    final address = await context.push<Address>('/addresses?select=true');
    if (address != null) _proceedFromLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // ── Headline ──
              const Text(
                'Where do you need\nthe service?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                  height: 1.25,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "We'll show services near\nyour location",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),

              const Spacer(),

              // ── Map Pin Illustration ──
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Circular map background
                      Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF1F5F9),
                          border: Border.all(
                            color: AppColors.border,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: CustomPaint(
                            painter: _MapRoadsPainter(),
                          ),
                        ),
                      ),

                      // Ripple circle
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),

                      // Green Pin Icon
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x3305A357),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // ── Use Current Location Button ──
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── OR Divider ──
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppColors.divider)),
                ],
              ),

              const SizedBox(height: 16),

              // ── Enter Location Manually Button ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: _handleEnterManually,
                  icon: const Icon(Icons.search_rounded, size: 20, color: AppColors.navy),
                  label: const Text(
                    'Enter Location Manually',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: AppColors.border, width: 1.2),
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter to draw subtle map grid roads inside circular graphic
class _MapRoadsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final thinPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Roads
    canvas.drawLine(Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.4), paint);
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.6), paint);
    canvas.drawLine(Offset(size.width * 0.4, 0), Offset(size.width * 0.45, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.75, 0), Offset(size.width * 0.7, size.height), paint);
    canvas.drawLine(Offset(0, size.height * 0.8), Offset(size.width, size.height * 0.85), thinPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
