import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/address_models.dart';

/// Repository for customer addresses management.
class AddressRepository {
  AddressRepository({required this.api});

  final ApiClient api;

  // ── Get all addresses ─────────────────────────────────────────────────────
  Future<Result<List<Address>>> getAddresses() async {
    try {
      final response = await api.get('/auth/customer/addresses/');
      return ResponseNormalizer.extract(response, (data) {
        final List<dynamic> list;
        if (data is List) {
          list = data;
        } else if (data is Map) {
          if (data['results'] is List) {
            list = data['results'] as List;
          } else if (data['data'] is List) {
            list = data['data'] as List;
          } else if (data['addresses'] is List) {
            list = data['addresses'] as List;
          } else {
            list = [data];
          }
        } else {
          list = const [];
        }

        return list
            .whereType<Map>()
            .map((m) => Address.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Create address ────────────────────────────────────────────────────────
  Future<Result<Address>> createAddress(Address address) async {
    try {
      final response = await api.post(
        '/auth/customer/addresses/',
        data: address.toJson()..remove('id'),
      );
      return ResponseNormalizer.extract(
        response,
        (data) => Address.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Update address ────────────────────────────────────────────────────────
  Future<Result<Address>> updateAddress(Address address) async {
    try {
      final response = await api.patch(
        '/auth/customer/addresses/${address.id}/',
        data: address.toJson(),
      );
      return ResponseNormalizer.extract(
        response,
        (data) => Address.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Delete address ────────────────────────────────────────────────────────
  Future<Result<bool>> deleteAddress(int id) async {
    try {
      await api.delete('/auth/customer/addresses/$id/');
      return const Success(true);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Set default address ───────────────────────────────────────────────────
  Future<Result<Address>> setDefaultAddress(int id) async {
    try {
      final response = await api.post('/auth/customer/addresses/$id/set-default/');
      return ResponseNormalizer.extract(
        response,
        (data) => Address.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) {
      return e.error! as ApiError;
    }
    return UnknownError(e.toString());
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  return AddressRepository(api: ref.watch(apiClientProvider));
});
