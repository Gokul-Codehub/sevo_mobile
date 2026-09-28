import 'dart:convert';
import 'package:calservices_customer/features/addresses/domain/address_models.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/work_extension/domain/work_extension_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('API Parsing & Contract Resilience Suite', () {
    test('PARSE-01: Booking.fromJson handles items as a Map instead of List without throwing', () {
      final json = {
        'id': 104,
        'request_id': 'CAL-20260822-104',
        'status': 'confirmed',
        'total_amount': '499.00',
        'items': {
          'id': 228,
          'service': {
            'id': 228,
            'title': 'Beetroot',
            'slug': 'veg-beetroot',
            'price': '37.00',
          },
          'quantity': 2,
        },
        'available_actions': ['cancel', 'reschedule'],
      };

      final booking = Booking.fromJson(json);
      expect(booking.id, equals(104));
      expect(booking.items.length, equals(1));
      expect(booking.items.first.service.title, equals('Beetroot'));
      expect(booking.items.first.quantity, equals(2));
      expect(booking.canCancel, isTrue);
    });

    test('PARSE-02: Booking.fromJson handles cart_data as JSON string', () {
      final json = {
        'id': 105,
        'status': 'new_request',
        'total': '74.00',
        'cart_data': jsonEncode([
          {
            'id': 228,
            'title': 'Beetroot',
            'slug': 'veg-beetroot',
            'price': '37.00',
            'quantity': 2,
          }
        ]),
        'available_actions': 'cancel, reschedule',
      };

      final booking = Booking.fromJson(json);
      expect(booking.id, equals(105));
      expect(booking.items.length, equals(1));
      expect(booking.items.first.service.title, equals('Beetroot'));
      expect(booking.availableActions, contains('cancel'));
      expect(booking.availableActions, contains('reschedule'));
    });

    test('PARSE-03: Booking.fromJson handles single-service booking without items array (DRF shape)', () {
      final json = {
        'id': 106,
        'service_id': 101,
        'issue_title': 'AC General Service',
        'service_category': 15,
        'total_amount': '499.00',
        'status': 'assigned',
        'technician': {
          'id': 501,
          'name': 'Ramesh Kumar',
          'phone': '9876543210',
          'rating': 4.95,
        },
      };

      final booking = Booking.fromJson(json);
      expect(booking.id, equals(106));
      expect(booking.items.length, equals(1));
      expect(booking.items.first.service.title, equals('AC General Service'));
      expect(booking.items.first.service.categoryId, equals(15));
      expect(booking.technician?.name, equals('Ramesh Kumar'));
    });

    test('PARSE-04: Category.fromJson handles subcategories as Map with results', () {
      final json = {
        'id': 18,
        'name': 'Farm-Fresh Vegetables & Groceries',
        'slug': 'vegetables_groceries',
        'subcategories': {
          'count': 1,
          'results': [
            {
              'id': 50,
              'name': 'Fresh Vegetables',
              'slug': 'vegetables',
            }
          ]
        }
      };

      final cat = Category.fromJson(json);
      expect(cat.id, equals(18));
      expect(cat.subcategories.length, equals(1));
      expect(cat.subcategories.first.name, equals('Fresh Vegetables'));
    });

    test('PARSE-05: WorkExtensionProposal.fromJson handles items as single Map or results envelope', () {
      final json = {
        'id': 201,
        'booking_id': 104,
        'technician_name': 'Suresh',
        'amount': '350.00',
        'items': {
          'title': 'Capacitor',
          'quantity': 1,
          'price': '350.00',
        }
      };

      final prop = WorkExtensionProposal.fromJson(json, 'token_xyz');
      expect(prop.bookingId, equals(104));
      expect(prop.items.length, equals(1));
      expect(prop.items.first.title, equals('Capacitor'));
    });

    test('PARSE-06: Address.fromJson handles various address keys and string coordinates', () {
      final json = {
        'id': 133,
        'address_line_1': 'Trinity Home Decors',
        'street_area': 'KCC Nagar',
        'city': 'Hosur',
        'state': 'Tamil Nadu',
        'pincode': '635109',
        'latitude': '12.7409',
        'longitude': '77.8253',
      };

      final addr = Address.fromJson(json);
      expect(addr.id, equals(133));
      expect(addr.city, equals('Hosur'));
      expect(addr.postalCode, equals('635109'));
      expect(addr.latitude, equals(12.7409));
    });
  });
}
