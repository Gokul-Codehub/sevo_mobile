import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/api_error.dart';
import '../network/api_client.dart';
import '../network/response_normalizer.dart';
import 'foundation_models.dart';

/// Result of one config fetch. [notModified] means the cached copy is current.
class FoundationFetch {
  const FoundationFetch({this.config, this.etag, this.raw, this.notModified = false});
  final FoundationConfig? config;
  final String? etag;
  final Map<String, dynamic>? raw;
  final bool notModified;
}

/// `GET /api/app/config/` - public, works before login, never throws.
class FoundationRepository {
  FoundationRepository({required this.api, this.appKey = 'customer', this.installId});

  final ApiClient api;
  final String appKey;
  final Future<String?> Function()? installId;

  /// Config must never hold the app up: short budget, any failure is a [Failure].
  static const Duration timeout = Duration(seconds: 3);

  static String get platformName => !kIsWeb && Platform.isIOS ? 'ios' : 'android';

  /// Best-effort upload of queued client errors. Returns false on any failure.
  Future<bool> reportErrors(List<Map<String, String>> errors, {required String version}) async {
    if (errors.isEmpty) return true;
    try {
      String? deviceId;
      try {
        deviceId = await installId?.call();
      } catch (_) {}
      await api.post(
        '/app/errors/',
        data: {'device_id': deviceId ?? '', 'app': appKey, 'version': version, 'errors': errors},
        options: Options(sendTimeout: timeout, receiveTimeout: timeout, extra: {'skipRetry': true}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Result<FoundationFetch>> fetch({required String version, required int build, String? etag}) async {
    try {
      String? deviceId;
      try {
        deviceId = await installId?.call();
      } catch (_) {}
      final response = await api.get(
        '/app/config/',
        queryParameters: {
          'app': appKey,
          'platform': platformName,
          'version': version,
          'build': build,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        },
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          extra: {'skipRetry': true},
          headers: {if (etag != null && etag.isNotEmpty) 'If-None-Match': '"$etag"'},
          validateStatus: (s) => s != null && (s == 304 || (s >= 200 && s < 300)),
        ),
      );
      if (response.statusCode == 304) return const Success(FoundationFetch(notModified: true));
      final payload = ResponseNormalizer.extractPayload(response);
      switch (payload) {
        case Success(:final data):
          final config = FoundationConfig.tryParse(data);
          if (config == null) return const Failure(ParseError('The config server sent an unexpected answer.'));
          return Success(FoundationFetch(
            config: config,
            etag: config.version,
            raw: Map<String, dynamic>.from(data as Map),
          ));
        case Failure(:final error):
          return Failure(error);
      }
    } on DioException catch (e) {
      if (e.error is ApiError) return Failure(e.error! as ApiError);
      return const Failure(NetworkError());
    } catch (_) {
      return const Failure(NetworkError());
    }
  }
}

/// Last good config, so a cold start (or an outage) uses it instantly.
class FoundationCache {
  FoundationCache([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;
  static const _key = 'sevo_foundation_config_v1';

  Future<FoundationConfig?> read() async {
    try {
      final text = await _storage.read(key: _key);
      if (text == null || text.isEmpty) return null;
      return FoundationConfig.tryParse(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> raw) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(raw));
    } catch (_) {}
  }
}
