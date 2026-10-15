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
import '../../../../core/navigation/safe_back.dart';

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

  // Redesigned flow: 0 = map picker, 1 = details form.
  int _stage = 0;
  bool _visitedDetails = false;
  bool _satellite = false;
  bool _searching = false;
  final _searchController = TextEditingController();
  String _placeTitle = '';
  String _placeLine = '';
  String _lastAutoLine2 = '';

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
    _stage = addr == null ? 0 : 1;
    _visitedDetails = addr != null;
    if (addr != null) {
      _placeLine = addr.formattedAddress;
      _placeTitle = addr.addressLine2 ?? addr.city;
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
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
        // Only overwrite the street line when it is empty or still holds
        // the previous auto-filled value (never the customer's own text).
        if (streetBits.isNotEmpty &&
            (_line2Controller.text.trim().isEmpty ||
                _line2Controller.text.trim() == _lastAutoLine2)) {
          _line2Controller.text = streetBits;
          _lastAutoLine2 = streetBits;
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
        final area = [p.subLocality, p.locality]
            .where((s) => s != null && s.trim().isNotEmpty)
            .map((s) => s!.trim())
            .toList();
        final line = [
          streetBits,
          if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
          [
            if ((p.administrativeArea ?? '').trim().isNotEmpty)
              p.administrativeArea!.trim(),
            if ((p.postalCode ?? '').trim().isNotEmpty) p.postalCode!.trim(),
          ].join(' - '),
        ].where((s) => s.isNotEmpty).join(', ');
        if (mounted) {
          setState(() {
            _placeTitle = area.isNotEmpty ? area.first : 'Selected location';
            _placeLine = line;
          });
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
      context.goBack();
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Redesigned address flow (2026-10-14, per the UI requirement image):
  //   stage 0 — full-screen map with a fixed centre pin, search bar and a
  //             "Confirm your service location" sheet;
  //   stage 1 — "Address details" form with a small map card + Change
  //             Location, address-type pills and bordered fields.
  // New addresses start at stage 0; editing starts at stage 1. All save /
  // geocode / serviceability logic is unchanged.
  // ───────────────────────────────────────────────────────────────────────
  Future<void> _searchPlace(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final results = await locationFromAddress(q);
      if (results.isNotEmpty) {
        final l = results.first;
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(l.latitude, l.longitude), 16),
        );
      } else {
        _showLocationError('No results for "$q".');
      }
    } catch (_) {
      _showLocationError('Could not find that place. Try a different search.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {bool loading = false}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(13),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: AppColors.navy, size: 22),
        ),
      ),
    );
  }

  Widget _buildMapStage() {
    final target = LatLng(_currentLat, _currentLng);
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: target, zoom: 16),
              onMapCreated: (c) => _mapController = c,
              mapType: _satellite ? MapType.hybrid : MapType.normal,
              onCameraMove: (pos) {
                _currentLat = pos.target.latitude;
                _currentLng = pos.target.longitude;
              },
              onCameraIdle: () {
                if (!mounted) return;
                setState(() {});
                _reverseGeocodeAndFillFields(_currentLat, _currentLng);
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // Fixed centre pin + hint tooltip (the map moves under it).
          Align(
            alignment: Alignment.center,
            child: IgnorePointer(
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Move pin to set your exact location',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.location_on_rounded,
                        size: 52, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),

          // Back + search
          Positioned(
            top: topPad + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _circleButton(Icons.arrow_back_rounded, () {
                  if (_visitedDetails) {
                    setState(() => _stage = 1);
                  } else {
                    context.goBack();
                  }
                }),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _searchPlace,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search for area, landmark...',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.textSecondary),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Locate-me / map-type buttons
          Positioned(
            right: 14,
            bottom: 268 + bottomPad,
            child: Column(
              children: [
                _circleButton(Icons.my_location_rounded,
                    _isLocating ? () {} : _handleUseCurrentLocation,
                    loading: _isLocating),
                const SizedBox(height: 10),
                _circleButton(
                  Icons.layers_rounded,
                  () => setState(() => _satellite = !_satellite),
                ),
              ],
            ),
          ),

          // Confirm sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomPad),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD5DAE1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Confirm ',
                          style: TextStyle(
                              fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                        ),
                        TextSpan(
                          text: 'your service location',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, color: AppColors.navy),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: AppColors.primary, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _placeTitle.isEmpty ? 'Selected location' : _placeTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.navy),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _placeLine.isEmpty
                                    ? '${_currentLat.toStringAsFixed(5)}, ${_currentLng.toStringAsFixed(5)}'
                                    : _placeLine,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _goToDetails,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Edit',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _goToDetails,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(88, 54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Confirm and add details',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goToDetails() {
    setState(() {
      _visitedDetails = true;
      _stage = 1;
    });
  }

  InputDecoration _fieldDecoration(String label, IconData icon, {String? hint}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 22),
      labelStyle: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      floatingLabelStyle: const TextStyle(
          fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: border(const Color(0xFFE2E8F0)),
      enabledBorder: border(const Color(0xFFE2E8F0)),
      focusedBorder: border(AppColors.primary, 1.5),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 1.5),
    );
  }

  Widget _typePill(String value, String label, IconData icon) {
    final selected = _addressType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _addressType = value),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : Colors.white,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 19,
                  color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.primary : AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsStage() {
    final currentPincode = _pincodeController.text.trim();
    // Always check against the live pinned coordinates (see 2026-10-06 note).
    final serviceabilityAsync = ref.watch(serviceabilityProvider((
      pincode: currentPincode,
      lat: _currentLat,
      lng: _currentLng,
    )));
    final target = LatLng(_currentLat, _currentLng);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () {
            if (widget.initialAddress == null) {
              setState(() => _stage = 0);
            } else {
              context.goBack();
            }
          },
        ),
        title: Text(
          widget.initialAddress == null ? 'Address details' : 'Edit address',
          style: const TextStyle(
              color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 16.5),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Map card + chosen location
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 130,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: GoogleMap(
                                  key: ValueKey('mini_${_currentLat}_$_currentLng'),
                                  initialCameraPosition:
                                      CameraPosition(target: target, zoom: 15.5),
                                  liteModeEnabled: true,
                                  zoomControlsEnabled: false,
                                  myLocationButtonEnabled: false,
                                  mapToolbarEnabled: false,
                                  compassEnabled: false,
                                  markers: {
                                    Marker(
                                      markerId: const MarkerId('address_pin'),
                                      position: target,
                                    ),
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: GestureDetector(
                                onTap: () => setState(() => _stage = 0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_rounded,
                                          size: 14, color: AppColors.primary),
                                      SizedBox(width: 5),
                                      Text('Change Location',
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.primary)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_on_rounded,
                                  size: 20, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _placeTitle.isEmpty
                                        ? 'Selected location'
                                        : _placeTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navy),
                                  ),
                                  if (_placeLine.isNotEmpty)
                                    Text(
                                      _placeLine,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          height: 1.3,
                                          color: AppColors.textSecondary),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                const Text('Select address type',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _typePill('home', 'Home', Icons.home_rounded),
                    const SizedBox(width: 10),
                    _typePill('work', 'Office', Icons.business_rounded),
                    const SizedBox(width: 10),
                    _typePill('other', 'Other', Icons.location_on_outlined),
                  ],
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _line1Controller,
                  decoration: _fieldDecoration(
                      'Flat / House No., Floor, Building *', Icons.apartment_rounded),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Please enter house/building info'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _line2Controller,
                  decoration: _fieldDecoration(
                      'Street, Sector, Area', Icons.signpost_outlined),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _landmarkController,
                  decoration: _fieldDecoration(
                      'Nearby Landmark (Optional)', Icons.flag_outlined),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityController,
                        decoration:
                            _fieldDecoration('City *', Icons.location_city_rounded),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _stateController,
                        decoration: _fieldDecoration('State *', Icons.map_outlined),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pincodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: _fieldDecoration('PIN Code *', Icons.pin_drop_outlined)
                      .copyWith(counterText: ''),
                  onChanged: (v) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().length != 6) {
                      return 'Enter 6-digit PIN';
                    }
                    return null;
                  },
                ),

                // Live serviceability banner (reflects the pinned location).
                const SizedBox(height: 14),
                serviceabilityAsync.when(
                  loading: () => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Checking service availability...',
                            style: TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                  data: (result) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: result.isServiceable
                          ? const Color(0xFFEAF8EF)
                          : AppColors.errorLight,
                      borderRadius: BorderRadius.circular(12),
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
                              fontSize: 11.5,
                              color: result.isServiceable
                                  ? AppColors.primaryDark
                                  : AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Make this my default address',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: const Text('Used automatically during service checkout',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary)),
                    value: _isDefault,
                    onChanged: (val) => setState(() => _isDefault = val),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            16, 10, 16, 14 + MediaQuery.of(context).padding.bottom),
        color: const Color(0xFFF7F9FC),
        child: SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleSave,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(88, 54),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Address',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: (_stage == 0 && !_visitedDetails) ||
          (_stage == 1 && widget.initialAddress != null),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _stage = _stage == 1 ? 0 : 1);
      },
      child: _stage == 0 ? _buildMapStage() : _buildDetailsStage(),
    );
  }
}
