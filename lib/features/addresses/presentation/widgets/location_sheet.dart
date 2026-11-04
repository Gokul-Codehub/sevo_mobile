import '../../../auth/domain/auth_return.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/location_gate.dart';
import '../../../../core/errors/api_error.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../../coverage/data/coverage_repository.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../domain/address_models.dart';
import '../../domain/address_notifier.dart';

/// "Select delivery location": the one place to change where we deliver, opened from the location pill on Home.
/// Same shape as Blinkit / Swiggy / Zomato / Amazon: search a place or pincode, use the current location, or pick a saved
/// address (signed in). Whatever is chosen takes effect at once and is remembered; if we do not deliver there, the
/// customer is told straight away.
Future<void> showLocationSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const LocationSheet(),
    );

class _Place {
  const _Place(this.label, this.pincode, this.lat, this.lng);
  final String label;
  final String pincode;
  final double lat;
  final double lng;
}

class LocationSheet extends ConsumerStatefulWidget {
  const LocationSheet({super.key});

  @override
  ConsumerState<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends ConsumerState<LocationSheet> {
  final _query = TextEditingController();
  // One Google "session" per sheet opening: the typing and the final pick are billed together.
  String _session = _newSession();

  static String _newSession() =>
      List.generate(24, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[Random.secure().nextInt(36)]).join();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  List<_Place> _results = const [];
  bool _searching = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Suggestions as the customer types (Google Places through our server). If place search is unavailable the
  /// list simply stays empty and the search button / keyboard key still finds the place by plain address search.
  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 3) {
      _session = _newSession(); // the search ended: the next one is a new billing session
      setState(() {
        _suggestions = const [];
        _message = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final here = ref.read(customerLocationProvider);
      final r = await ref.read(coverageRepositoryProvider).autocomplete(q, session: _session, lat: here.latitude, lng: here.longitude);
      if (!mounted || _query.text.trim() != q) return; // the customer kept typing
      setState(() {
        _results = const [];
        _suggestions = r is Success<List<PlaceSuggestion>> ? r.data : const [];
        _message = null;
      });
    });
  }

  Future<void> _pickSuggestion(PlaceSuggestion s) async {
    setState(() => _busy = true);
    final r = await ref.read(coverageRepositoryProvider).details(s, session: _session);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Success(:final data):
        await _pickPlace(_Place(data.label, data.pincode, data.lat, data.lng));
      case Failure():
        setState(() => _message = "We couldn't open that place. Try another, or search again.");
    }
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 3) {
      setState(() => _message = 'Type an area, street or a 6-digit pincode.');
      return;
    }
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    setState(() {
      _searching = true;
      _message = null;
      _results = const [];
      _suggestions = const [];
    });
    final found = <_Place>[];
    try {
      final hits = await locationFromAddress('$q, India');
      for (final h in hits.take(4)) {
        String label = q;
        String pin = '';
        try {
          final pm = await placemarkFromCoordinates(h.latitude, h.longitude);
          if (pm.isNotEmpty) {
            final p = pm.first;
            final name = [p.subLocality, p.locality, p.administrativeArea]
                .map((s) => (s ?? '').trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (name.isNotEmpty) label = name.join(', ');
            pin = (p.postalCode ?? '').trim();
          }
        } catch (_) {}
        if (!found.any((f) => f.label == label)) found.add(_Place(label, pin, h.latitude, h.longitude));
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = found;
      if (found.isEmpty) _message = "We couldn't find that place. Check the spelling or try the pincode.";
    });
  }

  /// A choice takes effect at once. If we do not serve the place, Home itself says so (and offers "Notify me"), for
  /// services and groceries alike, so there is nothing more to decide here.
  Future<void> _applied() async {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _pickPlace(_Place p) async {
    ref.read(customerLocationProvider.notifier).setManualLocation(p.label, p.pincode, latitude: p.lat, longitude: p.lng);
    await chooseDeliveryAddress(ref, null); // a chosen place replaces the saved address
    await _applied();
  }

  Future<void> _pickSaved(Address a) async {
    await chooseDeliveryAddress(ref, a);
    await _applied();
  }

  Future<void> _useCurrent() async {
    setState(() => _busy = true);
    final ok = await useCurrentLocationWithHelp(context, ref);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await chooseDeliveryAddress(ref, null);
      await _applied();
    } else {
      setState(() => _message = 'Location is off. Turn it on, or search for your place above.');
    }
  }

  IconData _iconFor(String type) => switch (type.toLowerCase()) {
        'home' => Icons.home_outlined,
        'work' || 'office' => Icons.work_outline_rounded,
        _ => Icons.place_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isUserAuthenticatedProvider);
    final selected = ref.watch(selectedAddressProvider);
    final addresses = signedIn ? ref.watch(addressListProvider).valueOrNull ?? const <Address>[] : const <Address>[];
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select delivery location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search area, street or pincode',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
              ),
            for (final s in _suggestions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined, color: AppColors.navy),
                title: Text(s.main, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: s.secondary.isEmpty ? null : Text(s.secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                onTap: _busy ? null : () => _pickSuggestion(s),
              ),
            for (final p in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined, color: AppColors.navy),
                title: Text(p.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: p.pincode.isEmpty ? null : Text(p.pincode, style: const TextStyle(fontSize: 12)),
                onTap: () => _pickPlace(p),
              ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded, color: Color(0xFF059669)),
              title: const Text('Use my current location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
              onTap: _busy ? null : _useCurrent,
            ),
            const Divider(height: 20),
            if (!signedIn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.login_rounded, color: AppColors.navy),
                title: const Text('Sign in to use your saved addresses', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  requireLoginWith(router, ref);
                },
              )
            else ...[
              const Text('Saved addresses', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.4)),
              for (final a in addresses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_iconFor(a.addressType), color: AppColors.navy),
                  title: Text(a.addressType.isEmpty ? 'Address' : a.addressType[0].toUpperCase() + a.addressType.substring(1),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  subtitle: Text(a.formattedAddress, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  trailing: selected?.id == a.id ? const Icon(Icons.check_circle_rounded, color: Color(0xFF059669)) : null,
                  onTap: () => _pickSaved(a),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_location_alt_outlined, color: AppColors.navy),
                title: const Text('Add new address', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(AppRoutes.addAddress);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
