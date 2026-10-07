import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../domain/address_models.dart';
import '../../domain/address_notifier.dart';

/// Screen to create or edit a customer address with live map pin & service zone check.
class AddEditAddressScreen extends ConsumerStatefulWidget {
  const AddEditAddressScreen({
    super.key,
    this.initialAddress,
  });

  final Address? initialAddress;

  @override
  ConsumerState<AddEditAddressScreen> createState() =>
      _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends ConsumerState<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _line1Controller;
  late final TextEditingController _line2Controller;
  late final TextEditingController _landmarkController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _pincodeController;

  String _addressType = 'home';
  bool _isDefault = false;
  bool _isLoading = false;
  bool _isLocating = false;

  double _currentLat = 12.754598;
  double _currentLng = 77.834477;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    final addr = widget.initialAddress;
    _line1Controller = TextEditingController(text: addr?.addressLine1 ?? '');
    _line2Controller = TextEditingController(text: addr?.addressLine2 ?? '');
    _landmarkController = TextEditingController(text: addr?.landmark ?? '');
    _cityController = TextEditingController(text: addr?.city ?? 'Hosur');
    _stateController = TextEditingController(text: addr?.state ?? 'Tamil Nadu');
    _pincodeController = TextEditingController(text: addr?.postalCode ?? '635109');
    _addressType = addr?.addressType ?? 'home';
    _isDefault = addr?.isDefault ?? false;
    _currentLat = addr?.latitude ?? 12.754598;
    _currentLng = addr?.longitude ?? 77.834477;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _line1Controller.dispose();
    _line2Controller.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  // ── Use current location ──────────────────────────────────────────────────
  // Added 2026-08-27: previously there was no way to auto-fill this form from
  // the device's actual GPS position — every address had to be typed and
  // pinned by hand. This fetches the real device location (with proper
  // permission handling) and reverse-geocodes it into the address fields,
  // instead of leaving them at the hardcoded Hosur default.
  Future<void> _handleUseCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError(
          'Location services are turned off. Please enable GPS and try again.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permission was denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationError(
          'Location permission is permanently denied. Enable it from app settings.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );

      await _reverseGeocodeAndFillFields(position.latitude, position.longitude);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location detected. Please confirm the details below.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showLocationError('Could not detect your location. Please try again.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // Fixed 2026-10-06: this reverse-geocode (coordinates -> City/State/PIN
  // Code text fields) used to run only after "Use Current Location" — not
  // when the customer tapped or dragged the pin directly on the map, which
  // is the most common way to place it. That left the PIN Code field (and
  // so the serviceability banner below, keyed off it) stuck on whatever it
  // last held — the default Hosur PIN code on a brand new address — no
  // matter where the pin actually moved to. Extracted so onTap/onDragEnd
  // (see the GoogleMap below) can call the same logic. Best-effort: on
  // failure (no network, no result) the pinned coordinates are still kept —
  // only the text fields are left for the customer to fill in by hand.
  Future<void> _reverseGeocodeAndFillFields(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final streetBits = [p.street, p.subLocality]
            .where((s) => s != null && s.trim().isNotEmpty)
            .join(', ');
        if (streetBits.isNotEmpty && _line2Controller.text.trim().isEmpty) {
          _line2Controller.text = streetBits;
        }
        if ((p.locality ?? '').trim().isNotEmpty) {
          _cityController.text = p.locality!.trim();
        }
        if ((p.administrativeArea ?? '').trim().isNotEmpty) {
          _stateController.text = p.administrativeArea!.trim();
        }
        if ((p.postalCode ?? '').trim().isNotEmpty) {
          _pincodeController.text = p.postalCode!.trim();
        }
      }
    } catch (_) {
      // Reverse geocoding is best-effort — pinned coordinates are still set.
    }
  }

  void _showLocationError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final newAddress = Address(
      id: widget.initialAddress?.id ?? 0,
      addressLine1: _line1Controller.text.trim(),
      addressLine2: _line2Controller.text.trim().isEmpty
          ? null
          : _line2Controller.text.trim(),
      landmark: _landmarkController.text.trim().isEmpty
          ? null
          : _landmarkController.text.trim(),
      city: _cityController.text.trim(),
      state: _stateController.text.trim(),
      postalCode: _pincodeController.text.trim(),
      addressType: _addressType,
      latitude: _currentLat,
      longitude: _currentLng,
      isDefault: _isDefault,
    );

