import '../../../coverage/data/coverage_repository.dart';
import '../../../addresses/presentation/widgets/place_suggestions_panel.dart';
import '../../../addresses/domain/place_search.dart';
import '../../../../core/permissions/permission_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/logistics_models.dart';
import '../../domain/logistics_providers.dart';
import '../widgets/gt_coverage_map.dart';
import '../../../../shared/maps/sevo_map_style.dart';

/// Drop-off location picker for Goods & Transport.
///
/// Uses the same map UI as the address screen ("Confirm your service
/// location"): full-screen map with a fixed centre pin, a search bar, locate-me
/// and map-type buttons, and a confirm sheet.
///
/// Dynamic both ways:
///  - move the map -> the pin's address is looked up and shown;
///  - search a place, or tap "Edit" and type an address -> the pin moves there.
///
/// A real point on the map is required (the backend's distance-priced fares
/// need real drop latitude / longitude — see logistics_models.dart).
///
/// Returns a [PickedDropLocation] via `context.pop(result)`, or `null` if the
/// customer backs out without confirming.
class DropLocationPickerScreen extends ConsumerStatefulWidget {
  const DropLocationPickerScreen({super.key, this.initial});

  final PickedDropLocation? initial;

  @override
  ConsumerState<DropLocationPickerScreen> createState() => _DropLocationPickerScreenState();
}

class _DropLocationPickerScreenState extends ConsumerState<DropLocationPickerScreen> {
  double _lat = 12.754598;
  double _lng = 77.834477;

  /// Full address that will be returned.
  String _address = '';

  /// Shown on the confirm sheet (short place name + longer line).
  String _placeTitle = '';
  String _placeLine = '';

  bool _isLocating = false;
  bool _isResolvingAddress = false;
  bool _searching = false;
  bool _satellite = false;
  int _geocodeSeq = 0;
  GoogleMapController? _mapController;
  final _searchController = TextEditingController();

  // Suggestions while typing (customer backend proxy, never Google directly): from 3 characters, 300 ms pause, one
  // session token per search. If the proxy fails, Enter still searches the plain way and the pin can be moved by hand.
  late final PlaceSearch _places = _newPlaceSearch();

  PlaceSearch _newPlaceSearch() => PlaceSearch(
        autocomplete: (q, session, lat, lng) => ref.read(coverageRepositoryProvider).autocomplete(q, session: session, lat: lat, lng: lng),
        details: (s, session) => ref.read(coverageRepositoryProvider).details(s, session: session),
      );

