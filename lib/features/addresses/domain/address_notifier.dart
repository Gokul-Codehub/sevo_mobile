import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../data/address_repository.dart';
import 'address_models.dart';

/// State notifier for customer addresses list.
class AddressListNotifier extends AsyncNotifier<List<Address>> {
  @override
  Future<List<Address>> build() async {
    // Fixed 2026-09-19 per explicit bug report ("even i doesnot login with
    // any account... it is showig 'Hosur, Tamilnadu' even i am in different
    // city"): a guest has no real saved addresses, but this used to call
    // the addresses API regardless — whatever it returned for a guest
    // session (however that resolved server-side) could get auto-selected
    // below and silently override Home's live GPS-detected location with a
    // stale/default address. Guests now always get an empty address list
    // client-side, with no request sent and nothing ever auto-selected, so
    // Home's location pill can only ever reflect the real, live GPS fix
    // (or an address the user explicitly picked after signing in).
    final isAuthenticated = ref.read(isUserAuthenticatedProvider);
    if (!isAuthenticated) return const [];
    return _fetchAddresses();
  }

  AddressRepository get _repo => ref.read(addressRepositoryProvider);

  Future<List<Address>> _fetchAddresses() async {
    final result = await _repo.getAddresses();
    return switch (result) {
      Success(:final data) => () {
          if (data.isNotEmpty) {
            Future.microtask(() {
              final currentSelected = ref.read(selectedAddressProvider);
              if (currentSelected == null || !data.any((a) => a.id == currentSelected.id)) {
                final defaultAddr = data.firstWhere((a) => a.isDefault, orElse: () => data.first);
                ref.read(selectedAddressProvider.notifier).state = defaultAddr;
              }
            });
          }
          return data;
        }(),
      Failure(:final error) => throw error,
    };
  }

  // ── Refresh list ──────────────────────────────────────────────────────────
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetchAddresses);
  }

  // ── Add new address ───────────────────────────────────────────────────────
  Future<String?> addAddress(Address address) async {
    final result = await _repo.createAddress(address);
    switch (result) {
      case Success(:final data):
        final current = state.valueOrNull ?? [];
        if (data.isDefault) {
          state = AsyncValue.data([
            data,
            ...current.map((a) => a.copyWith(isDefault: false)),
          ]);
        } else {
          state = AsyncValue.data([...current, data]);
        }
        // Also auto-select the newly created address
        ref.read(selectedAddressProvider.notifier).state = data;
        return null;
      case Failure(:final error):
        return error.message;
    }
  }

  // ── Update address ────────────────────────────────────────────────────────
  Future<String?> updateAddress(Address address) async {
    final result = await _repo.updateAddress(address);
    switch (result) {
      case Success(:final data):
        final current = state.valueOrNull ?? [];
        state = AsyncValue.data(
          current.map((a) {
            if (a.id == data.id) return data;
            if (data.isDefault) return a.copyWith(isDefault: false);
            return a;
          }).toList(),
        );
        if (ref.read(selectedAddressProvider)?.id == data.id) {
          ref.read(selectedAddressProvider.notifier).state = data;
        }
        return null;
      case Failure(:final error):
        return error.message;
    }
  }

  // ── Delete address ────────────────────────────────────────────────────────
  Future<String?> deleteAddress(int id) async {
    final result = await _repo.deleteAddress(id);
    switch (result) {
      case Success():
        final current = state.valueOrNull ?? [];
        state = AsyncValue.data(current.where((a) => a.id != id).toList());
        if (ref.read(selectedAddressProvider)?.id == id) {
          final remaining = state.valueOrNull ?? [];
          ref.read(selectedAddressProvider.notifier).state =
              remaining.isNotEmpty ? remaining.first : null;
        }
        return null;
      case Failure(:final error):
        return error.message;
    }
  }

  // ── Set default address ───────────────────────────────────────────────────
  Future<String?> setDefault(int id) async {
    final result = await _repo.setDefaultAddress(id);
    switch (result) {
      case Success(:final data):
        final current = state.valueOrNull ?? [];
        state = AsyncValue.data(
          current.map((a) {
            return a.copyWith(isDefault: a.id == id);
          }).toList(),
        );
        ref.read(selectedAddressProvider.notifier).state = data;
        return null;
      case Failure(:final error):
        return error.message;
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────
final addressListProvider =
    AsyncNotifierProvider<AddressListNotifier, List<Address>>(
  AddressListNotifier.new,
);

/// Currently selected address for active booking (independent StateProvider).
final selectedAddressProvider = StateProvider<Address?>((ref) => null);
