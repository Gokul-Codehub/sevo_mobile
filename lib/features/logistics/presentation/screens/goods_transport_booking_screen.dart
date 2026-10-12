import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/location_gate.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../addresses/domain/address_models.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../../booking/domain/booking_models.dart';
import '../../../booking/domain/booking_providers.dart';
import '../../../booking/domain/cart_notifier.dart'
    show isUserAuthenticatedProvider;
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../../core/errors/api_error.dart';
import '../../domain/gt_models.dart';
import '../../domain/gt_providers.dart';
import '../../domain/logistics_models.dart';
import '../../domain/logistics_providers.dart';
import '../widgets/gt_extras_section.dart';
import '../widgets/gt_slot_picker.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';

/// Added 2026-09-19, REWRITTEN 2026-09-20 per explicit feedback after the
/// first version shipped:
///
///  - "Remove the 'Select Routes'" — the Lane picker is gone; the real fare
///    now comes from a live distance-based quote instead of a fixed route.
///  - "Add a privilege for drop-off address to choose on Map" — drop
///    location is now captured via [DropLocationPickerScreen], which is
///    required (not optional free text), because the backend's fare
///    resolution needs a real coordinate — see the file-level note on
///    [LogisticsTier] in logistics_models.dart for the confirmed source.
///  - "The fare engine ... should be calculated and show to the customer" —
///    wired to the real `POST /api/logistics/quote/` endpoint
///    (confirmed to exist on the actual backend, not the mirror-only guess
///    the first version assumed), rendered live as tier/pickup/drop change.
///  - "Confirm Booking shows a validation error" — root-caused to two bugs
///    fixed here: `service_category` must be the logistics enum string
///    ("goods_transport_truck"/"goods_transport_two_wheeler"), never the
///    catalog slug; and the backend requires a non-blank cargo description
///    for logistics bookings, which was previously an optional field here.
///  - "Don't list services like Mini Truck / 2-Wheeler [as separate catalog
///    packages] — show pickup/drop/date/slot + a transportation category,
///    calculate fare from the selection" — this screen no longer takes a
///    specific catalog [ServiceItem]/package at all. It takes only an
///    optional [Category] (for branding/title) and lets the customer pick
///    the vehicle category (Truck / 2-Wheeler) and tier entirely from the
///    real `ServiceTier` catalog (`GET /api/logistics/tiers/`), which is a
///    separate, dedicated backend app from the generic services catalog.
/// Result of [_GoodsTransportBookingScreenState._prepareGtBooking].
typedef _GtBookingPrep = ({
  String? error,
  List<Map<String, dynamic>>? cart,
  Map<String, dynamic> extra,
  Decimal? total,
  String paymentMethod,
  bool insurance,
  int? laneId,
});

class GoodsTransportBookingScreen extends ConsumerStatefulWidget {
  const GoodsTransportBookingScreen({
    super.key,
    this.category,
    this.initialVehicleCategory,
  });

  /// Optional — only used for the screen's title/branding. Booking logic
  /// never depends on it; the real "package" selection is the vehicle
  /// category + tier picked below, resolved against the dedicated
  /// `logistics` backend app, not the generic catalog.
  final Category? category;

  /// Optional vehicle category override (e.g. from deep links or tab selection)
  final LogisticsVehicleCategory? initialVehicleCategory;

  @override
  ConsumerState<GoodsTransportBookingScreen> createState() =>
      _GoodsTransportBookingScreenState();
}

