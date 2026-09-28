import 'dart:convert';
import 'dart:io';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/response_normalizer.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Production Fixture Contract Tests', () {
    test('Categories fixture parses into List<Category>', () {
      final file = File('test/fixtures/categories.json');
      final jsonMap = jsonDecode(file.readAsStringSync());
      final response = Response(
        requestOptions: RequestOptions(path: '/catalog/categories/'),
        data: jsonMap,
      );

      final result = ResponseNormalizer.extract(
        response,
        (json) => (json as List<dynamic>)
            .map((e) => Category.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

      expect(result, isA<Success<List<Category>>>());
      final categories = (result as Success<List<Category>>).data;
      expect(categories.length, equals(9));

      final vegCategory = categories.firstWhere((c) => c.slug == 'vegetables_groceries');
      expect(vegCategory.id, equals(18));
      expect(vegCategory.name, equals('Farm-Fresh Vegetables & Groceries'));
    });

    test('Category 18 (Vegetables & Groceries) services fixture parses cleanly', () {
      final file = File('test/fixtures/category_18_services.json');
      final jsonMap = jsonDecode(file.readAsStringSync());
      final response = Response(
        requestOptions: RequestOptions(path: '/catalog/services/?category_id=18'),
        data: jsonMap,
      );

      final result = ResponseNormalizer.extract(
        response,
        (json) => (json as List<dynamic>)
            .map((e) => ServiceItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

      expect(result, isA<Success<List<ServiceItem>>>());
      final services = (result as Success<List<ServiceItem>>).data;
      expect(services.length, equals(43));

      for (final s in services) {
        expect(s.flowType, equals(CatalogFlowType.grocery));
      }
    });

    test('Beetroot fixture parses into ServiceItem with grocery flowType', () {
      final file = File('test/fixtures/service_beetroot.json');
      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      final beetroot = ServiceItem.fromJson(jsonMap);
      expect(beetroot.id, equals(228));
      expect(beetroot.title, equals('Beetroot'));
      expect(beetroot.slug, equals('veg-beetroot'));
      expect(beetroot.flowType, equals(CatalogFlowType.grocery));
      expect(beetroot.price, equals(Decimal.parse('37.00')));
    });

    test('Category 15 (AC & Appliance) services fixture parses cleanly with serviceBooking flowType', () {
      final file = File('test/fixtures/category_15_services.json');
      final jsonMap = jsonDecode(file.readAsStringSync());
      final response = Response(
        requestOptions: RequestOptions(path: '/catalog/services/?category_id=15'),
        data: jsonMap,
      );

      final result = ResponseNormalizer.extract(
        response,
        (json) => (json as List<dynamic>)
            .map((e) => ServiceItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

      expect(result, isA<Success<List<ServiceItem>>>());
      final services = (result as Success<List<ServiceItem>>).data;

      for (final s in services) {
        expect(s.flowType, equals(CatalogFlowType.serviceBooking));
      }
    });

    test('AC combo service fixture parses into ServiceItem with serviceBooking flowType', () {
      final file = File('test/fixtures/service_ac_repair.json');
      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      final acService = ServiceItem.fromJson(jsonMap);
      expect(acService.id, equals(490));
      expect(acService.title, equals('2-in-1 Combo AC Power Jet Service'));
      expect(acService.slug, equals('ac-combo-2-units'));
      expect(acService.flowType, equals(CatalogFlowType.serviceBooking));
      expect(acService.price, equals(Decimal.parse('899.00')));
    });

    test('Auth OTP response fixture parses cleanly into AuthVerifyResult and UserProfile', () {
      final file = File('test/fixtures/auth_otp_response.json');
      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      final userMap = jsonMap['user'] as Map<String, dynamic>;
      final user = UserProfile.fromJson(userMap);
      expect(user.id, equals(7988));
      expect(user.phone, equals('9876543210'));
      expect(user.name, equals('Gokul M'));
    });

    test('Booking order response fixture parses cleanly into Booking domain model', () {
      final file = File('test/fixtures/booking_order_response.json');
      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final data = jsonMap['data'] as Map<String, dynamic>;

      final booking = Booking.fromJson(data);
      expect(booking.id, equals(104));
      expect(booking.requestId, equals('CAL-20260823-104'));
      expect(booking.status, equals('new_request'));
      expect(booking.totalAmount, equals(Decimal.parse('59.00')));
      expect(booking.advanceAmount, equals(Decimal.parse('59.00')));
      expect(booking.balanceAmount, equals(Decimal.zero));
      expect(booking.items.length, equals(1));
      expect(booking.items.first.service.title, equals('Beetroot'));
      expect(booking.availableActions, contains('cancel'));
      expect(booking.availableActions, contains('track'));
    });
  });
}
