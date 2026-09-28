import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/utils/image_url_helper.dart';
import 'package:calservices_customer/features/addresses/domain/address_models.dart';
import 'package:calservices_customer/features/addresses/presentation/screens/add_edit_address_screen.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/logistics/data/logistics_repository.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_models.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_providers.dart';
import 'package:calservices_customer/features/tracking/data/tracking_service.dart';
import 'package:calservices_customer/features/tracking/domain/tracking_models.dart';
import 'package:calservices_customer/features/tracking/presentation/screens/live_tracking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockTrackingNotifier extends TrackingNotifier {
  @override
  TrackingUpdate build(String arg) {
    return TrackingUpdate(
      latitude: 12.754598,
      longitude: 77.834477,
      status: 'en_route',
      statusMessage: 'Technician is en route',
      etaMinutes: 12,
      technicianName: 'Ramesh Kumar',
      updatedAt: DateTime(2026, 8, 24),
      isLiveWs: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 8.2 — Media & Image Resolution Tests (IMG-P01 to IMG-P10)', () {
    test('IMG-P01: ImageUrlHelper resolves Beetroot to photographic mockup', () {
      final photo = ImageUrlHelper.getFoodItemPhoto('Fresh Beetroot 500g', isGrocery: true);
      expect(photo, contains('beetroot.jpg'));
    });

    test('IMG-P02: ImageUrlHelper resolves Amla / Amlaa / Nellikai to photographic mockup', () {
      final photo1 = ImageUrlHelper.getFoodItemPhoto('Organic Amla 250g');
      final photo2 = ImageUrlHelper.getFoodItemPhoto('Amlaa (Nellikai)');
      expect(photo1, contains('amla.jpg'));
      expect(photo2, contains('amla.jpg'));
    });

    test('IMG-P03: ImageUrlHelper resolves Zucchini to photographic mockup', () {
      final photo = ImageUrlHelper.getFoodItemPhoto('Green Zucchini 500g');
      expect(photo, contains('zucchini.jpg'));
    });

    test('IMG-P04: ImageUrlHelper resolves Bitter Gourd / Karela to photographic mockup', () {
      final photo = ImageUrlHelper.getFoodItemPhoto('Bitter Gourd (Pavakkai / Karela)');
      expect(photo, contains('karela.jpg'));
    });

    test('IMG-P05: ImageUrlHelper resolves Drumstick / Murungakkai to photographic mockup', () {
      final photo = ImageUrlHelper.getFoodItemPhoto('Country Drumstick (Murungakkai)');
      expect(photo, contains('drumstick.jpg'));
    });

    test('IMG-P06: ImageUrlHelper bypasses dead /media/catalog/ links and returns studio photo', () {
      final resolved = ImageUrlHelper.resolve(
        '/media/catalog/catalog_458e0083382547608b7f87b613d388d9.webp',
        title: 'Beetroot',
        categoryId: 18,
      );
      expect(resolved, isNotNull);
      expect(resolved, contains('beetroot.jpg'));
      expect(resolved, isNot(contains('catalog_458e0083')));
    });

    test('IMG-P07: ImageUrlHelper.getCategoryPhoto resolves all 9 categories', () {
      expect(ImageUrlHelper.getCategoryPhoto('ac-appliance', 'AC & Appliance'), contains('category_appliance.png'));
      expect(ImageUrlHelper.getCategoryPhoto('electrician', 'Electrician, Plumbing & Carpentry'), contains('category_repair.png'));
      expect(ImageUrlHelper.getCategoryPhoto('deep-cleaning', 'Deep Cleaning & Housekeeping'), contains('category_cleaning.png'));
      expect(ImageUrlHelper.getCategoryPhoto('vegetables', 'Farm-Fresh Vegetables & Groceries'), contains('vegetables_realistic.png'));
      expect(ImageUrlHelper.getCategoryPhoto('goods-transports', 'Goods Transports & Logistics'), contains('category_goods_transports.png'));
      expect(ImageUrlHelper.getCategoryPhoto('painting', 'Painting & Waterproofing'), contains('category_painting.png'));
      expect(ImageUrlHelper.getCategoryPhoto('masonry', 'Masonry & Home Construction'), contains('service_building.png'));
      expect(ImageUrlHelper.getCategoryPhoto('pest-control', 'Pest Control'), contains('category_cleaning.png'));
    });

    // Note: IMG-P08 (Tier-2 resolveLocalAssetFallback alias mapping) was
    // removed along with the method itself — the bundled asset folders it
    // pointed at were empty, so it was deleted as dead code.

    test('IMG-P09: Category.fromJson resolves category image even if API returns null/empty image', () {
      final json = {
        'id': 12,
        'name': 'Deep Cleaning & Housekeeping',
        'slug': 'deep-cleaning',
        'image': null,
        'is_active': true,
      };
      final category = Category.fromJson(json);
      expect(category.image, isNotNull);
      expect(category.image, contains('category_cleaning.png'));
    });

    test('IMG-P10: ServiceItem.fromJson resolves working photographic URL when given dead catalog link', () {
      final json = {
        'id': 101,
        'title': 'Organic Amlaa 500g',
        'slug': 'veg-amlaa',
        'image': '/media/catalog/dead_link.webp',
        'category_id': 18,
        'category_slug': 'vegetables',
        'price': '45.00',
      };
      final item = ServiceItem.fromJson(json);
      expect(item.imageUrl, contains('amla.jpg'));
      expect(item.imageUrl, isNot(contains('dead_link')));
    });
  });

  group('Phase 8.2 — Map & Location Tests (MAP01 to MAP09)', () {
    testWidgets('MAP01: LiveTrackingScreen renders without crashing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingProvider.overrideWith(() => _MockTrackingNotifier()),
          ],
          child: const MaterialApp(
            home: LiveTrackingScreen(identifier: 'TRK-1001'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Live Technician Tracking'), findsOneWidget);
    });

    testWidgets('MAP02: LiveTrackingScreen displays live status badge and ETA', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingProvider.overrideWith(() => _MockTrackingNotifier()),
          ],
          child: const MaterialApp(
            home: LiveTrackingScreen(identifier: 'TRK-1002'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('LIVE WS'), findsOneWidget);
      expect(find.text('Estimated Arrival'), findsOneWidget);
    });

    test('MAP03: TrackingUpdate parses latitude, longitude, and ETA', () {
      final update = TrackingUpdate.fromJson({
        'latitude': 12.754598,
        'longitude': 77.834477,
        'eta_minutes': 12,
        'technician_name': 'Ramesh Kumar',
        'status': 'en_route',
      });
      expect(update.latitude, equals(12.754598));
      expect(update.longitude, equals(77.834477));
      expect(update.etaMinutes, equals(12));
      expect(update.technicianName, equals('Ramesh Kumar'));
    });

    testWidgets('MAP04: AddEditAddressScreen renders address form with map pin picker', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceabilityProvider('635109').overrideWith((ref) => ServiceabilityResult.available()),
          ],
          child: const MaterialApp(
            home: AddEditAddressScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add New Address'), findsOneWidget);
      expect(find.text('Tap to pin service location'), findsOneWidget);
      expect(find.text('Save Address'), findsOneWidget);
    });

    test('MAP05: Address.fromJson parses latitude and longitude correctly', () {
      final addr = Address.fromJson({
        'id': 1,
        'address_line_1': 'Plot 45, SIPCOT Phase 2',
        'city': 'Hosur',
        'state': 'Tamil Nadu',
        'postal_code': '635109',
        'latitude': '12.754598',
        'longitude': '77.834477',
      });
      expect(addr.latitude, equals(12.754598));
      expect(addr.longitude, equals(77.834477));
      expect(addr.city, equals('Hosur'));
    });

    test('MAP06: Address.toJson preserves latitude and longitude', () {
      const addr = Address(
        id: 1,
        addressLine1: 'Plot 45, SIPCOT Phase 2',
        city: 'Hosur',
        postalCode: '635109',
        latitude: 12.754598,
        longitude: 77.834477,
      );
      final json = addr.toJson();
      expect(json['latitude'], equals(12.754598));
      expect(json['longitude'], equals(77.834477));
    });

    test('MAP07: Address formattedAddress formats components with postal code', () {
      const addr = Address(
        id: 1,
        addressLine1: 'Flat 101, Green Meadows',
        addressLine2: 'Mookandapalli',
        city: 'Hosur',
        state: 'Tamil Nadu',
        postalCode: '635126',
      );
      expect(addr.formattedAddress, contains('Flat 101, Green Meadows, Mookandapalli, Hosur, Tamil Nadu - 635126'));
    });

    test('MAP08: TrackingUpdate.initial provides safe, honest fallback defaults', () {
      // Updated 2026-08-27: .initial() previously claimed isLiveWs: true and
      // a fake 15-minute ETA before any real position had ever arrived —
      // indistinguishable from a genuine live update. It now marks itself
      // as not-yet-live (hasLiveData: false) so the UI can show a waiting
      // state instead of a fabricated "LIVE GPS" signal.
      final initial = TrackingUpdate.initial('Test Tech');
      expect(initial.technicianName, equals('Test Tech'));
      expect(initial.hasLiveData, isFalse);
      expect(initial.isLiveWs, isFalse);
    });

    test('MAP09: ImageUrlHelper mapCategoryIcon maps icons for all trade types', () {
      expect(ImageUrlHelper.mapCategoryIcon('carrot', 'vegetables'), equals(Icons.shopping_basket_rounded));
      expect(ImageUrlHelper.mapCategoryIcon('truck', 'goods-transports'), equals(Icons.local_shipping_rounded));
      expect(ImageUrlHelper.mapCategoryIcon('sparkles', 'cleaning'), equals(Icons.cleaning_services_rounded));
      expect(ImageUrlHelper.mapCategoryIcon('wind', 'ac-appliance'), equals(Icons.ac_unit_rounded));
      expect(ImageUrlHelper.mapCategoryIcon('bolt', 'electrician'), equals(Icons.electric_bolt_rounded));
    });
  });

  group('Phase 8.2 — Serviceability & Service Zone Tests (ZONE-01 to ZONE-10)', () {
    test('ZONE-01: ServiceabilityResult parses in_zone: true response from server', () {
      final result = ServiceabilityResult.fromJson({
        'in_zone': true,
        'zone': {'id': 2, 'name': 'hosur'},
        'available_services': ['ac-repair', 'vegetables', 'full-house-cleaning'],
        'message': 'Service available in hosur.',
      });
      expect(result.isServiceable, isTrue);
      expect(result.inZone, isTrue);
      expect(result.hubName, equals('hosur'));
      expect(result.availableServices, contains('vegetables'));
    });

    test('ZONE-02: ServiceabilityResult parses in_zone: false response from server', () {
      final result = ServiceabilityResult.fromJson({
        'in_zone': false,
        'zone': null,
        'available_services': [],
        'message': 'Selected location is outside our operational service zones.',
      });
      expect(result.isServiceable, isFalse);
      expect(result.inZone, isFalse);
      expect(result.message, contains('outside our operational service zones'));
    });

    test('ZONE-03: ServiceabilityResult.available defaults to serviceable with Hosur Hub', () {
      final result = ServiceabilityResult.available();
      expect(result.isServiceable, isTrue);
      expect(result.inZone, isTrue);
      expect(result.hubName, equals('Hosur Hub'));
    });

    test('ZONE-04: ServiceabilityResult.unavailable defaults to unserviceable', () {
      final result = ServiceabilityResult.unavailable('Area not covered');
      expect(result.isServiceable, isFalse);
      expect(result.inZone, isFalse);
      expect(result.message, equals('Area not covered'));
    });

    test('ZONE-05: serviceabilityProvider rejects invalid pincodes without crashing', () async {
      final container = ProviderContainer();
      final res = await container.read(serviceabilityProvider('123').future);
      expect(res.isServiceable, isFalse);
      expect(res.message, contains('valid 6-digit'));
      container.dispose();
    });

    test('ZONE-06: LogisticsRepository fails open gracefully on network error', () async {
      final container = ProviderContainer();
      final repo = container.read(logisticsRepositoryProvider);

      final result = await repo.checkServiceability(postalCode: '635109');
      switch (result) {
        case Success(:final data):
          expect(data.isServiceable, isTrue);
          expect(data.hubName, isNotNull);
        case Failure(:final error):
          fail('Should not fail: $error');
      }
      container.dispose();
    });

    test('ZONE-07: Service slug normalization handles all category variations', () {
      expect(Category(id: 18, name: 'Farm-Fresh Vegetables', slug: 'vegetables').flowType, equals(CatalogFlowType.grocery));
      expect(Category(id: 1, name: 'AC & Appliance Repair', slug: 'ac-appliance').flowType, equals(CatalogFlowType.serviceBooking));
    });

    test('ZONE-08: ServiceItem displayUnit fallback logic works correctly', () {
      final item1 = ServiceItem.fromJson({
        'id': 1,
        'title': 'Fresh Carrots',
        'slug': 'veg-carrots',
        'unit': '1 kg',
      });
      expect(item1.displayUnit, equals('1 kg'));

      final item2 = ServiceItem.fromJson({
        'id': 2,
        'title': 'Fresh Tomatoes',
        'slug': 'veg-tomatoes',
        'short_description': 'Pack of 500g fresh farm harvest',
      });
      expect(item2.displayUnit, equals('Pack of 500g fresh farm harvest'));
    });

    test('ZONE-09: ServiceabilityResult preserves openAccess flag', () {
      final result = ServiceabilityResult.fromJson({
        'in_zone': true,
        'open_access': true,
        'message': 'Open Access Zone',
      });
      expect(result.openAccess, isTrue);
      expect(result.isServiceable, isTrue);
    });

    test('ZONE-10: ServiceItem flow classification isolates grocery vs service bookings', () {
      final groceryItem = ServiceItem.fromJson({
        'id': 101,
        'title': 'Farm Fresh Beetroot',
        'slug': 'veg-beetroot',
        'category_id': 18,
      });
      expect(groceryItem.flowType, equals(CatalogFlowType.grocery));

      final serviceItem = ServiceItem.fromJson({
        'id': 201,
        'title': 'Split AC Deep Clean Service',
        'slug': 'ac-service-cleaning',
        'category_id': 1,
      });
      expect(serviceItem.flowType, equals(CatalogFlowType.serviceBooking));
    });
  });
}
