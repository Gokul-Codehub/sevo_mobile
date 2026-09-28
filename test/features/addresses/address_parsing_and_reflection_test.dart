import 'package:calservices_customer/features/addresses/domain/address_models.dart';
import 'package:calservices_customer/features/addresses/domain/address_notifier.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_providers.dart';
import 'package:calservices_customer/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Address Parsing & Reflection Suite', () {
    test('ADDR-01: Address.fromJson handles String latitude and longitude without type cast error', () {
      final json = {
        'id': 130,
        'label': 'home',
        'address_line1': 'Trinity Home Decors',
        'address_line2': 'KCC NAGAR',
        'landmark': 'Near Park',
        'city': 'Hosur',
        'state': 'Tamil Nadu',
        'pincode': '635109',
        'latitude': '12.7409',
        'longitude': '77.8253',
        'is_default': 'true',
      };

      final addr = Address.fromJson(json);
      expect(addr.id, 130);
      expect(addr.addressLine1, 'Trinity Home Decors');
      expect(addr.addressLine2, 'KCC NAGAR');
      expect(addr.city, 'Hosur');
      expect(addr.state, 'Tamil Nadu');
      expect(addr.postalCode, '635109');
      expect(addr.latitude, 12.7409);
      expect(addr.longitude, 77.8253);
      expect(addr.isDefault, isTrue);
      expect(
        addr.formattedAddress,
        'Trinity Home Decors, KCC NAGAR, Near Park, Hosur, Tamil Nadu - 635109',
      );
    });

    test('ADDR-02: Address.fromJson handles flat_house_no and street_area aliases', () {
      final json = {
        'id': 131,
        'type': 'work',
        'flat_house_no': 'Flat 402, Lotus Apt',
        'street_area': 'MG Road',
        'city': 'Bengaluru',
        'state': 'Karnataka',
        'postal_code': '560001',
        'latitude': 12.9716,
        'longitude': 77.5946,
        'default': 1,
      };

      final addr = Address.fromJson(json);
      expect(addr.id, 131);
      expect(addr.addressLine1, 'Flat 402, Lotus Apt');
      expect(addr.addressLine2, 'MG Road');
      expect(addr.addressType, 'work');
      expect(addr.city, 'Bengaluru');
      expect(addr.postalCode, '560001');
      expect(addr.latitude, 12.9716);
      expect(addr.longitude, 77.5946);
      expect(addr.isDefault, isTrue);
      expect(
        addr.formattedAddress,
        'Flat 402, Lotus Apt, MG Road, Bengaluru, Karnataka - 560001',
      );
    });

    test('ADDR-03: Address.formattedAddress does not output leading comma when line1 is present', () {
      const addr = Address(
        id: 1,
        addressLine1: 'Trinity Home Decors',
        addressLine2: 'KCC NAGAR',
        city: 'Hosur',
        state: 'Karnataka',
        postalCode: '635109',
      );

      expect(addr.formattedAddress.startsWith(','), isFalse);
      expect(
        addr.formattedAddress,
        'Trinity Home Decors, KCC NAGAR, Hosur, Karnataka - 635109',
      );
    });

    testWidgets('ADDR-04: HomeScreen dynamically reflects selected address in location strip', (tester) async {
      const selected = Address(
        id: 130,
        addressLine1: 'Trinity Home Decors',
        addressLine2: 'KCC NAGAR',
        city: 'Hosur',
        state: 'Tamil Nadu',
        postalCode: '635109',
        addressType: 'home',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => const UserProfile(
                  id: 1,
                  name: 'Pradeep M',
                  phone: '+919876543210',
                )),
            categoriesProvider.overrideWith((ref) async => const []),
            selectedAddressProvider.overrideWith((ref) => selected),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('HOME: Trinity Home Decors, Hosur'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('ADDR-05: HomeScreen displays fallback text when no address is selected', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => null),
            categoriesProvider.overrideWith((ref) async => const []),
            selectedAddressProvider.overrideWith((ref) => null),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Set your service location'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });
  });
}
