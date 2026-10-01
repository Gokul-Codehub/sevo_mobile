import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import '../theme/app_colors.dart';

/// Full-screen "You're Offline" state.
///
/// Shown automatically by [ConnectivityGate] the instant the device's
/// network link drops, over whatever screen the customer was already on,
/// and dismissed automatically the instant it's restored — this screen is
/// never pushed/popped and is intentionally NOT registered in
/// app_router.dart; it is a transient overlay, not a route.
class NoInternetScreen extends ConsumerWidget {
  const NoInternetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "You're Offline",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  "Looks like there's no internet connection.\n"
                  "Check your Wi-Fi or mobile data and try again.",
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () {
                    // The stream already re-emits on its own the moment
                    // connectivity actually changes — this just forces an
                    // immediate re-check so a manual tap gives instant
                    // feedback instead of the customer wondering whether
                    // anything happened.
                    ref.invalidate(connectivityStatusProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
