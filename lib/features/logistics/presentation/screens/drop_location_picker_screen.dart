import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/logistics_providers.dart';

/// Added 2026-09-20 per explicit request: "add a privilege for drop-off
/// address to choose on Map." Mirrors the existing map-pin pattern already
/// used by `AddEditAddressScreen` (tap/drag a marker, reverse-geocode for a
/// readable address, "Use current location" shortcut) rather than
/// introducing a new pattern.
///
/// This exists specifically because a free-text-only drop address cannot
/// satisfy the backend's authoritative fare resolution
/// (`resolve_logistics_fare_v2` in service_requests/views.py requires real
/// `drop_latitude`/`drop_longitude` for any distance-priced tier — see the
/// file-level note in logistics_models.dart) — so picking a real point on
/// the map is required, not a convenience.
///
/// Returns a [PickedDropLocation] via `context.pop(result)`, or `null` if
/// the customer backs out without confirming.
class DropLocationPickerScreen extends StatefulWidget {
  const DropLocationPickerScreen({super.key, this.initial});

  final PickedDropLocation? initial;

  @override
  State<DropLocationPickerScreen> createState() => _DropLocationPickerScreenState();
}

class _DropLocationPickerScreenState extends State<DropLocationPickerScreen> {
  double _lat = 12.754598;
  double _lng = 77.834477;
  String _address = '';
  bool _isLocating = false;
  bool _isResolvingAddress = false;
  bool _isMapMoving = false;
  int _geocodeSeq = 0;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _lat = widget.initial!.latitude;
      _lng = widget.initial!.longitude;
      _address = widget.initial!.address;
    } else {
      _reverseGeocode(_lat, _lng);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    final seq = ++_geocodeSeq;
    setState(() => _isResolvingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (seq != _geocodeSeq) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.name,
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.postalCode,
        ].where((s) => s != null && s.trim().isNotEmpty).toSet().toList();
        if (mounted) {
          setState(() => _address = parts.join(', '));
        }
      }
    } catch (_) {
      // Reverse geocoding is best-effort — the pinned coordinates are still
      // valid and usable even if we can't turn them into readable text.
    } finally {
      if (mounted && seq == _geocodeSeq) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  void _onMapTap(LatLng position) {
    _lat = position.latitude;
    _lng = position.longitude;
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(position),
    );
  }

  Future<void> _handleUseCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are turned off. Please enable GPS and try again.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission was denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError('Location permission is permanently denied. Enable it from app settings.');
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
        _lat = position.latitude;
        _lng = position.longitude;
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
      await _reverseGeocode(position.latitude, position.longitude);
    } catch (_) {
      _showError('Could not detect your location. Please try again.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _confirm() {
    context.pop(PickedDropLocation(
      latitude: _lat,
      longitude: _lng,
      address: _address.trim().isEmpty
          ? '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}'
          : _address.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final targetPos = LatLng(_lat, _lng);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Drop-off Location'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.navy,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: targetPos, zoom: 15),
                  onMapCreated: (c) => _mapController = c,
                  onTap: _onMapTap,
                  onCameraMove: (position) {
                    _lat = position.target.latitude;
                    _lng = position.target.longitude;
                    if (!_isMapMoving) {
                      setState(() => _isMapMoving = true);
                    }
                  },
                  onCameraIdle: () {
                    if (_isMapMoving) {
                      setState(() => _isMapMoving = false);
                    }
                    _reverseGeocode(_lat, _lng);
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
                // ── Fixed Center Pin ──
                _CenterMapPin(isMoving: _isMapMoving),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.pan_tool_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Move the map to place the pin on your drop-off location',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'drop-location-my-location',
                    backgroundColor: Colors.white,
                    onPressed: _isLocating ? null : _handleUseCurrentLocation,
                    child: _isLocating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: AppColors.border, width: 0.8)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag_rounded, size: 16, color: AppColors.serviceBlue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _isResolvingAddress || _isMapMoving
                            ? const Text(
                                'Pinning location...',
                                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                              )
                            : Text(
                                _address.isEmpty
                                    ? '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}'
                                    : _address,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.navy,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.serviceBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Text('Confirm Drop-off Location',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
}

class _CenterMapPin extends StatelessWidget {
  const _CenterMapPin({required this.isMoving});

  final bool isMoving;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, isMoving ? -10 : 0, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(14, 10),
                    painter: _TrianglePainter(color: AppColors.error),
                  ),
                ],
              ),
            ),
            // Ground contact dot at exact map center
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isMoving ? 12 : 8,
              height: isMoving ? 5 : 8,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: isMoving ? 0.2 : 0.45),
                shape: BoxShape.circle,
              ),
            ),
            // Bottom offset counter-balancing the pin so the dot is at exact center
            const SizedBox(height: 52),
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      color != oldDelegate.color;
}