class _GoodsTransportBookingScreenState
    extends ConsumerState<GoodsTransportBookingScreen> {
  // Built from the cargo details at submit (the backend requires a
  // non-empty `description` for every logistics booking).
  String _cargoDescription = '';
  final _dropAddressDetailController = TextEditingController();
  final _dropContactNameController = TextEditingController();
  final _dropContactPhoneController = TextEditingController();
  final _declaredValueController = TextEditingController();
  final _consigneeRelationshipController = TextEditingController();

  bool _isLoading = false;
  bool _inventorySectionExpanded = true;

  LogisticsVehicleCategory _resolveVehicleCategory(Subcategory sub) {
    final slug = sub.slug.toLowerCase();
    final name = sub.name.toLowerCase();
    if (slug.contains('wheeler') || slug.contains('bike') || name.contains('wheeler')) {
      return LogisticsVehicleCategory.twoWheeler;
    }
    if (slug.contains('packer') || slug.contains('mover') || name.contains('packer') || name.contains('mover')) {
      return LogisticsVehicleCategory.packersMovers;
    }
    return LogisticsVehicleCategory.truck;
  }

  Widget _buildTransportationCategoryCard({
    required String title,
    required String? imageUrl,
    required IconData fallbackIcon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.serviceBlue : AppColors.border,
              width: isSelected ? 2.0 : 0.8,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.serviceBlue.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background Image from Admin Panel ──
              if (imageUrl != null && imageUrl.isNotEmpty)
                AppRemoteImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  fallbackWidget: Container(
                    color: isSelected ? AppColors.serviceBlue : const Color(0xFFE2E8F0),
                    child: Center(
                      child: Icon(
                        fallbackIcon,
                        size: 26,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  color: isSelected ? AppColors.serviceBlue : const Color(0xFFE2E8F0),
                  child: Center(
                    child: Icon(
                      fallbackIcon,
                      size: 26,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),

              // ── Gradient scrim overlay for high legibility ──
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.15, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: isSelected ? 0.75 : 0.65),
                    ],
                  ),
                ),
              ),

              // ── Active blue tint overlay when selected ──
              if (isSelected)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.serviceBlue.withValues(alpha: 0.28),
                    ),
                  ),
                ),

              // ── Active checkmark badge in top-right ──
              if (isSelected)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: const BoxDecoration(
                      color: AppColors.serviceBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),

              // ── Service title from Admin Panel ──
              Positioned(
                left: 4,
                right: 4,
                bottom: 6,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: Colors.white,
                    height: 1.15,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _resolveFallbackIcon(LogisticsVehicleCategory cat) {
    switch (cat) {
      case LogisticsVehicleCategory.truck:
        return Icons.local_shipping_rounded;
      case LogisticsVehicleCategory.twoWheeler:
        return Icons.two_wheeler_rounded;
      case LogisticsVehicleCategory.packersMovers:
        return Icons.inventory_2_rounded;
    }
  }

  Widget _buildDefaultCategoryRow(LogisticsVehicleCategory vehicleCategory) {
    return Row(
      children: [
        for (final cat in LogisticsVehicleCategory.values) ...[
          if (cat != LogisticsVehicleCategory.values.first)
            const SizedBox(width: 8),
          _buildTransportationCategoryCard(
            title: cat.label,
            imageUrl: switch (cat) {
              LogisticsVehicleCategory.truck => '/hero_minitruck_bg.png',
              LogisticsVehicleCategory.twoWheeler => '/hero_twowheeler_bg.png',
              LogisticsVehicleCategory.packersMovers => '/hero_packers_bg.png',
            },
            fallbackIcon: _resolveFallbackIcon(cat),
            isSelected: vehicleCategory == cat,
            onTap: () => ref
                .read(selectedVehicleCategoryProvider.notifier)
                .state = cat,
          ),
        ],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // Added 2026-09-19 per explicit request ("whenever the user is going to
    // book services or place groceries/vegetales order ask the user to turn
    // on the navigation using the android") — Goods & Transport is a booking
    // flow just like Checkout/Grocery Cart, so it gets the same
    // GPS-toggle nudge those two already have.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ensureLocationEnabled(context);
        // A new booking starts from a clean slate (these providers outlive
        // the screen).
        ref.read(cargoDeclarationProvider.notifier).state = const CargoDeclaration();
        ref.read(loadingHelpProvider.notifier).state = true;
        ref.read(selectedGtLaneProvider.notifier).state = null;
        ref.read(acceptEstimatedDistanceProvider.notifier).state = false;
        ref.read(insuranceOptInProvider.notifier).state = false;
        ref.read(customerGstinProvider.notifier).state = '';
        ref.read(ewayBillNumberProvider.notifier).state = '';
        ref.read(ptlModeProvider.notifier).state = false;
        ref.read(ptlWeightKgProvider.notifier).state = null;
        ref.read(ptlLoadAssistProvider.notifier).state = false;
        if (widget.initialVehicleCategory != null) {
          ref.read(selectedVehicleCategoryProvider.notifier).state =
              widget.initialVehicleCategory!;
        }
      }
    });
  }

  /// Mirrors the backend's `HIGH_VALUE_CONSIGNMENT_THRESHOLD` default
  /// (₹25,000, per `service_requests/serializers.py`) — used only to decide
  /// when to reveal the consignee/drop-contact-required hint in this UI.
  /// The server independently re-validates the real threshold; this is a
  /// convenience trigger, not the authoritative rule.
  static const int _highValueThresholdHint = 25000;

  @override
  void dispose() {
    _dropAddressDetailController.dispose();
    _dropContactNameController.dispose();
    _dropContactPhoneController.dispose();
    _declaredValueController.dispose();
    _consigneeRelationshipController.dispose();
    super.dispose();
  }

  // ── Goods & Transport quote lock / extras (updated backend contract) ──────

  /// 15-character GSTIN only. A half-typed value is neither quoted nor
  /// booked, so the quote's customer binding and the booking always agree.
  String? get _effectiveGstin {
    final g = ref.read(customerGstinProvider).trim();
    return g.length == 15 ? g : null;
  }

  /// The one place the spot-quote key is built, so the fare shown on screen
  /// and the quote locked at submit are the SAME cached quote (same
  /// quote_id / quote_hash).
  LogisticsQuoteParam _spotParam({
    required LogisticsVehicleCategory category,
    required LogisticsTier tier,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) {
    final cargo = ref.read(cargoDeclarationProvider);
    return LogisticsQuoteParam(
      tierId: tier.id,
      serviceCategory: category.serviceCategoryValue,
      pickupLatitude: pickupLat,
      pickupLongitude: pickupLng,
      dropLatitude: dropLat,
      dropLongitude: dropLng,
      loadingHelp: ref.read(loadingHelpProvider),
      cargo: cargo.isEmpty ? null : cargo,
      customerGstin: _effectiveGstin,
    );
  }

  String _apiMsg(Object e) => e is ApiError ? e.message : e.toString();

  /// Locks the fare with the server and builds the booking's quote echo
  /// (`cart_data[0].quote_id/quote_hash/expires_at` + the exact quoted
  /// total), Light PTL fields, cargo, consent, GSTIN and e-way bill.
  /// Mirrors `resolve_logistics_fare_v2`'s verification so the booking is
  /// charged exactly what the customer was shown.
  Future<_GtBookingPrep> _prepareGtBooking({
    required LogisticsVehicleCategory category,
    required LogisticsTier tier,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required ServiceItem bookingItem,
  }) async {
    _GtBookingPrep fail(String message) => (
          error: message,
          cart: null,
          extra: const <String, dynamic>{},
          total: null,
          paymentMethod: 'COD',
          insurance: false,
          laneId: null,
        );

    final extra = <String, dynamic>{};
    final gstin = _effectiveGstin;
    if (gstin != null) extra['customer_gstin'] = gstin;

    final eway = ref.read(ewayBillNumberProvider).trim();
    if (eway.isNotEmpty) {
      if (!RegExp(r'^\d{12}$').hasMatch(eway)) {
        return fail('The e-way bill number must be exactly 12 digits.');
      }
      extra['eway_bill_number'] = eway;
    }

    final insurance = ref.read(insuranceOptInProvider) &&
        (_declaredValue?.toDouble() ?? 0) > 0;
    final paymentMethod = insurance ? 'ONLINE' : 'COD';

    Map<String, dynamic> line(double price, Map<String, dynamic> more) => {
          'id': bookingItem.id,
          'name': bookingItem.title,
          'price': price,
          'quantity': 1,
          'categoryName': bookingItem.categoryName ?? '',
          ...more,
        };

    final isPtl = category == LogisticsVehicleCategory.truck &&
        ref.read(ptlModeProvider);

    if (isPtl) {
      final weight = ref.read(ptlWeightKgProvider);
      if (weight == null || weight <= 0) {
        return fail('Enter the cargo weight in kg for Part Truck Load.');
      }
      final assist = ref.read(ptlLoadAssistProvider);
      final laneId = ref.read(selectedGtLaneProvider)?.id;
      final param = PtlQuoteParam(
        tierId: tier.id,
        declaredWeightKg: weight,
        pickupLatitude: pickupLat,
        pickupLongitude: pickupLng,
        dropLatitude: dropLat,
        dropLongitude: dropLng,
        laneId: laneId,
        loadAssist: assist,
      );
      PtlQuote q;
      try {
        q = await ref.read(ptlQuoteProvider(param).future);
        if (q.isExpired) {
          ref.invalidate(ptlQuoteProvider(param));
          q = await ref.read(ptlQuoteProvider(param).future);
        }
      } catch (e) {
        return fail(_apiMsg(e));
      }
      extra['logistics_booking_mode'] = 'ptl';
      extra['ptl_declared_weight_kg'] = weight;
      extra['ptl_load_assist'] = assist;
      return (
        error: null,
        cart: [
          line(q.total, {
            if ((q.quoteId ?? '').isNotEmpty) 'quote_id': q.quoteId,
            if ((q.quoteHash ?? '').isNotEmpty) 'quote_hash': q.quoteHash,
            if ((q.expiresAt ?? '').isNotEmpty) 'expires_at': q.expiresAt,
            'declared_weight_kg': weight,
            'load_assist': assist,
          }),
        ],
        extra: extra,
        total: Decimal.parse(q.total.toStringAsFixed(2)),
        paymentMethod: paymentMethod,
        insurance: insurance,
        laneId: laneId,
      );
    }

    // Spot (distance) booking: re-use the quote on screen, refreshing it if
    // it has expired.
    final param = _spotParam(
      category: category,
      tier: tier,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropLat: dropLat,
      dropLng: dropLng,
    );
    LogisticsQuote q;
    try {
      q = await ref.read(logisticsQuoteProvider(param).future);
      if (q.isExpired) {
        ref.invalidate(logisticsQuoteProvider(param));
        q = await ref.read(logisticsQuoteProvider(param).future);
      }
    } catch (e) {
      return fail(_apiMsg(e));
    }
    if (!q.quotable) {
      return fail('We could not calculate the fare for this trip. Please try again.');
    }
    if (GtQuoteNotices.needsEstimateConsent(q)) {
      if (!ref.read(acceptEstimatedDistanceProvider)) {
        return fail(
          'This fare uses an estimated distance. Please accept the estimate to continue.',
        );
      }
      extra['accept_estimated_distance'] = true;
    }
    final cargo = ref.read(cargoDeclarationProvider);
    if (!cargo.isEmpty) extra.addAll(cargo.toPayload());

    return (
      error: null,
      cart: [line(q.total, q.toCartEcho())],
      extra: extra,
      total: Decimal.parse(q.total.toStringAsFixed(2)),
      paymentMethod: paymentMethod,
      insurance: insurance,
      laneId: null,
    );
  }

  /// Human-readable cargo summary sent as the booking `description`
  /// (the backend requires one for logistics and scans it for prohibited
  /// goods). Returns null when the customer has not told us what they are
  /// moving.
  String? _buildCargoDescription(LogisticsVehicleCategory category) {
    if (category == LogisticsVehicleCategory.packersMovers) {
      final qty = ref.read(pmSelectedQuantitiesProvider);
      final all = ref
              .read(packersMoversInventoryProvider)
              .valueOrNull
              ?.expand((c) => c.items)
              .toList() ??
          const <PmGoodsItem>[];
      final parts = <String>[];
      for (final e in qty.entries) {
        if (e.value <= 0) continue;
        final it = all.where((i) => i.id == e.key).firstOrNull;
        parts.add('${e.value} × ${it?.name ?? 'item'}');
      }
      return parts.isEmpty ? null : 'Packers & Movers: ${parts.join(', ')}';
    }

    if (category == LogisticsVehicleCategory.truck && ref.read(ptlModeProvider)) {
      final w = ref.read(ptlWeightKgProvider);
      return (w == null || w <= 0)
          ? null
          : 'Part Truck Load, approx. ${w.toStringAsFixed(0)} kg';
    }

    final cargo = ref.read(cargoDeclarationProvider);
    if (cargo.isEmpty) return null;
    final parts = <String>[];
    final cat = ref
        .read(goodsCategoriesProvider)
        .valueOrNull
        ?.where((c) => c.id == cargo.goodsCategoryId)
        .firstOrNull;
    if (cat != null) parts.add(cat.name);
    if (cargo.items.isNotEmpty) {
      final known = cargo.goodsCategoryId == null
          ? null
          : ref.read(goodsItemsProvider(cargo.goodsCategoryId)).valueOrNull;
      parts.add(cargo.items.map((l) {
        final it = known?.where((i) => i.id == l.itemId).firstOrNull;
        return '${l.quantity} × ${it?.name ?? 'item'}';
      }).join(', '));
    }
    if (cargo.declaredWeightKg != null) {
      parts.add('approx. ${cargo.declaredWeightKg!.toStringAsFixed(0)} kg');
    }
    return parts.join(' · ');
  }

  Decimal? get _declaredValue {
    final raw = _declaredValueController.text.trim();
    if (raw.isEmpty) return null;
    try {
      return Decimal.parse(raw);
    } catch (_) {
      return null;
    }
  }

  bool get _isHighValue =>
      (_declaredValue?.toDouble() ?? 0) >= _highValueThresholdHint;

  Future<void> _handlePickDropLocation() async {
    final current = ref.read(dropLocationProvider);
    final result = await context.push<PickedDropLocation>(
      AppRoutes.dropLocationPicker,
      extra: current,
    );
    if (result != null) {
      ref.read(dropLocationProvider.notifier).state = result;
    }
  }

  Future<void> _handleSubmit() async {
    final vehicleCategory = ref.read(selectedVehicleCategoryProvider);
    final selectedTier = ref.read(selectedLogisticsTierProvider);
    final selectedAddress = ref.read(selectedAddressProvider);
    final dropLocation = ref.read(dropLocationProvider);
    final selectedDate = ref.read(selectedBookingDateProvider);
    final selectedSlot = ref.read(selectedTimeSlotProvider);
    final currentUser = ref.read(currentUserProvider);

    final isAuthenticated = ref.read(isUserAuthenticatedProvider);
    if (!isAuthenticated) {
      context.push('/login');
      return;
    }

    if (selectedTier == null) {
      _warn('Please select a vehicle.');
      return;
    }

    if (selectedAddress == null) {
      _warn('Please select a pickup address.');
      context.push('/addresses?select=true');
      return;
    }

    if (selectedAddress.latitude == null || selectedAddress.longitude == null) {
      _warn(
        'Your pickup address is missing a map location. Please edit it and pin it on the map before booking.',
      );
      return;
    }

    if (dropLocation == null) {
      _warn('Please choose the drop-off location on the map.');
      return;
    }

    if (selectedSlot == null) {
      _warn('Please select a pickup time slot.');
      return;
    }

    final builtDescription = _buildCargoDescription(vehicleCategory);
    if (builtDescription == null) {
      _warn(
        vehicleCategory == LogisticsVehicleCategory.packersMovers
            ? 'Please add at least one item to move.'
            : (ref.read(ptlModeProvider) &&
                    vehicleCategory == LogisticsVehicleCategory.truck)
                ? 'Enter the cargo weight in kg for Part Truck Load.'
                : 'Please add your cargo details (type of goods, items or weight).',
      );
      return;
    }
    _cargoDescription = builtDescription;

    if (_isHighValue && _consigneeRelationshipController.text.trim().isEmpty) {
      _warn(
        'For high-value consignments, please describe your relationship to the consignee.',
      );
      return;
    }

    final dateFormatted = DateFormat('yyyy-MM-dd').format(selectedDate);
    final dropAddressDetail = _dropAddressDetailController.text.trim();
    final dropAddressFull = dropAddressDetail.isEmpty
        ? dropLocation.address
        : '$dropAddressDetail, ${dropLocation.address}';

    if (vehicleCategory == LogisticsVehicleCategory.packersMovers) {
      await _handleSubmitPackersMovers(
        selectedTier: selectedTier,
        selectedAddress: selectedAddress,
        dropLocation: dropLocation,
        selectedSlot: selectedSlot,
        dateFormatted: dateFormatted,
        dropAddressFull: dropAddressFull,
        currentUser: currentUser,
      );
      return;
    }

    setState(() => _isLoading = true);

    // A synthetic catalog item representing this booking's line item, so
    // the existing CartItem/booking payload plumbing (built for the
    // generic catalog) has something to carry `service_id`/`issue_title`/
    // `cart_data` from. The authoritative price is never this item's
    // `price` — it's whatever `resolve_logistics_fare_v2` computes
    // server-side from the tier + pickup/drop coordinates.
    final bookingItem = ServiceItem(
      id: selectedTier.id,
      title: '${vehicleCategory.label} — ${selectedTier.name}',
      slug: selectedTier.slug ?? 'goods-transport-${selectedTier.id}',
      price: Decimal.parse((selectedTier.startingPrice ?? 0).toString()),
      categoryId: widget.category?.id,
      categoryName: widget.category?.name ?? 'Goods & Transport',
      categorySlug: widget.category?.slug ?? 'goods_transports',
    );

    final prep = await _prepareGtBooking(
      category: vehicleCategory,
      tier: selectedTier,
      pickupLat: selectedAddress.latitude!,
      pickupLng: selectedAddress.longitude!,
      dropLat: dropLocation.latitude,
      dropLng: dropLocation.longitude,
      bookingItem: bookingItem,
    );
    if (!mounted) return;
    if (prep.error != null) {
      setState(() => _isLoading = false);
      AppToast.show(context, prep.error!, type: AppToastType.error);
      return;
    }

    final result = await ref
        .read(bookingActionControllerProvider.notifier)
        .createBooking(
          customItems: [CartItem(service: bookingItem, quantity: 1)],
          date: dateFormatted,
          slot: selectedSlot,
          // Placeholder only — the server independently recomputes and
          // overrides this from the tier + pickup/drop coordinates
          // (resolve_logistics_fare_v2), it is never trusted as submitted.
          // The live quote shown above the submit button reflects that same
          // computation, so this is not a surprise to the customer.
          // Now the server-locked quote total (quote_id/hash echoed in
          // cart_data); the tier's starting price is only a last resort.
          totalAmount: prep.total ??
              Decimal.parse((selectedTier.startingPrice ?? 0).toString()),
          cartDataOverride: prep.cart,
          extraPayload: prep.extra,
          paymentMethod: prep.paymentMethod,
          insuranceOptedIn: prep.insurance ? true : null,
          logisticsLane: prep.laneId,
          specialInstructions: _cargoDescription,
          contactPhone: currentUser?.phone,
          dropAddress: dropAddressFull,
          dropLatitude: dropLocation.latitude,
          dropLongitude: dropLocation.longitude,
          logisticsTier: selectedTier.id,
          declaredValue: _declaredValue,
          consigneeRelationship: _isHighValue
              ? _consigneeRelationshipController.text.trim()
              : null,
          dropContactName: _dropContactNameController.text.trim().isEmpty
              ? null
              : _dropContactNameController.text.trim(),
          dropContactPhone: _dropContactPhoneController.text.trim().isEmpty
              ? null
              : _dropContactPhoneController.text.trim(),
          serviceCategoryOverride: vehicleCategory.serviceCategoryValue,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          backgroundColor: AppColors.error,
        ),
      );
    } else if (result.booking != null) {
      ref.read(selectedLogisticsTierProvider.notifier).state = null;
      ref.read(dropLocationProvider.notifier).state = null;
      AppToast.bookingSuccessful(context);
      context.go(
        '/bookings/success/${result.booking!.id}',
        extra: result.booking,
      );
    }
  }

  /// Packers & Movers submit path. Distinct from the Truck/2-Wheeler path
  /// above because the backend's own booking-time verification
  /// (`verify_packers_movers_quote`) requires an EXACT match between the
  /// `cart_data[0]` sent here and the parameters of whichever quote's
  /// `quote_id` is included — so this re-fetches the quote fresh right
  /// before submit (never trusts a possibly-stale one already on screen)
  /// and sends the identical parameters back, unchanged, as `cart_data`.
  Future<void> _handleSubmitPackersMovers({
    required LogisticsTier selectedTier,
    required Address selectedAddress,
    required PickedDropLocation dropLocation,
    required TimeSlot selectedSlot,
    required String dateFormatted,
    required String dropAddressFull,
    required UserProfile? currentUser,
  }) async {
    final quantities = ref.read(pmSelectedQuantitiesProvider);
    final selectedCount = quantities.values.where((q) => q > 0).length;
    if (selectedCount == 0) {
      _warn('Please add at least one item to move.');
      return;
    }

    final allItems =
        ref
            .read(packersMoversInventoryProvider)
            .valueOrNull
            ?.expand((c) => c.items)
            .toList() ??
        const [];
    final inventoryLines = <Map<String, dynamic>>[];
    for (final entry in quantities.entries) {
      if (entry.value <= 0) continue;
      final item = allItems.where((it) => it.id == entry.key).firstOrNull;
      if (item == null) continue;
      inventoryLines.add({
        'goods_item_id': item.id,
        'name': item.name,
        'quantity': entry.value,
      });
    }
    if (inventoryLines.isEmpty) {
      _warn('Please add at least one item to move.');
      return;
    }

    setState(() => _isLoading = true);

    final city = selectedTier.city ?? 'Hosur';
    final param = PmQuoteParam(
      tierId: selectedTier.id,
      city: city,
      pickupLatitude: selectedAddress.latitude as double,
      pickupLongitude: selectedAddress.longitude as double,
      dropLatitude: dropLocation.latitude,
      dropLongitude: dropLocation.longitude,
      inventory: inventoryLines,
      packingTier: ref.read(pmPackingTierProvider),
      dismantlingRequired: ref.read(pmDismantlingRequiredProvider),
      unpackingRequired: ref.read(pmUnpackingRequiredProvider),
      pickupFloor: ref.read(pmPickupFloorProvider),
      pickupHasLift: ref.read(pmPickupHasLiftProvider),
      dropFloor: ref.read(pmDropFloorProvider),
      dropHasLift: ref.read(pmDropHasLiftProvider),
      relocationType: ref.read(pmRelocationTypeProvider),
    );

    PackersMoversQuote quote;
    try {
      quote = await ref.read(pmQuoteProvider(param).future);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _warn('Could not calculate the fare for this move. Please try again.');
      return;
    }

    if (!quote.quotable ||
        quote.requiresSurvey ||
        quote.requiresReview ||
        quote.total == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _warn(
        quote.estimateNotice ?? quote.reviewReason ?? 'This move needs a quick review before it can be booked instantly — please contact support to finalize it.',
      );
      return;
    }

    final bookingItem = ServiceItem(
      id: selectedTier.id,
      title: 'Packers & Movers — ${selectedTier.name}',
      slug: selectedTier.slug ?? 'packers-movers-${selectedTier.id}',
      price: Decimal.parse(quote.total!.toStringAsFixed(2)),
      categoryId: widget.category?.id,
      categoryName: widget.category?.name ?? 'Goods & Transport',
      categorySlug: widget.category?.slug ?? 'goods_transports',
    );

    // This cart_data[0] map is read verbatim by the backend's
    // `verify_packers_movers_quote` (via `resolve_logistics_fare_v2`) — it
    // must exactly match what `param` above just quoted, plus `quote_id`
    // and `city` so the server can look the cached quote back up.
    final cartDataOverride = [
      {
        'quote_id': quote.quoteId,
        'tier_id': selectedTier.id,
        'city': city,
        'inventory': inventoryLines,
        'packing_tier': param.packingTier,
        'dismantling_required': param.dismantlingRequired,
        'unpacking_required': param.unpackingRequired,
        'pickup_floor': param.pickupFloor,
        'pickup_has_lift': param.pickupHasLift,
        'drop_floor': param.dropFloor,
        'drop_has_lift': param.dropHasLift,
        'relocation_type': param.relocationType,
      },
    ];

    final result = await ref
        .read(bookingActionControllerProvider.notifier)
        .createBooking(
          customItems: [CartItem(service: bookingItem, quantity: 1)],
          date: dateFormatted,
          slot: selectedSlot,
          // Matches quote.total exactly — the backend's verify step rejects a
          // submitted total that doesn't equal the verified quote's total.
          totalAmount: Decimal.parse(quote.total!.toStringAsFixed(2)),
          specialInstructions: _cargoDescription,
          contactPhone: currentUser?.phone,
          dropAddress: dropAddressFull,
          dropLatitude: dropLocation.latitude,
          dropLongitude: dropLocation.longitude,
          logisticsTier: selectedTier.id,
          declaredValue: _declaredValue,
          consigneeRelationship: _isHighValue
              ? _consigneeRelationshipController.text.trim()
              : null,
          dropContactName: _dropContactNameController.text.trim().isEmpty
              ? null
              : _dropContactNameController.text.trim(),
          dropContactPhone: _dropContactPhoneController.text.trim().isEmpty
              ? null
              : _dropContactPhoneController.text.trim(),
          serviceCategoryOverride:
              LogisticsVehicleCategory.packersMovers.serviceCategoryValue,
          cartDataOverride: cartDataOverride,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          backgroundColor: AppColors.error,
        ),
      );
    } else if (result.booking != null) {
      ref.read(selectedLogisticsTierProvider.notifier).state = null;
      ref.read(dropLocationProvider.notifier).state = null;
      ref.read(pmSelectedQuantitiesProvider.notifier).state = const {};
      AppToast.bookingSuccessful(context);
      context.go(
        '/bookings/success/${result.booking!.id}',
        extra: result.booking,
      );
    }
  }

  void _warn(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.warning),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicleCategory = ref.watch(selectedVehicleCategoryProvider);
    final tiersAsync = ref.watch(logisticsTiersProvider(vehicleCategory));
    final subServicesAsync = ref.watch(
      subServicesProvider(widget.category?.slug ?? 'goods_transports'),
    );
    final selectedTier = ref.watch(selectedLogisticsTierProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);
    final dropLocation = ref.watch(dropLocationProvider);

    // A tier from the other vehicle category is never valid once the
    // category tab switches — clear it rather than silently keep a
    // mismatched tier selected (which would fail the backend's
    // assert_catalog_matches_category check on submit).
    ref.listen<LogisticsVehicleCategory>(selectedVehicleCategoryProvider, (
      prev,
      next,
    ) {
      if (prev != null && prev != next) {
        ref.read(selectedLogisticsTierProvider.notifier).state = null;
        // Slots are per service category on the server.
        ref.read(selectedTimeSlotProvider.notifier).state = null;
        // Items valid for one vehicle type may not be for the other.
        ref.read(cargoDeclarationProvider.notifier).state = ref
            .read(cargoDeclarationProvider)
            .copyWith(items: const []);
        // A Packers & Movers inventory selection is meaningless once the
        // customer switches away from it (and vice versa) — clear it so a
        // stale selection can't silently ride along into a Truck/2-Wheeler
        // fare computation or a re-visited P&M tab.
        ref.read(pmSelectedQuantitiesProvider.notifier).state = const {};
      }
    });

    final isPackersMovers =
        vehicleCategory == LogisticsVehicleCategory.packersMovers;

    // Watched so a change re-builds and re-quotes (the values themselves are
    // read inside _spotParam so build and submit share one quote key).
    ref.watch(loadingHelpProvider);
    ref.watch(cargoDeclarationProvider);
    ref.watch(customerGstinProvider);
    final ptlMode = ref.watch(ptlModeProvider) &&
        vehicleCategory == LogisticsVehicleCategory.truck;

    LogisticsQuoteParam? quoteParam;
    if (!isPackersMovers &&
        !ptlMode &&
        selectedTier != null &&
        selectedAddress?.latitude != null &&
        selectedAddress?.longitude != null &&
        dropLocation != null) {
      quoteParam = _spotParam(
        category: vehicleCategory,
        tier: selectedTier,
        pickupLat: selectedAddress!.latitude!,
        pickupLng: selectedAddress.longitude!,
        dropLat: dropLocation.latitude,
        dropLng: dropLocation.longitude,
      );
    }

    PmQuoteParam? pmQuoteParam;
    final pmQuantities = ref.watch(pmSelectedQuantitiesProvider);
    final pmInventoryAsync = ref.watch(packersMoversInventoryProvider);
    if (isPackersMovers &&
        selectedTier != null &&
        selectedAddress?.latitude != null &&
        selectedAddress?.longitude != null &&
        dropLocation != null &&
        pmQuantities.values.any((q) => q > 0)) {
      final allItems =
          pmInventoryAsync.valueOrNull?.expand((c) => c.items).toList() ??
          const [];
      final inventoryLines = <Map<String, dynamic>>[];
      for (final entry in pmQuantities.entries) {
        if (entry.value <= 0) continue;
        final item = allItems.where((it) => it.id == entry.key).firstOrNull;
        if (item == null) continue;
        inventoryLines.add({
          'goods_item_id': item.id,
          'name': item.name,
          'quantity': entry.value,
        });
      }
      if (inventoryLines.isNotEmpty) {
        pmQuoteParam = PmQuoteParam(
          tierId: selectedTier.id,
          city: selectedTier.city ?? 'Hosur',
          pickupLatitude: selectedAddress!.latitude!,
          pickupLongitude: selectedAddress.longitude!,
          dropLatitude: dropLocation.latitude,
          dropLongitude: dropLocation.longitude,
          inventory: inventoryLines,
          packingTier: ref.watch(pmPackingTierProvider),
          dismantlingRequired: ref.watch(pmDismantlingRequiredProvider),
          unpackingRequired: ref.watch(pmUnpackingRequiredProvider),
          pickupFloor: ref.watch(pmPickupFloorProvider),
          pickupHasLift: ref.watch(pmPickupHasLiftProvider),
          dropFloor: ref.watch(pmDropFloorProvider),
          dropHasLift: ref.watch(pmDropHasLiftProvider),
          relocationType: ref.watch(pmRelocationTypeProvider),
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.category?.name ?? 'Goods & Transport',
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Vehicle category tabs (Truck / 2-Wheeler) ──
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transportation Category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  subServicesAsync.when(
                    data: (services) {
                      if (services.isEmpty) {
                        return _buildDefaultCategoryRow(vehicleCategory);
                      }
                      return Row(
                        children: [
                          for (int i = 0; i < services.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Builder(
                              builder: (context) {
                                final sub = services[i];
                                final cat = _resolveVehicleCategory(sub);
                                final isSelected = vehicleCategory == cat;
                                return _buildTransportationCategoryCard(
                                  title: sub.name,
                                  imageUrl: sub.image,
                                  fallbackIcon: _resolveFallbackIcon(cat),
                                  isSelected: isSelected,
                                  onTap: () => ref
                                      .read(
                                        selectedVehicleCategoryProvider.notifier,
                                      )
                                      .state = cat,
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    },
                    loading: () => Row(
                      children: [
                        for (int i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: 78,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    error: (e, s) => _buildDefaultCategoryRow(vehicleCategory),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Vehicle tier / package picker ──
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Select Available Package's",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  tiersAsync.when(
                    data: (tiers) {
                      if (tiers.isEmpty) {
                        return const Text(
                          'No vehicles are configured for this category right now. Please try the other category or check back later.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        );
                      }
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = ((constraints.maxWidth - 10) / 2).floorToDouble();
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: tiers.map((tier) {
                          final isSelected = selectedTier?.id == tier.id;
                          return GestureDetector(
                            onTap: () =>
                                ref
                                        .read(
                                          selectedLogisticsTierProvider
                                              .notifier,
                                        )
                                        .state =
                                    tier,
                            child: Container(
                              width: cardWidth,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.serviceBlueLight
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.serviceBlue
                                      : AppColors.border,
                                  width: isSelected ? 1.5 : 0.8,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppColors.serviceBlue
                                              .withValues(alpha: 0.15),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      height: 72,
                                      width: double.infinity,
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFFF1F5F9),
                                      child: tier.imageUrl != null &&
                                              tier.imageUrl!.isNotEmpty
                                          ? AppRemoteImage(
                                              imageUrl: tier.imageUrl,
                                              fit: BoxFit.contain,
                                            )
                                          : Center(
                                              child: Icon(
                                                vehicleCategory ==
                                                        LogisticsVehicleCategory
                                                            .truck
                                                    ? Icons
                                                        .local_shipping_rounded
                                                    : (vehicleCategory ==
                                                            LogisticsVehicleCategory
                                                                .twoWheeler
                                                        ? Icons
                                                            .two_wheeler_rounded
                                                        : Icons
                                                            .inventory_2_rounded),
                                                size: 32,
                                                color: isSelected
                                                    ? AppColors.serviceBlue
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    tier.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: isSelected
                                          ? AppColors.serviceBlue
                                          : AppColors.navy,
                                      height: 1.2,
                                    ),
                                  ),
                                  if (tier.capacityLabel != null &&
                                      tier.capacityLabel!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      tier.capacityLabel!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (tier.startingPrice != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'from ₹${tier.startingPrice!.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.serviceBlue,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
                    loading: () => Row(
                      children: [
                        Expanded(
                          child: ShimmerBox(
                            width: double.infinity,
                            height: 140,
                            borderRadius: 8,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ShimmerBox(
                            width: double.infinity,
                            height: 140,
                            borderRadius: 8,
                          ),
                        ),
                      ],
                    ),
                    error: (_, _) => const Text(
                      'Could not load vehicle options. Please pull to refresh or try again shortly.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.error,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Packers & Movers: inventory builder + move details ──
            // Added 2026-09-20 — this is the genuinely separate part of
            // this flow; see [PackersMoversQuote]'s doc comment in
            // logistics_models.dart. Only ever shown for this category.
            if (isPackersMovers) ...[
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _inventorySectionExpanded = !_inventorySectionExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'What are you moving?',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _inventorySectionExpanded
                                        ? 'Pick a room on the left, then add its items on the right.'
                                        : 'Tap to unshrink moving inventory list.',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              _inventorySectionExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: AppColors.navy,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_inventorySectionExpanded) ...[
                      const SizedBox(height: 12),
                      pmInventoryAsync.when(
                        data: (categories) {
                          if (categories.isEmpty) {
                            return const Text(
                              'The moving inventory catalog is not configured yet. Please check back later.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            );
                          }
                          return PmInventoryPicker(categories: categories);
                        },
                        loading: () => Column(
                          children: List.generate(
                            4,
                            (index) => const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: ShimmerBox(
                                width: double.infinity,
                                height: 44,
                                borderRadius: 8,
                              ),
                            ),
                          ),
                        ),
                      error: (_, _) => const Text(
                        'Could not load the moving inventory. Please pull to refresh or try again shortly.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.error,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
              const SizedBox(height: 18),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Move Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Packing',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            ('standard', 'Standard Packing'),
                            ('premium', 'Premium (Fragile-Safe)'),
                            ('no_packing', 'I Will Pack Myself'),
                          ].map((opt) {
                            final selected =
                                ref.watch(pmPackingTierProvider) == opt.$1;
                            return _PmChoiceChip(
                              label: opt.$2,
                              selected: selected,
                              onTap: () =>
                                  ref
                                          .read(pmPackingTierProvider.notifier)
                                          .state =
                                      opt.$1,
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Relocation Type',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Within City', 'Intercity'].map((opt) {
                        final selected =
                            ref.watch(pmRelocationTypeProvider) == opt;
                        return _PmChoiceChip(
                          label: opt,
                          selected: selected,
                          onTap: () =>
                              ref
                                      .read(pmRelocationTypeProvider.notifier)
                                      .state =
                                  opt,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Dismantle furniture that needs it',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      value: ref.watch(pmDismantlingRequiredProvider),
                      onChanged: (v) =>
                          ref
                                  .read(pmDismantlingRequiredProvider.notifier)
                                  .state =
                              v,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Unpack at the drop-off',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      value: ref.watch(pmUnpackingRequiredProvider),
                      onChanged: (v) =>
                          ref.read(pmUnpackingRequiredProvider.notifier).state =
                              v,
                    ),
                    const Divider(height: 20, color: AppColors.border),
                    Row(
                      children: [
                        Expanded(
                          child: _PmFloorStepper(
                            label: 'Pickup floor',
                            value: ref.watch(pmPickupFloorProvider),
                            onChanged: (v) =>
                                ref.read(pmPickupFloorProvider.notifier).state =
                                    v,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PmFloorStepper(
                            label: 'Drop floor',
                            value: ref.watch(pmDropFloorProvider),
                            onChanged: (v) =>
                                ref.read(pmDropFloorProvider.notifier).state =
                                    v,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Pickup building has a lift',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      value: ref.watch(pmPickupHasLiftProvider),
                      onChanged: (v) =>
                          ref.read(pmPickupHasLiftProvider.notifier).state = v,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Drop-off building has a lift',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      value: ref.watch(pmDropHasLiftProvider),
                      onChanged: (v) =>
                          ref.read(pmDropHasLiftProvider.notifier).state = v,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ── Pickup address (reuses the app's existing saved-address
            // picker — real coordinates are required here for the fare
            // engine, same as the drop-off pin below). ──
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Pickup Address',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => context.push('/addresses?select=true'),
                        child: Text(
                          selectedAddress != null ? 'Change' : '+ Add New',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: AppColors.border),
                  if (selectedAddress != null) ...[
                    Text(
                      selectedAddress.formattedAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (selectedAddress.latitude == null ||
                        selectedAddress.longitude == null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'This address has no pinned map location — edit it to add one before booking.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ] else
                    GestureDetector(
                      onTap: () => context.push('/addresses?select=true'),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.border,
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.add_location_alt_outlined,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Tap to select your pickup address',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Drop-off location (map pick — required; see file-level
            // note on why free text alone can't work here). ──
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            color: AppColors.serviceBlue,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Drop-off Location',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _handlePickDropLocation,
                        child: Text(
                          dropLocation != null ? 'Change' : 'Choose on Map',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: AppColors.border),
                  if (dropLocation != null)
                    Text(
                      dropLocation.address,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _handlePickDropLocation,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.border,
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.map_outlined,
                              color: AppColors.serviceBlue,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Tap to pin the drop-off location',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dropAddressDetailController,
                    decoration: _fieldDecoration(
                      'Flat/floor/landmark (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dropContactNameController,
                          decoration: _fieldDecoration(
                            'Receiver name (optional)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _dropContactPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: _fieldDecoration(
                            'Receiver phone (optional)',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Live fare — "the frontend never determines the fare, it
            // renders what [the server] returns" (backend's own words). ──
            _SectionCard(
              child: isPackersMovers
                  ? (pmQuoteParam == null
                        ? const Row(
                            children: [
                              Icon(
                                Icons.calculate_outlined,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Select a vehicle, pickup, drop-off, and at least one item to see the fare.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Consumer(
                            builder: (context, ref, _) {
                              final quoteAsync = ref.watch(
                                pmQuoteProvider(pmQuoteParam!),
                              );
                              return quoteAsync.when(
                                loading: () => const Row(
                                  children: [
                                    ShimmerBox(
                                      height: 16,
                                      width: 16,
                                      borderRadius: 4,
                                    ),
                                    SizedBox(width: 10),
                                    ShimmerLine(width: 120, height: 14),
                                  ],
                                ),
                                error: (err, _) => Text(
                                  err is Exception
                                      ? _friendlyQuoteError(err)
                                      : 'Could not calculate the fare.',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.error,
                                    height: 1.4,
                                  ),
                                ),
                                data: (quote) => _PmFareQuoteView(quote: quote),
                              );
                            },
                          ))
                  : (quoteParam == null
                        ? (ptlMode
                            ? const Text(
                                'The Part Truck Load fare is shown in the Part Truck Load section.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : const Row(
                            children: [
                              Icon(
                                Icons.calculate_outlined,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Select a vehicle, pickup and drop-off to see the fare.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ))
                        : Consumer(
                            builder: (context, ref, _) {
                              final quoteAsync = ref.watch(
                                logisticsQuoteProvider(quoteParam!),
                              );
                              return quoteAsync.when(
                                loading: () => const Row(
                                  children: [
                                    ShimmerBox(
                                      height: 16,
                                      width: 16,
                                      borderRadius: 4,
                                    ),
                                    SizedBox(width: 10),
                                    ShimmerLine(width: 120, height: 14),
                                  ],
                                ),
                                error: (err, _) => Text(
                                  err is Exception
                                      ? _friendlyQuoteError(err)
                                      : 'Could not calculate the fare.',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.error,
                                    height: 1.4,
                                  ),
                                ),
                                data: (quote) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FareQuoteView(quote: quote),
                                    GtQuoteNotices(quote: quote),
                                  ],
                                ),
                              );
                            },
                          )),
            ),
            const SizedBox(height: 18),

            // ── Part Truck Load (truck only) + cargo details / fitment ──
            if (!isPackersMovers) ...[
              if (vehicleCategory == LogisticsVehicleCategory.truck) ...[
                GtPtlSection(
                  city: selectedTier?.city ?? 'Hosur',
                  tier: selectedTier,
                  pickupLatitude: selectedAddress?.latitude,
                  pickupLongitude: selectedAddress?.longitude,
                  dropLatitude: dropLocation?.latitude,
                  dropLongitude: dropLocation?.longitude,
                ),
                const SizedBox(height: 18),
              ],
              if (!ptlMode) ...[
                GtCargoSection(city: selectedTier?.city ?? 'Hosur'),
                const SizedBox(height: 18),
              ],
            ],

            // ── Declared value / consignee relationship ──
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Declared Value of Goods (Optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Helps us handle high-value consignments with extra care.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _declaredValueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: _fieldDecoration('e.g. 15000'),
                  ),
                  if (_isHighValue) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _consigneeRelationshipController,
                      decoration: _fieldDecoration(
                        'Your relationship to the consignee (required for high-value goods)',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Loading help, insurance, GST / e-way bill ──
            if (!isPackersMovers) ...[
              GtOptionsSection(declaredValue: _declaredValue?.toDouble()),
              const SizedBox(height: 18),
            ],

            // ── Pickup date & time (server-driven slots) ──
            _SectionCard(
              child: GtSlotPicker(
                category: ptlMode ? 'ptl' : vehicleCategory.serviceCategoryValue,
                city: selectedTier?.city,
              ),
            ),
            const SizedBox(height: 18),

            GtPoliciesSection(
              serviceCategory: vehicleCategory.serviceCategoryValue,
              faqCategory: vehicleCategory.tierCategoryValue,
              city: selectedTier?.city,
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppColors.border, width: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.serviceBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Confirm Booking',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }

  String _friendlyQuoteError(Exception err) {
    if (err is ApiError) return err.message;
    final msg = err.toString();
    // ApiError subtypes already carry a customer-facing message (see
    // error_interceptor.dart's structured {message, error_code} parsing for
    // this exact endpoint) — strip the Dart exception type prefix Riverpod
    // adds so only that message shows.
    final match = RegExp(r'^[A-Za-z]+Error\(?\s*(.*?)\)?$').firstMatch(msg);
    return match?.group(1)?.trim().isNotEmpty == true
        ? match!.group(1)!.trim()
        : msg;
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: AppColors.border, width: 0.8),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: AppColors.border, width: 0.8),
    ),
  );

}

/// Renders a [LogisticsQuote] the same way the real customer web app's
/// booking pages do: a prominent total plus a itemised breakdown of the
/// components the backend actually charged for
/// (`LogisticsFareBreakdown` in `service_requests/services/logistics_pricing.py`)
/// — never a client-invented number.
class _FareQuoteView extends StatelessWidget {
  const _FareQuoteView({required this.quote});

  final LogisticsQuote quote;

  /// Row logic rewritten 2026-09-20 to mirror the real customer web app's
  /// own Fare Breakdown panel exactly (`MiniTruckBookingHosurPage.jsx`,
  /// confirmed against the actual reference source, not guessed) — row by
  /// row, rather than a generic "print every present key" list:
  ///  - Base fare always shows when present.
  ///  - Distance charge shows the "(X km × ₹Y/km)" annotation inline, same
  ///    as the web page, instead of a separate "distance charged" row.
  ///  - Loading/unloading and additional-stop charges only show when > 0
  ///    (the web page hides a present-but-zero line rather than printing
  ///    "₹0.00", which reads as more, not less, trustworthy).
  ///  - Surge only shows when the multiplier isn't 1×.
  ///  - "Minimum fare applied" is surfaced as its own note, matching the
  ///    web page's dedicated line for it, instead of being silently absent.
  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = quote.breakdown;
    final baseFare = _num(breakdown?['base_fare']);
    final distanceCharge = _num(breakdown?['distance_charge']);
    final chargeableKm = _num(breakdown?['chargeable_km']);
    final ratePerKm = _num(breakdown?['rate_per_km']);
    final loadingUnloading = _num(breakdown?['loading_unloading']) ?? 0;
    final additionalStopCharge =
        _num(breakdown?['additional_stop_charge']) ?? 0;
    final additionalStops = breakdown?['additional_stops'];
    final surgeMultiplier = _num(breakdown?['surge_multiplier']) ?? 1;
    final minimumFareApplied = breakdown?['minimum_fare_applied'] == true;
    final isDistanceMode = quote.pricingMode == 'distance' && breakdown != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Estimated Fare',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            Text(
              '₹${quote.total.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.serviceBlue,
              ),
            ),
          ],
        ),
        if (quote.isEstimate && (quote.estimateNotice ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            quote.estimateNotice!,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const Divider(height: 20, color: AppColors.border),
        if (isDistanceMode) ...[
          if (baseFare != null) _FareRow('Base fare', baseFare),
          if (distanceCharge != null)
            _FareRow(
              chargeableKm != null && ratePerKm != null
                  ? 'Distance (${chargeableKm.toStringAsFixed(1)} km × ₹${ratePerKm.toStringAsFixed(0)}/km)'
                  : 'Distance charge',
              distanceCharge,
            ),
          if (loadingUnloading > 0)
            _FareRow('Loading / unloading', loadingUnloading),
          if (additionalStopCharge > 0)
            _FareRow(
              additionalStops != null
                  ? 'Additional stops ($additionalStops)'
                  : 'Additional stops',
              additionalStopCharge,
            ),
          if (surgeMultiplier != 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Surge',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${surgeMultiplier.toStringAsFixed(2)}×',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
        ] else
          _FareRow('Trip fare', quote.total),
        if (minimumFareApplied) ...[
          const SizedBox(height: 6),
          const Text(
            'Minimum fare applied for this trip.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'This is the same authoritative number the server records — it will not change unexpectedly when you confirm.',
          style: TextStyle(fontSize: 11, color: AppColors.textHint),
        ),
      ],
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow(this.label, this.amount);

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: child,
    );
  }
}

/// One inventory row in the Packers & Movers "What are you moving?" section.
/// Only a [PmGoodsItem.configured] item gets a quantity stepper — an
/// unconfigured one (no admin-entered CFT/weight) forces the backend into
/// requires_review/requires_survey, which this screen can't turn into an
/// instant booking, so it's shown disabled with an explanation instead of a
/// stepper that would look like it works.
class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.navy : AppColors.textHint,
        ),
      ),
    );
  }
}

class _PmChoiceChip extends StatelessWidget {
  const _PmChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.serviceBlue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.serviceBlue : AppColors.border,
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.navy,
          ),
        ),
      ),
    );
  }
}

class _PmFloorStepper extends StatelessWidget {
  const _PmFloorStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _QtyButton(
              icon: Icons.remove_rounded,
              onTap: value > 0 ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            _QtyButton(
              icon: Icons.add_rounded,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

/// Renders a [PackersMoversQuote] — deliberately more cautious than
/// [_FareQuoteView] because, unlike the distance quote, this one can come
/// back needing a survey/manual review instead of an instant price; that
/// state is surfaced as a blocking notice rather than a number that looks
/// final but can't actually be booked yet (matching the backend's own
/// `verify_packers_movers_quote`, which refuses the booking in that case).
class _PmFareQuoteView extends StatelessWidget {
  const _PmFareQuoteView({required this.quote});

  final PackersMoversQuote quote;

  @override
  Widget build(BuildContext context) {
    final needsReview =
        !quote.quotable ||
        quote.requiresSurvey ||
        quote.requiresReview ||
        quote.total == null;

    if (needsReview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This move needs a quick review before we can confirm an instant price',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            quote.estimateNotice ?? quote.reviewReason ?? 'Some of the selected items need a closer look. Our team will contact you to finalize the price before this can be confirmed as an instant booking.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (quote.unrecognizedItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Needs review: ${quote.unrecognizedItems.join(', ')}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Estimated Fare',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            Text(
              '₹${quote.total!.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.serviceBlue,
              ),
            ),
          ],
        ),
        const Divider(height: 20, color: AppColors.border),
        if (quote.subtotal != null) _FareRow('Subtotal', quote.subtotal!),
        if (quote.gstAmount != null) _FareRow('GST', quote.gstAmount!),
        const SizedBox(height: 8),
        const Text(
          'This is the same authoritative number the server records — it will not change unexpectedly when you confirm.',
          style: TextStyle(fontSize: 11, color: AppColors.textHint),
        ),
      ],
    );
  }
}