  /// True when the pin moved because of a typed address, so the map settling
  /// doesn't overwrite what the customer typed.
  bool _keepTypedAddress = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _lat = init.latitude;
      _lng = init.longitude;
      _address = init.address;
      _placeTitle = 'Drop-off location';
      _placeLine = init.address;
      // Keep the saved text; the map settling must not replace it.
      _keepTypedAddress = true;
    } else {
      _reverseGeocode(_lat, _lng);
    }
  }

  @override
  void dispose() {
    _places.dispose();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    final seq = ++_geocodeSeq;
    if (mounted) setState(() => _isResolvingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (seq != _geocodeSeq || !mounted) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.name, p.street, p.subLocality, p.locality, p.administrativeArea, p.postalCode]
            .where((s) => s != null && s.trim().isNotEmpty)
            .map((s) => s!.trim())
            .toSet()
            .toList();
        final area = [p.subLocality, p.locality]
            .where((s) => s != null && s.trim().isNotEmpty)
            .map((s) => s!.trim())
            .toList();
        final streetBits = [p.street, p.subLocality]
            .where((s) => s != null && s.trim().isNotEmpty)
            .map((s) => s!.trim())
            .toSet()
            .join(', ');
        final line = [
          streetBits,
          if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
          [
            if ((p.administrativeArea ?? '').trim().isNotEmpty) p.administrativeArea!.trim(),
            if ((p.postalCode ?? '').trim().isNotEmpty) p.postalCode!.trim(),
          ].join(' - '),
        ].where((s) => s.isNotEmpty).join(', ');
        setState(() {
          _address = parts.join(', ');
          _placeTitle = area.isNotEmpty ? area.first : 'Selected location';
          _placeLine = line.isNotEmpty ? line : _address;
        });
      }
    } catch (_) {
      // Best-effort: the pinned coordinates are still valid without text.
    } finally {
      if (mounted && seq == _geocodeSeq) setState(() => _isResolvingAddress = false);
    }
  }

  /// Moves the map (and so the pin) to [lat],[lng].
  Future<void> _moveTo(double lat, double lng, {double zoom = 17}) async {
    _lat = lat;
    _lng = lng;
    await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), zoom));
  }

  /// Top search bar: find a place, move the pin, then look up its address.
  Future<void> _searchPlace(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final results = await _geocodeQuery(q);
      if (results.isEmpty) {
        _showError('No results for "$q".');
      } else {
        await _moveTo(results.first.latitude, results.first.longitude, zoom: 16);
        // The map settling triggers the normal reverse lookup.
      }
    } catch (_) {
      _showError('Could not find that place. Try a different search.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// A suggestion was tapped in the search bar: take its address and coordinates, move the pin there.
  Future<void> _pickSuggestion(PlaceSuggestion s) async {
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    final d = await _places.select(s); // same session token as the typing that found it
    if (!mounted) return;
    setState(() => _searching = false);
    if (d == null) {
      _showError("We couldn't open that place. Move the pin on the map, or type the address with Edit.");
      return;
    }
    final text = withoutCountry(d.address.isNotEmpty ? d.address : d.label);
    _searchController.clear();
    _keepTypedAddress = true; // the map settling must not replace the address that came with the place
    _geocodeSeq++;
    setState(() {
      _address = text;
      _placeTitle = d.name.isNotEmpty ? d.name : (d.locality.isNotEmpty ? d.locality : 'Selected location');
      _placeLine = text;
      _isResolvingAddress = false;
    });
    await _moveTo(d.lat, d.lng, zoom: 17);
  }

  Future<List<Location>> _geocodeQuery(String q) async {
    var results = await locationFromAddress(q);
    if (results.isEmpty && !q.toLowerCase().contains('india')) {
      results = await locationFromAddress('$q, India');
    }
    return results;
  }

  Future<void> _handleUseCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are turned off. Please enable GPS and try again.');
        return;
      }
      if (!mounted) return;
      if (!await PermissionManager.instance.ensure(context, AppPermission.location)) {
        _showError('Location access is off. You can search or pin the drop point manually.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      await _moveTo(position.latitude, position.longitude, zoom: 16);
    } catch (_) {
      _showError('Could not detect your location. Please try again.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// "Edit": type the address; the pin follows it.
  Future<void> _openEditSheet() async {
    final ctrl = TextEditingController(text: _address.isNotEmpty ? _address : _placeLine);
    final sheetSearch = _newPlaceSearch();
    PlaceDetails? picked; // the suggestion whose text is in the box (cleared as soon as the text is edited)
    String pickedText = '';
    var busy = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> apply() async {
            final text = ctrl.text.trim();
            if (text.isEmpty) {
              setSheet(() => error = 'Enter the drop-off address.');
              return;
            }
            setSheet(() {
              busy = true;
              error = null;
            });
            var moved = false;
            try {
              if (picked != null && text == pickedText) {
                // The text is exactly a suggestion: its coordinates are already known, no guessing needed.
                _keepTypedAddress = true;
                _geocodeSeq++;
                await _moveTo(picked!.lat, picked!.lng);
                moved = true;
              } else {
                final results = await _geocodeQuery(text);
                if (results.isNotEmpty) {
                  _keepTypedAddress = true;
                  _geocodeSeq++; // drop any reverse lookup still in flight
                  await _moveTo(results.first.latitude, results.first.longitude);
                  moved = true;
                }
              }
            } catch (_) {}
            if (!mounted) return;
            setState(() {
              _address = text;
              _placeTitle = _placeTitle.isEmpty ? 'Drop-off location' : _placeTitle;
              _placeLine = text;
              _isResolvingAddress = false;
            });
            if (!moved) {
              _showError('Address saved, but the pin could not be placed from it. Move the pin on the map if needed.');
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFD5DAE1), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Edit drop-off address',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)),
                const SizedBox(height: 4),
                const Text('Type the address (add house no. / landmark) - the pin moves to it.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => busy ? null : apply(),
                  onChanged: (v) {
                    if (v.trim() != pickedText) picked = null;
                    sheetSearch.onChanged(v, lat: _lat, lng: _lng);
                  },
                  decoration: InputDecoration(
                    labelText: 'Drop-off address',
                    errorText: error,
                    prefixIcon: const Icon(Icons.location_on_rounded, color: AppColors.navy),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                PlaceSuggestionsPanel(
                  search: sheetSearch,
                  manualHint: 'Type the full address and tap Save.',
                  onPick: (sug) async {
                    final d = await sheetSearch.select(sug);
                    if (d == null) {
                      setSheet(() => error = "We couldn't open that place. Type the full address and tap Save.");
                      return;
                    }
                    picked = d;
                    pickedText = withoutCountry(d.address.isNotEmpty ? d.address : d.label);
                    ctrl.text = pickedText;
                    ctrl.selection = TextSelection.collapsed(offset: pickedText.length);
                    setSheet(() => error = null);
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: busy ? null : apply,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save and place pin', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    // Not disposed straight away: the sheet is still animating closed and its
    // TextField would rebuild with a disposed controller (red error screen).
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      ctrl.dispose();
      sheetSearch.dispose();
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _confirm() {
    final text = _address.trim().isNotEmpty ? _address.trim() : _placeLine.trim();
    context.pop(PickedDropLocation(
      latitude: _lat,
      longitude: _lng,
      address: text.isEmpty ? '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}' : text,
    ));
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
              ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, color: AppColors.navy, size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(_lat, _lng);
    // Service area for the selected GT service, drawn on the map.
    final category = ref.watch(selectedVehicleCategoryProvider);
    final vehicleClass = ref.watch(selectedLogisticsTierProvider)?.vehicleClass;
    final intercity = category == LogisticsVehicleCategory.packersMovers && ref.watch(pmRelocationTypeProvider) != 'Within City';
    final zones = zonesFor(ref.watch(gtServiceZonesProvider(category.serviceCategoryValue)).valueOrNull ?? const <GtZone>[], vehicleClass);
    final inside = insideService(zones, _lat, _lng);
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              // SEVO map look (or the cloud Map ID when one is set).
              style: SevoMap.style,
              cloudMapId: SevoMap.cloudMapId,
              initialCameraPosition: CameraPosition(target: target, zoom: 16),
              onMapCreated: (c) => _mapController = c,
              circles: zoneCircles(zones),
              polygons: zonePolygons(zones),
              mapType: _satellite ? MapType.hybrid : MapType.normal,
              onCameraMove: (pos) {
                _lat = pos.target.latitude;
                _lng = pos.target.longitude;
              },
              onCameraIdle: () {
                if (!mounted) return;
                if (_keepTypedAddress) {
                  // Pin moved because of a typed / saved address: keep its text.
                  _keepTypedAddress = false;
                  setState(() {});
                  return;
                }
                _reverseGeocode(_lat, _lng);
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
                      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10)),
                      child: const Text(
                        'Move pin to set your exact location',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.location_on_rounded, size: 52, color: AppColors.navy),
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
                _circleButton(Icons.arrow_back_rounded, () => context.pop()),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _searchPlace,
                      onChanged: (v) => _places.onChanged(v, lat: _lat, lng: _lng),
                      style: const TextStyle(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search for area, landmark...',
                        hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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

          // Suggestions under the search box
          Positioned(
            top: topPad + 8 + 48 + 6,
            left: 12 + 46 + 10,
            right: 12,
            child: PlaceSuggestionsPanel(search: _places, onPick: _pickSuggestion),
          ),

          // Locate-me / map-type buttons
          Positioned(
            right: 14,
            bottom: 318 + bottomPad,
            child: Column(
              children: [
                _circleButton(Icons.my_location_rounded, _isLocating ? () {} : _handleUseCurrentLocation, loading: _isLocating),
                const SizedBox(height: 10),
                _circleButton(Icons.layers_rounded, () => setState(() => _satellite = !_satellite)),
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
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, -4)),
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
                      decoration: BoxDecoration(color: const Color(0xFFD5DAE1), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Confirm ', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                        TextSpan(text: 'your drop-off location', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)),
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
                          decoration: BoxDecoration(color: const Color(0xFFE6ECF4), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.location_on_rounded, color: AppColors.navy, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isResolvingAddress
                                    ? 'Finding address...'
                                    : (_placeTitle.isEmpty ? 'Selected location' : _placeTitle),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.navy),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _placeLine.isEmpty ? '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}' : _placeLine,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _openEditSheet,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.navy,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Edit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                  if (zones.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          intercity
                              ? Icons.public_rounded
                              : (inside == true ? Icons.check_circle_rounded : Icons.error_rounded),
                          size: 16,
                          color: intercity
                              ? AppColors.navy
                              : (inside == true ? const Color(0xFF15803D) : AppColors.error),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            intercity
                                ? 'Intercity move: the drop-off can be in any city (shaded area = pickup coverage).'
                                : (inside == true
                                    ? 'Inside our service area (shaded on the map).'
                                    : 'Outside our service area. Move the pin into the shaded area.'),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: intercity
                                  ? AppColors.navy
                                  : (inside == true ? const Color(0xFF15803D) : AppColors.error),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        minimumSize: const Size(88, 54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Confirm drop-off location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
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
