import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../../../shared/utils/app_toast.dart';

/// "Enter location manually" for people who are not logged in.
///
/// A location is needed to use the app at all (what is served depends on it),
/// but an account is only needed to BOOK. So this screen needs no login: the
/// customer types an address line, area, city, state and pincode (or uses
/// GPS) and we store it as the browsing location. Pops `true` once a location
/// has been set.
class GuestLocationPickerScreen extends ConsumerStatefulWidget {
  const GuestLocationPickerScreen({super.key});

  @override
  ConsumerState<GuestLocationPickerScreen> createState() => _GuestLocationPickerScreenState();
}

class _GuestLocationPickerScreenState extends ConsumerState<GuestLocationPickerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressLine = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  String? _state;
  bool _busy = false;

  static const _states = <String>[
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa',
    'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala',
    'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland',
    'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura',
    'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
    'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu',
    'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  ];

  @override
  void dispose() {
    _addressLine.dispose();
    _area.dispose();
    _city.dispose();
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _busy = true);
    var detected = false;
    try {
      detected = await ref.read(customerLocationProvider.notifier).detectAndSetCurrentLocation(openSettingsIfBlocked: true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (detected) {
      context.pop(true);
    } else {
      // Stay on this page so the place can be typed in instead.
      AppToast.show(
        context,
        'Location is off. Turn it on, or enter your address below.',
        type: AppToastType.error,
      );
    }
  }

  Future<void> _confirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final line = _addressLine.text.trim();
    final area = _area.text.trim();
    final city = _city.text.trim();
    final state = (_state ?? '').trim();
    final pin = _pincode.text.trim();
    final label = [line, area, city, state, pin].where((p) => p.isNotEmpty).join(', ');
    double? lat;
    double? lng;
    try {
      // Best effort: turn what was typed into coordinates so the app can
      // check serviceability for that exact place.
      final hits = await locationFromAddress('$label, India');
      if (hits.isNotEmpty) {
        lat = hits.first.latitude;
        lng = hits.first.longitude;
      }
    } catch (_) {}
    ref.read(customerLocationProvider.notifier).setManualLocation(
          label,
          pin,
          latitude: lat,
          longitude: lng,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text('Choose your location', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Tell us where you need service. You only need an account when you book.',
              style: TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _busy ? null : _useGps,
              icon: const Icon(Icons.my_location_rounded, size: 20),
              label: const Text('Use my current location'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: AppColors.navy),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(children: [
                Expanded(child: Divider()),
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or enter it', style: TextStyle(color: Color(0xFF9CA3AF)))),
                Expanded(child: Divider()),
              ]),
            ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _addressLine,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('Address line (house / flat / building)', Icons.home_outlined),
                    validator: (v) => (v ?? '').trim().length < 3 ? 'Enter your address line' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _area,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('Area, street or landmark', Icons.place_outlined),
                    validator: (v) => (v ?? '').trim().length < 3 ? 'Enter your area or street' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _city,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('City', Icons.location_city_outlined),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your city' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _state,
                    isExpanded: true,
                    menuMaxHeight: 320,
                    decoration: _dec('State', Icons.map_outlined),
                    items: [
                      for (final st in _states) DropdownMenuItem(value: st, child: Text(st, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _state = v),
                    validator: (v) => (v == null || v.isEmpty) ? 'Select your state' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pincode,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: _dec('Pincode', Icons.pin_drop_outlined),
                    validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Enter a 6-digit pincode',
                    onFieldSubmitted: (_) => _confirm(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: _busy ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Confirm location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      );
}
