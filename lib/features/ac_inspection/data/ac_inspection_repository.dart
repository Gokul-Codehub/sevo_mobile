import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../../addresses/domain/address_models.dart';
import '../../booking/data/booking_repository.dart';
import '../../booking/domain/booking_models.dart';
import '../domain/ac_inspection_models.dart';

/// Air Conditioner "Inspection & Diagnostic Visit" (job_type ESTIMATION).
///
/// Mirrors the web app: config from `GET /settings/ac-inspection/config/`
/// and the booking is the normal `POST /booking/` multipart form with
/// `job_type=ESTIMATION` plus the AC details; the backend
/// (`EstimationService.create_estimation_booking`) takes the fee from its own
/// config, validates the AC fields and the slot, and creates the estimation.
class AcInspectionRepository {
  AcInspectionRepository({required this.api, required this.bookings});

  final ApiClient api;
  final BookingRepository bookings;

  Future<Result<AcInspectionConfig>> getConfig() async {
    try {
      final response = await api.get('/settings/ac-inspection/config/');
      return ResponseNormalizer.extract(response, (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        return AcInspectionConfig.fromJson(map);
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  Future<Result<Booking>> book({
    required AcInspectionConfig config,
    required AcInspectionDetails details,
    required Address address,
    required String date,
    required String timeSlot,
    required String customerName,
    required String phone,
    String? email,
    Uint8List? photoBytes,
    String? photoFileName,
    String? idempotencyKey,
  }) async {
    try {
      final fee = config.fee.toString();
      final fields = <String, dynamic>{
        'customer_name': customerName,
        'phone': phone,
        if (email != null && email.contains('@')) 'email': email,
        'service_category': 'ac_appliance',
        'issue_title': 'AC Inspection & Diagnostic Visit',
        'description': details.symptom,
        'address': address.formattedAddress,
        'saved_address_id': address.id.toString(),
        if (address.latitude != null) 'latitude': address.latitude!.toStringAsFixed(6),
        if (address.longitude != null) 'longitude': address.longitude!.toStringAsFixed(6),
        'preferred_date': date,
        'preferred_time': timeSlot,
        'total_amount': fee,
        'payment_method': 'COD',
        'job_type': 'ESTIMATION',
        'estimation_fee': fee,
        'ac_type': details.acType,
        'ac_brand': details.brand,
        'ac_quantity': details.quantity.toString(),
        'ac_capacity': details.capacity,
        'customer_symptom': details.symptom,
        if (details.notes != null && details.notes!.trim().isNotEmpty) 'customer_notes': details.notes!.trim(),
        'cart_data': jsonEncode([
          {
            'id': 'hvac-ac-inspection',
            'name': 'AC Inspection',
            'price': config.fee.toDouble(),
            'quantity': 1,
            'jobType': 'ESTIMATION',
            'ac_brand': details.brand,
            'ac_type': details.acType,
            'ac_quantity': details.quantity,
            'categoryName': 'Air Conditioner',
          }
        ]),
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      };
      if (photoBytes != null && photoBytes.isNotEmpty) {
        fields['photo'] = MultipartFile.fromBytes(photoBytes, filename: photoFileName ?? 'ac_photo.jpg');
      }
      final response = await api.post(
        '/booking/',
        data: FormData.fromMap(fields),
        options: (idempotencyKey != null) ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null,
      );
      final created = ResponseNormalizer.extract(
        response,
        (data) => Booking.fromJson(data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{}),
      );
      switch (created) {
        case Success(:final data):
          final detail = await bookings.getBookingDetail(data.id);
          return detail is Success<Booking> ? detail : Success(data);
        case Failure(:final error):
          return Failure(error);
      }
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) return e.error! as ApiError;
    return UnknownError(e.toString());
  }
}

final acInspectionRepositoryProvider = Provider<AcInspectionRepository>((ref) {
  return AcInspectionRepository(
    api: ref.watch(apiClientProvider),
    bookings: ref.watch(bookingRepositoryProvider),
  );
});

final acInspectionConfigProvider = FutureProvider.autoDispose<AcInspectionConfig>((ref) async {
  final result = await ref.watch(acInspectionRepositoryProvider).getConfig();
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
