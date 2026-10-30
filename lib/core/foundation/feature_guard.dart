import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../navigation/safe_back.dart';
import 'foundation_controller.dart';

/// Wraps a module's entry route. When the server turned the feature flag off, or put just this
/// module into maintenance, the module is replaced by a friendly "temporarily unavailable" page -
/// also for deep links and notification taps. An unknown flag leaves the module available.
class FeatureGuard extends ConsumerWidget {
  const FeatureGuard({super.key, required this.flag, required this.child, this.module, this.label = 'This service'});

  final String flag;
  final String? module;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(featureFlagProvider(flag));
    final blocked = ref.watch(foundationControllerProvider.select((s) => s.config.maintenance.blocksModule(module ?? flag)));
    if (on && !blocked) return child;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.goBack),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.navy,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction_rounded, size: 56, color: AppColors.navy),
              const SizedBox(height: 18),
              Text('$label is temporarily unavailable',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.navy)),
              const SizedBox(height: 8),
              const Text('We are working on it. Please try again in a little while.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, height: 1.4)),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: context.goBack,
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