    final String? error;
    if (widget.initialAddress == null) {
      error = await ref
          .read(addressListProvider.notifier)
          .addAddress(newAddress);
    } else {
      error = await ref
          .read(addressListProvider.notifier)
          .updateAddress(newAddress);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      if (_isDefault || ref.read(selectedAddressProvider) == null) {
        ref.read(selectedAddressProvider.notifier).state = newAddress;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Address saved successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPincode = _pincodeController.text.trim();
    // Fixed 2026-10-06: always check against the live pinned coordinates
    // (always present — defaults to Hosur) rather than gating on a 6-digit
    // PIN code that a freshly-dropped pin may not have resolved yet.
    final serviceabilityAsync = ref.watch(serviceabilityProvider((
      pincode: currentPincode,
      lat: _currentLat,
      lng: _currentLng,
    )));

    final targetPos = LatLng(_currentLat, _currentLng);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.initialAddress == null ? 'Add New Address' : 'Edit Address',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Map Location Pin Picker Card
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: targetPos,
                          zoom: 14.5,
                        ),
                        onMapCreated: (c) => _mapController = c,
                        // Fixed 2026-10-06 ("the map could not be move it
                        // has fixed"): a GoogleMap nested inside a
                        // SingleChildScrollView loses every pan/drag gesture
                        // to the ancestor scroll view's own vertical drag
                        // recognizer — Flutter's gesture arena hands drags
                        // to the Scrollable by default, so the map behaves
                        // as if frozen even though nothing disabled it.
                        // EagerGestureRecognizer (built into
                        // package:flutter/gestures.dart) claims the gesture
                        // for the map immediately instead of waiting to lose
                        // that arbitration — the standard fix for Google
                        // Maps Flutter embedded in a scrollable.
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                        onTap: (latLng) {
                          setState(() {
                            _currentLat = latLng.latitude;
                            _currentLng = latLng.longitude;
                          });
                          // Fixed 2026-10-06: tapping/dragging the pin used
                          // to leave City/State/PIN Code — and so the
                          // serviceability banner below, keyed off them —
                          // stuck on whatever they last held. Now every pin
                          // move re-resolves them for the new spot.
                          _reverseGeocodeAndFillFields(
                              latLng.latitude, latLng.longitude);
                        },
                        markers: {
                          Marker(
                            markerId: const MarkerId('address_pin'),
                            position: targetPos,
                            draggable: true,
                            onDragEnd: (newPos) {
                              setState(() {
                                _currentLat = newPos.latitude;
                                _currentLng = newPos.longitude;
                              });
                              _reverseGeocodeAndFillFields(
                                  newPos.latitude, newPos.longitude);
                            },
                          ),
                        },
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Tap to pin service location',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Use Current Location button — fetches real GPS coordinates
                // and reverse-geocodes them into the fields below.
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _isLocating ? null : _handleUseCurrentLocation,
                    icon: _isLocating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(
                      _isLocating ? 'Detecting location...' : 'Use Current Location',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Address Type Chips
                Text(
                  'Address Type',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.home_outlined, size: 16),
                      label: const Text('Home'),
                      selected: _addressType == 'home',
                      onSelected: (val) {
                        if (val) setState(() => _addressType = 'home');
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      avatar: const Icon(Icons.business_outlined, size: 16),
                      label: const Text('Work'),
                      selected: _addressType == 'work',
                      onSelected: (val) {
                        if (val) setState(() => _addressType = 'work');
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      avatar: const Icon(Icons.location_on_outlined, size: 16),
                      label: const Text('Other'),
                      selected: _addressType == 'other',
                      onSelected: (val) {
                        if (val) setState(() => _addressType = 'other');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Flat / House / Building
                TextFormField(
                  controller: _line1Controller,
                  decoration: const InputDecoration(
                    labelText: 'Flat / House No., Floor, Building *',
                    hintText: 'e.g. Flat 302, Prestige Tower',
                    prefixIcon: Icon(Icons.apartment_outlined),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Please enter house/building info'
                      : null,
                ),
                const SizedBox(height: 16),

                // Street / Area
                TextFormField(
                  controller: _line2Controller,
                  decoration: const InputDecoration(
                    labelText: 'Street, Sector, Area',
                    hintText: 'e.g. 12th Main, Indiranagar',
                    prefixIcon: Icon(Icons.signpost_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                // Landmark
                TextFormField(
                  controller: _landmarkController,
                  decoration: const InputDecoration(
                    labelText: 'Nearby Landmark (Optional)',
                    hintText: 'e.g. Near Metro Station',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                // City & State Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(
                          labelText: 'City *',
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _stateController,
                        decoration: const InputDecoration(
                          labelText: 'State *',
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Pincode
                TextFormField(
                  controller: _pincodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'PIN Code *',
                    counterText: '',
                    prefixIcon: Icon(Icons.pin_drop_outlined),
                  ),
                  onChanged: (v) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().length != 6) {
                      return 'Enter 6-digit PIN';
                    }
                    return null;
                  },
                ),

                // Live Serviceability Status Banner — always shown now
                // (the pin always has coordinates, Hosur default included),
                // so it reflects the actual pinned location, not just a
                // typed PIN code.
                ...[
                  const SizedBox(height: 14),
                  serviceabilityAsync.when(
                    loading: () => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Checking service availability...',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    error: (error, stackTrace) => const SizedBox.shrink(),
                    data: (result) => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: result.isServiceable
                            ? AppColors.surfaceVariant
                            : AppColors.errorLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            result.isServiceable
                                ? Icons.verified_rounded
                                : Icons.error_outline_rounded,
                            size: 18,
                            color: result.isServiceable
                                ? AppColors.primary
                                : AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              result.message,
                              style: TextStyle(
                                fontSize: 12,
                                color: result.isServiceable
                                    ? AppColors.primaryDark
                                    : AppColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Set as default address switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Make this my default address',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Used automatically during service checkout',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  value: _isDefault,
                  onChanged: (val) => setState(() => _isDefault = val),
                ),

                const SizedBox(height: 32),

                // Save button
                FilledButton(
                  onPressed: _isLoading ? null : _handleSave,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Address'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
