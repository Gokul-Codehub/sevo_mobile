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
/// Where the deletion code was sent (masked, e.g. `******3210`) and when it can be re-sent.
class DeletionCodeInfo {
  const DeletionCodeInfo({required this.sentTo, this.resendAfterSeconds = 60});
  final String sentTo;
  final int resendAfterSeconds;
}

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

  // ── Email + password accounts ────────────────────────────────────────────
  static AuthVerifyResult _verifyFromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    final access = (map['access'] ?? map['auth_token'] ?? '').toString();
    final refresh = (map['refresh'] ?? map['refresh_token'] ?? '').toString();
    final isNew = map['is_new_customer'] == true || map['is_new_user'] == true;
    final userMap = map['user'] is Map ? Map<String, dynamic>.from(map['user'] as Map) : map;
    return AuthVerifyResult(
      access: access,
      refresh: refresh,
      user: UserProfile.fromJson(userMap),
      isNewUser: isNew,
    );
  }

  /// POST /auth/customer/signup/request/ - validates the form and emails a 6-digit code.
  /// Success data: {resend_after_seconds, email_masked}.
  Future<Result<Map<String, dynamic>>> signupRequest({
    required String fullName,
    required String email,
    required String mobile,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final response = await api.post('/auth/customer/signup/request/', data: {
        'full_name': fullName.trim(),
        'email': email.trim(),
        'mobile_number': mobile.trim(),
        'password': password,
        'confirm_password': confirmPassword,
      });
      return ResponseNormalizer.extract(
        response,
        (json) => json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{},
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// POST /auth/customer/signup/verify/ - creates the account and signs the customer in.
  Future<Result<AuthVerifyResult>> signupVerify({required String email, required String otp}) async {
    try {
      final response = await api.post('/auth/customer/signup/verify/', data: {
        'email': email.trim(),
        'otp': otp.trim(),
      });
      return ResponseNormalizer.extract(response, _verifyFromJson);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// POST /auth/customer/signup/resend/
  Future<Result<Map<String, dynamic>>> signupResend({required String email}) async {
    try {
      final response = await api.post('/auth/customer/signup/resend/', data: {'email': email.trim()});
      return ResponseNormalizer.extract(
        response,
        (json) => json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{},
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// POST /auth/customer/login/ - sign in with email / mobile / username + password.
  Future<Result<AuthVerifyResult>> passwordLogin({required String identifier, required String password}) async {
    try {
      final response = await api.post('/auth/customer/login/', data: {
        'identifier': identifier.trim(),
        'password': password,
      });
      return ResponseNormalizer.extract(response, _verifyFromJson);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// POST /auth/password/set/ - for a signed-in customer who has no password yet.
  Future<Result<bool>> setPassword({required String newPassword, required String confirmPassword}) async {
    try {
      final response = await api.post('/auth/password/set/', data: {
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      });
      return ResponseNormalizer.extract(response, (_) => true);
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

  // ── Update Profile (name/email) ──────────────────────────────────────────
  /// PATCH /auth/customer/profile/update/
  ///
  /// Fixed 2026-10-01: the Edit Profile screen (and the one-time
  /// post-signup "Complete Profile" screen) called [completeProfile] above,
  /// which hits `/auth/customer/profile/complete/`. That endpoint's backend
  /// implementation (accounts/services.py::complete_customer_profile)
  /// unconditionally raises "Mobile number is required to complete customer
  /// profile." whenever the account has no phone on file and the request
  /// doesn't supply one — which is every customer who signed up with email
  /// only, since neither Flutter screen has a phone field. The save
  /// silently 400s every time, so the name never actually changes and the
  /// profile keeps showing the auto-generated `cust_<email-local-part>`
  /// username fallback from [UserProfile.fromJson] instead.
  ///
  /// This method calls the separate, already-existing
  /// `/auth/customer/profile/update/` endpoint instead (the same one
  /// [updateAvatar] below uses for photos) — it is IsAuthenticated-gated
  /// (no `customer_id` needed, unlike `/profile/complete/`'s AllowAny +
  /// manual id lookup), has no phone requirement, and accepts
  /// `first_name`/`last_name` directly. The entered full name is split the
  /// same way the backend's own `complete_customer_profile` already does
  /// it (first word = first_name, remainder = last_name) so both endpoints
  /// stay consistent.
  ///
  /// Note: unlike `/profile/complete/`, this endpoint does not set the
  /// backend's `profile_complete` flag — that flag isn't read anywhere in
  /// this app (see [UserProfile.isProfileComplete], computed purely from
  /// whether a name is present) or in any other traced backend endpoint,
  /// so it's safe to leave unset here; it only matters if something in the
  /// admin/CRM side filters customers by that flag.
  Future<Result<UserProfile>> updateProfile({
    required String name,
    String? email,
    String? phone,
  }) async {
    try {
      final parts = name.trim().split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      final response = await api.patch(
        '/auth/customer/profile/update/',
        data: {
          'first_name': firstName,
          'last_name': lastName,
          if (email != null && email.isNotEmpty) 'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
      final result = ResponseNormalizer.extract(
        response,
        (json) => UserProfile.fromJson(
          json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{},
        ),
      );
      // Same persistence rule as completeProfile/updateAvatar — without
      // this, a restart before the next /auth/me/ resync would show the
      // pre-edit name again.
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

  // ── Delete Account (OTP-confirmed) ───────────────────────────────────────
  /// Step 1: `POST /auth/customer/account/delete/request/` - the server checks the account may be deleted
  /// (no active booking or order) and sends a one-time code to the customer's own phone / e-mail.
  /// A refusal comes back as a [ValidationError] with code `ACTIVE_ACTIVITY` (counts in `extra['details']`).
  Future<Result<DeletionCodeInfo>> requestAccountDeletion() async {
    try {
      final response = await api.post('/auth/customer/account/delete/request/', data: <String, dynamic>{});
      return ResponseNormalizer.extract(response, (json) {
        final m = json is Map ? Map<String, dynamic>.from(json) : const <String, dynamic>{};
        return DeletionCodeInfo(
          sentTo: m['sent_to']?.toString() ?? '',
          resendAfterSeconds: int.tryParse(m['resend_after_seconds']?.toString() ?? '') ?? 60,
        );
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// Step 2: `POST /auth/customer/account/delete/confirm/ {otp}`. The phone is wiped ONLY when the server
  /// confirms the deletion - a failure never signs the customer out of an account that still exists.
  Future<Result<bool>> confirmAccountDeletion(String otp) async {
    try {
      final response = await api.post('/auth/customer/account/delete/confirm/', data: {'otp': otp.trim()});
      final result = ResponseNormalizer.extract(response, (_) => true);
      if (result is Success<bool>) {
        await storage.clearAll();
        await storage.clearCartStorage();
        await storage.clearSelectedAddress();
      }
      return result;
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Restore session ──────────────────────────────────────────────────────
  /// Restores session from local storage. Returns null if no token found.
  /// NOTE: Call [validateSession] or [fetchProfile] to verify/sync the token with the server.
  Future<UserProfile?> restoreSession() async {
    final hasAccess = await storage.hasAccessToken();
    final refreshToken = await storage.getRefreshToken();
    final hasRefreshToken = refreshToken?.isNotEmpty == true;
    AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: hasAccessToken=$hasAccess, hasRefreshToken=$hasRefreshToken');
    // A signed-in customer stays signed in as long as EITHER token is on the device: a missing access
    // token is recovered by the silent refresh on the first request. Only when both are truly absent
    // (never signed in, or explicitly signed out) is there no session. Storage is never purged here:
    // a failed read must not destroy a good session; logout/revocation clear it explicitly elsewhere.
    final hasToken = hasAccess || hasRefreshToken;
    if (!hasToken) {
      AppLogger.d('[P0-AUTH]', 'TOKEN_LOAD: No access or refresh token found — no session.');
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
