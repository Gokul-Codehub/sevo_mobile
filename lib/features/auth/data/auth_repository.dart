import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/auth_models.dart';

/// Auth repository — all authentication API calls.
///
/// Endpoint contracts from Handover Bible §4:
///   POST /auth/customer/otp/request/
///   POST /auth/customer/otp/verify/
///   POST /auth/customer/profile/complete/
///   POST /auth/refresh/            ← BCR-001 (cookie-only currently)
///   POST /auth/logout/
class AuthRepository {
  AuthRepository({
    required this.api,
    required this.storage,
  });

  final ApiClient api;
  final SecureStorage storage;

  // ── OTP Request ──────────────────────────────────────────────────────────
  /// POST /auth/customer/otp/request/
  /// Body: {identifier: "...", channel: "phone" | "email"}
  Future<Result<Map<String, dynamic>>> requestOtp({
    required String identifier,
    required String channel,
  }) async {
    try {
      final ch = channel.trim().toLowerCase();
      final normChannel = (ch == 'sms' || ch == 'phone') ? 'phone' : 'email';
      final body = {
        'identifier': identifier.trim(),
        'channel': normChannel,
      };
      final response = await api.post('/auth/customer/otp/request/', data: body);
      return ResponseNormalizer.extract(
        response,
        (json) => json is Map<String, dynamic> ? json : <String, dynamic>{},
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── OTP Verify ───────────────────────────────────────────────────────────
  /// POST /auth/customer/otp/verify/
  /// Returns [AuthVerifyResult] with access/refresh tokens + user profile.
  Future<Result<AuthVerifyResult>> verifyOtp({
    required String identifier,
    required String otp,
    required String channel,
  }) async {
    try {
      final ch = channel.trim().toLowerCase();
      final normChannel = (ch == 'sms' || ch == 'phone') ? 'phone' : 'email';
      final response = await api.post('/auth/customer/otp/verify/', data: {
        'identifier': identifier.trim(),
        'channel': normChannel,
        'otp_code': otp.trim(),
      });
      return ResponseNormalizer.extract(response, (json) {
        final map = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
        final access = (map['access'] ?? map['auth_token'] ?? '').toString();
        final refresh = (map['refresh'] ?? map['refresh_token'] ?? '').toString();
        final isNew = map['is_new_customer'] == true || map['is_new_user'] == true;

        final userMap = map['user'] is Map<String, dynamic>
            ? map['user'] as Map<String, dynamic>
            : (map['user'] is Map
                ? Map<String, dynamic>.from(map['user'] as Map)
                : map);

        return AuthVerifyResult(
          access: access,
          refresh: refresh,
          user: UserProfile.fromJson(userMap),
          isNewUser: isNew,
        );
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Profile Complete ─────────────────────────────────────────────────────
  /// POST /auth/customer/profile/complete/
  ///
  /// Fixed 2026-08-27: the live backend rejected every call here with
  /// "customer_id and full_name are required." — confirmed by testing on
  /// device — because this was sending `name`/`email` only. The backend
  /// wants `customer_id` (the authenticated user's own id) and `full_name`
  /// specifically. Both the old and new field names are sent together so
  /// this keeps working if the contract is later normalized on either side.
  Future<Result<UserProfile>> completeProfile({
    required String name,
    String? email,
    int? customerId,
  }) async {
    try {
      final response = await api.post(
        '/auth/customer/profile/complete/',
        data: {
          if (customerId != null && customerId > 0) 'customer_id': customerId,
          'full_name': name,
          'name': name,
          if (email != null && email.isNotEmpty) 'email': email,
        },
      );
      final result = ResponseNormalizer.extract(
        response,
        (json) => UserProfile.fromJson(
          json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{},
        ),
      );
      // Fixed 2026-08-27: this previously updated only the in-memory auth
      // state (via AuthNotifier.completeProfile) and never wrote the new
      // name/email back to secure storage. The very next time the stored
      // session was restored on app start — or if the background
      // /auth/me/ resync happened to fail — restoreSession() would read
      // the OLD cached user JSON and show the pre-edit name again. Persist
      // the updated profile here so the edit sticks across restarts.
      if (result is Success<UserProfile>) {
        await storage.setUserJson(jsonEncode(result.data.toJson()));
      }
      return result;
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Update Avatar ─────────────────────────────────────────────────────────
  /// PATCH /api/auth/customer/profile/update/ (multipart) — Added 2026-09-16,
  /// corrected 2026-09-19 after reviewing the real backend source
  /// (accounts/urls.py + accounts/views.py:CustomerProfileUpdateView +
  /// accounts/customer_services.py:update_customer_profile). The endpoint
  /// this originally called, `/v1/auth/profile/`, does not exist anywhere in
  /// the backend — it was a guess based on a stale reference doc. The real,
  /// customer-specific profile endpoint is this one: it's IsCustomer-gated
  /// (matching every other `/auth/customer/...` call in this file), accepts
  /// `parser_classes = [FormParser, MultiPartParser, JSONParserClass]`, and
  /// explicitly allow-lists `avatar` as a file field alongside
  /// first_name/last_name/phone/email.
  ///
  /// Profile & Settings previously only ever READ `profile_picture`/
  /// `avatar_url` from whatever the backend returned — there was no upload
  /// flow at all, so the app could show a photo but never let the customer
  /// set or change one. This is a different endpoint from
  /// /auth/customer/profile/complete/ above (that one is the one-time
  /// name/email onboarding step after signup).
  Future<Result<UserProfile>> updateAvatar(String imagePath) async {
    try {
      final fileName = imagePath.split(RegExp(r'[\\/]')).last;
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(imagePath, filename: fileName),
      });
      final response = await api.patch(
        '/auth/customer/profile/update/',
        data: formData,
      );
      final result = ResponseNormalizer.extract(
        response,
        (json) => UserProfile.fromJson(
          json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{},
        ),
      );
      // Same persistence rule as completeProfile above: without this, a
      // restart before the next /auth/me/ resync would show the old/no
      // avatar again.
      if (result is Success<UserProfile>) {
        await storage.setUserJson(jsonEncode(result.data.toJson()));
      }
      return result;
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      await api.post('/auth/logout/');
    } catch (_) {
      // Best-effort logout
    } finally {
      await storage.clearAll();
    }
  }

  // ── Restore session ──────────────────────────────────────────────────────
  /// Restores session from local storage. Returns null if no token found.
  /// NOTE: Call [validateSession] or [fetchProfile] to verify/sync the token with the server.
  Future<UserProfile?> restoreSession() async {
    final hasToken = await storage.hasAccessToken();
    final refreshToken = await storage.getRefreshToken();
    final hasRefreshToken = refreshToken?.isNotEmpty == true;
    AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: hasAccessToken=$hasToken, hasRefreshToken=$hasRefreshToken');
    if (!hasToken) {
      // Fixed 2026-09-16 — this used to purge (storage.clearAll()) the
      // instant the access token read came back empty, with NO regard for
      // whether a refresh token was still sitting right there in the same
      // storage. That converted every transient/false-negative access-token
      // read (see SecureStorage._readSafe's own note — a documented
      // encryptedSharedPreferences failure mode) into an irreversible
      // logout: the refresh token and cached user JSON were destroyed
      // before anything had a chance to use them, so the very next app
      // open always needed a fresh OTP login even though the session was
      // still perfectly recoverable a moment earlier.
      //
      // Only purge now when there is genuinely nothing left to recover —
      // no refresh token either. That's the real "never logged in" /
      // "fully logged out" case this branch was meant for. When a refresh
      // token IS still present, leave storage untouched and just report
      // "no session yet" for this cold start: the interceptor's own
      // 401→refresh→retry path (or the next successful read of the access
      // token) gets a chance to recover the session instead of it being
      // permanently gone.
      if (!hasRefreshToken) {
        AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: No access or refresh token found. Purging stale keys.');
        await storage.clearAll();
      } else {
        AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: Access token missing but a refresh token is still present — '
            'NOT purging storage (likely a transient read miss, not a real logout).');
      }
      return null;
    }
    final userJson = await storage.getUserJson();
    AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: userJsonPresent=${userJson?.isNotEmpty == true}');
    if (userJson != null && userJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(userJson);
        final user = UserProfile.fromJson(
          Map<String, dynamic>.from(decoded as Map),
        );
        if (!user.isGuest) {
          // Phone number is intentionally not logged — user id is enough to trace the flow.
          AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: restored user profile id=${user.id}');
          return user;
        }
      } catch (e) {
        AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: failed to parse user JSON: $e');
      }
    }
    // Token exists but cached user JSON is missing/corrupt — restore with placeholder and let fetchProfile() populate it
    AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: token exists, placeholder profile returned');
    return const UserProfile(id: 0, phone: '');
  }

  // ── Fetch Profile (non-destructive) ───────────────────────────────────────
  /// Fetches the latest profile from GET /auth/me/.
  /// If successful, updates the cached user JSON in secure storage.
  /// Never clears credentials on network errors, timeouts, or 500s.
  Future<UserProfile?> fetchProfile() async {
    if (!await storage.hasAccessToken()) return null;
    try {
      AppLogger.d('[P0-AUTH]', 'PROFILE_LOAD: calling GET /api/auth/me/ ...');
      final response = await api.get('/auth/me/');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          final dataMap = Map<String, dynamic>.from(data);
          final userMap = dataMap['data'] is Map
              ? Map<String, dynamic>.from(dataMap['data'] as Map)
              : (dataMap['user'] is Map
                  ? Map<String, dynamic>.from(dataMap['user'] as Map)
                  : dataMap);
          final updated = UserProfile.fromJson(userMap);
          AppLogger.d('[P0-AUTH]', 'PROFILE_LOAD: success for user id=${updated.id}');
          await storage.setUserJson(jsonEncode(updated.toJson()));
          return updated;
        }
      }
      return null;
    } catch (e) {
      AppLogger.d('[P0-AUTH]', 'PROFILE_LOAD: GET /api/auth/me/ failed (non-destructive): $e');
      return null;
    }
  }

  // ── Validate session against server ──────────────────────────────────────
  /// Calls GET /api/auth/me/ to verify the stored access token is still valid.
  /// Returns true if valid or if network is temporarily unreachable.
  Future<bool> validateSession() async {
    if (!await storage.hasAccessToken()) return false;
    try {
      final response = await api.get('/auth/me/');
      return response.statusCode == 200;
    } on DioException catch (e) {
      // Only return false if the server explicitly responded with 401
      if (e.response?.statusCode == 401) {
        return false;
      }
      // For network errors/timeouts/500, treat session as still valid locally
      return true;
    } catch (_) {
      return true;
    }
  }

  // ── Persist tokens ────────────────────────────────────────────────────────
  Future<void> saveVerifyResult(AuthVerifyResult result) async {
    await storage.setAccessToken(result.access);
    if (result.refresh.isNotEmpty) {
      await storage.setRefreshToken(result.refresh);
    }
    await storage.setUserJson(jsonEncode(result.user.toJson()));
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException) {
      if (e.error is ApiError) {
        return e.error! as ApiError;
      }
      final data = e.response?.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['error'] is Map) {
          final errMap = Map<String, dynamic>.from(map['error'] as Map);
          final msg = errMap['message']?.toString();
          if (msg != null && msg.isNotEmpty) return ValidationError(msg);
        }
        if (map['detail'] != null) {
          return ValidationError(map['detail'].toString());
        }
      }
    }
    return UnknownError(e.toString());
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    storage: ref.watch(secureStorageProvider),
  );
});
