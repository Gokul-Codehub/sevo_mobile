import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../data/pricing_repository.dart';
import 'pricing_models.dart';

/// Holds the live, admin-configured pricing. Starts with [PricingConfig.fallback]
/// (the exact values that used to be hardcoded) so every screen that reads
/// this has a correct number to show immediately — no loading flicker, no
/// risk of a ₹0 fee — then silently swaps in the real values once the
/// backend responds. If the fetch fails for any reason (offline, backend
/// down), it just keeps the fallback — pricing never breaks checkout.
///
/// Exposed as a plain [Provider] (not a FutureProvider) specifically so
/// synchronous consumers like cartSummaryProvider and checkout_screen.dart's
/// build() can `ref.watch` it without an AsyncValue wrapper.
class PricingConfigNotifier extends Notifier<PricingConfig> {
  @override
  PricingConfig build() {
    _refresh();
    return PricingConfig.fallback;
  }

  Future<void> _refresh() async {
    try {
      final repo = ref.read(pricingRepositoryProvider);
      final result = await repo.getPricingConfig();
      if (result is Success<PricingConfig>) {
        state = result.data;
      }
      // On Failure, silently keep whatever state is already set (the
      // fallback, or a previously-fetched real value) — a pricing fetch
      // failure must never surface as a broken checkout.
    } catch (_) {
      // Defensive: should already be caught inside the repository, but
      // never let a pricing refresh crash the app that called it.
    }
  }

  /// Lets a screen force a fresh read (e.g. pull-to-refresh on checkout)
  /// without waiting for the next app restart.
  Future<void> refreshNow() => _refresh();
}

final pricingConfigProvider =
    NotifierProvider<PricingConfigNotifier, PricingConfig>(
  PricingConfigNotifier.new,
);
