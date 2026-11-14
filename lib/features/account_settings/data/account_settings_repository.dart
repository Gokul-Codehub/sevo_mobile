import 'package:dio/dio.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/errors/api_error.dart';
import '../../app_update/data/app_version_repository.dart' show AppUpdateStore, InstalledAppReader, PackageInfoReader;
import '../../../core/foundation/foundation_repository.dart' show FoundationRepository;
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;

class DeviceSession {
  const DeviceSession({
    required this.deviceId,
    required this.model,
    required this.osVersion,
    required this.lastSeen,
    required this.current,
  });
  final String deviceId;
  final String model;
  final String osVersion;
  final DateTime? lastSeen;
  final bool current;

  static DeviceSession? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['device_id'];
    if (id is! String || id.isEmpty) return null;
    return DeviceSession(
      deviceId: id,
      model: raw['model'] is String && (raw['model'] as String).isNotEmpty ? raw['model'] as String : 'Unknown device',
      osVersion: raw['os_version'] is String ? raw['os_version'] as String : '',
      lastSeen: DateTime.tryParse(raw['last_seen'] is String ? raw['last_seen'] as String : '')?.toLocal(),
      current: raw['current'] == true,
    );
  }
}

/// Notification categories the customer can switch (server field name -> label).
const Map<String, ({String label, String hint})> kNotificationToggles = {
  'booking_confirmations': (label: 'Booking confirmations', hint: 'When a booking is confirmed or cancelled'),
  'technician_updates': (label: 'Technician updates', hint: 'Assigned, on the way, arrived, delayed'),
  'reschedule_updates': (label: 'Reschedule updates', hint: 'When a new time is approved or declined'),
  'completion_feedback': (label: 'Completion & feedback', hint: 'When the work is done'),
  'payment_receipts': (label: 'Payments & receipts', hint: 'Payment confirmations and receipts'),
  'refund_updates': (label: 'Refund updates', hint: 'Progress of a refund'),
  'complaint_updates': (label: 'Support updates', hint: 'Replies to your complaints'),
  'promotional_offers': (label: 'Offers & promotions', hint: 'Coupons and deals (off unless you turn it on)'),
};

/// Devices signed in to the account, and notification preferences.
class AccountSettingsRepository {
  AccountSettingsRepository({required this.api, this.installId, InstalledAppReader? installed})
      : _installed = installed ?? const PackageInfoReader();
  final ApiClient api;
  final Future<String?> Function()? installId;
  final InstalledAppReader _installed;

  /// Feedback / problem report. The app version and device are attached automatically.
  Future<bool> sendFeedback({required String category, required String message, String? bookingRef}) async {
    try {
      final app = await _installed.read();
      String? deviceId;
      try {
        deviceId = await installId?.call();
      } catch (_) {}
      await api.post('/app/feedback/', data: {
        'category': category,
        'message': message.trim(),
        if (bookingRef != null && bookingRef.trim().isNotEmpty) 'booking_ref': bookingRef.trim(),
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        'version': app.versionName,
        'app': 'customer',
        'platform': FoundationRepository.platformName,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Result<List<DeviceSession>>> devices() async {
    try {
      final response = await api.get('/app/sessions/');
      final payload = ResponseNormalizer.extractPayload(response);
      switch (payload) {
        case Success(:final data):
          final list = data is Map && data['results'] is List ? data['results'] as List : const [];
          return Success([for (final r in list) ?DeviceSession.tryParse(r)]);
        case Failure(:final error):
          return Failure(error);
      }
    } on DioException catch (e) {
      return Failure(e.error is ApiError ? e.error! as ApiError : const NetworkError());
    } catch (_) {
      return const Failure(NetworkError());
    }
  }

  Future<bool> signOutDevice(String deviceId) => _post('/app/sessions/$deviceId/revoke/');
  Future<bool> signOutOthers() => _post('/app/sessions/revoke-all/');

  Future<bool> _post(String path) async {
    try {
      await api.post(path, data: <String, dynamic>{});
      return true;
    } catch (_) {
      return false;
    }
  }

  // Notification switches belong to THIS PHONE, not to a login: they are kept on the device (and, when the
  // customer is signed in, also copied to the account so the server can honour them).
  static const _prefsKey = 'device_notification_prefs_v1';
  static const _local = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<Map<String, bool>> localPreferences() async {
    try {
      final raw = await _local.read(key: _prefsKey);
      final data = raw == null || raw.isEmpty ? const {} : jsonDecode(raw);
      return {
        for (final k in kNotificationToggles.keys) k: data is Map && data[k] is bool ? data[k] as bool : _defaultFor(k),
      };
    } catch (_) {
      return {for (final k in kNotificationToggles.keys) k: _defaultFor(k)};
    }
  }

  /// Everything is on by default except promotional offers (the server's own default too).
  static bool _defaultFor(String key) => key != 'promotional_offers';

  Future<void> _saveLocal(String field, bool value) async {
    try {
      final map = await localPreferences();
      map[field] = value;
      await _local.write(key: _prefsKey, value: jsonEncode(map));
    } catch (_) {}
  }

  Future<Result<Map<String, bool>>> preferences({bool signedIn = false}) async {
    if (!signedIn) return Success(await localPreferences());
    try {
      final response = await api.get('/auth/notification-preferences/');
      final data = response.data;
      if (data is! Map) return const Failure(ParseError('Unexpected response.'));
      return Success({for (final k in kNotificationToggles.keys) k: data[k] != false});
    } on DioException {
      return Success(await localPreferences());
    } catch (_) {
      return Success(await localPreferences());
    }
  }

  Future<bool> setPreference(String field, bool value, {bool signedIn = false}) async {
    await _saveLocal(field, value);
    if (!signedIn) return true;
    try {
      await api.patch('/auth/notification-preferences/', data: {field: value});
    } catch (_) {
      // Saved on this phone already; the account copy catches up the next time it is changed.
    }
    return true;
  }
}

final accountSettingsRepositoryProvider =
    Provider<AccountSettingsRepository>((ref) => AccountSettingsRepository(
          api: ref.watch(apiClientProvider),
          installId: AppUpdateStore().installId,
        ));

final deviceSessionsProvider = FutureProvider.autoDispose<List<DeviceSession>>((ref) async {
  final result = await ref.watch(accountSettingsRepositoryProvider).devices();
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

final notificationPreferencesProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final signedIn = ref.watch(isUserAuthenticatedProvider);
  final result = await ref.watch(accountSettingsRepositoryProvider).preferences(signedIn: signedIn);
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
