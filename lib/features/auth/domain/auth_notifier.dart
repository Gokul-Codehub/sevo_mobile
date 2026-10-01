import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/utils/app_logger.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// Auth state notifier — the single source of truth for authentication.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _checkStoredSession();
    return const AuthLoading();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  // ── Bootstrap ─────────────────────────────────────────────────────────────
  /// Checks stored session on app startup.
  ///
  /// The flow:
  ///   1. Read local secure storage — if no token or user, emit AuthUnauthenticated.
  ///   2. If token & user found, immediately emit AuthAuthenticated to prevent UI flicker
  ///      and allow instant offline/fast startup.
  ///   3. In the background, fetch the latest profile from /api/auth/me/ to sync user info.
  ///      If background sync fails due to network/offline, the authenticated session remains
  ///      intact. If token is expired, subsequent requests will trigger AuthInterceptor refresh.
  Future<void> _checkStoredSession() async {
    AppLogger.d('[P0-AUTH]', 'APP_START: checking stored session...');
    try {
      final user = await _repo.restoreSession();
      if (user == null) {
        AppLogger.d('[P0-AUTH]', 'AUTH_STATE_AFTER: unauthenticated (no valid session in storage)');
        state = const AuthUnauthenticated();
        return;
      }

      // Immediately establish authenticated state from valid stored credentials.
      // Phone number is intentionally not logged — user id is enough to trace the flow.
      AppLogger.d('[P0-AUTH]', 'AUTH_STATE_AFTER: authenticated (user id=${user.id}, isGuest=${user.isGuest})');
      state = AuthAuthenticated(user: user);

      // Background profile revalidation (non-destructive)
      final updatedUser = await _repo.fetchProfile();
      if (updatedUser != null) {
        AppLogger.d('[P0-AUTH]', 'PROFILE_LOAD: updated profile from /api/auth/me/ (id=${updatedUser.id})');
        state = AuthAuthenticated(user: updatedUser);
      }
    } catch (e) {
      AppLogger.d('[P0-AUTH]', 'Session check error: $e');
      if (state is AuthLoading) {
        AppLogger.d('[P0-AUTH]', 'AUTH_STATE_AFTER: unauthenticated (fallback from loading)');
        state = const AuthUnauthenticated();
      }
    }
  }

  // ── OTP Request ───────────────────────────────────────────────────────────
  /// Requests an OTP. Returns (error: null, resendAfterSeconds: N) on success,
  /// (error: "message", resendAfterSeconds: 60) on failure.
  Future<({String? error, int resendAfterSeconds})> requestOtp({
    required String identifier,
    required String channel,
  }) async {
    final result = await _repo.requestOtp(
      identifier: identifier,
      channel: channel,
    );
    return switch (result) {
      Success(:final data) => (
          error: null,
          resendAfterSeconds: (data['resend_after_seconds'] as num?)?.toInt() ?? 60,
        ),
      Failure(:final error) => (
          error: error.message,
          // Fixed 2026-10-01: a too-soon resend hits the backend's rate
          // limit (RateLimitError, HTTP 429) and the real wait time comes
          // back as `resend_after_seconds` in the error body (see
          // ErrorInterceptor's `extra` map) — e.g. "wait 42s" rather than
          // always showing a flat 60s countdown no matter how long is
          // actually left.
          resendAfterSeconds: error is ValidationError
              ? (error.extra['resend_after_seconds'] as num?)?.toInt() ?? 60
              : 60,
        ),
    };
  }

  // ── OTP Verify ────────────────────────────────────────────────────────────
  /// Returns null error on success, error message on failure.
  Future<({String? error, bool isNewUser})> verifyOtp({
    required String identifier,
    required String otp,
    required String channel,
  }) async {
    final result = await _repo.verifyOtp(
      identifier: identifier,
      otp: otp,
      channel: channel,
    );
    switch (result) {
      case Success(:final data):
        await _repo.saveVerifyResult(data);
        state = AuthAuthenticated(user: data.user);
        return (error: null, isNewUser: data.isNewUser);
      case Failure(:final error):
        return (error: error.message, isNewUser: false);
    }
  }

  // ── Profile Complete / Edit ───────────────────────────────────────────────
  /// Used by both the post-signup "Complete Profile" screen and the
  /// Profile tab's "Edit Profile" sheet.
  ///
  /// Fixed 2026-10-01: this used to call AuthRepository.completeProfile(),
  /// which 400s for any customer with no phone on file (every email-only
  /// signup) — see the detailed note on AuthRepository.updateProfile. Now
  /// routes through that phone-agnostic endpoint instead, so entering a
  /// name here actually sticks instead of silently failing and leaving the
  /// screen showing the auto-generated `cust_...` username.
  Future<String?> completeProfile({required String name, String? email}) async {
    final result = await _repo.updateProfile(
      name: name,
      email: email,
    );
    switch (result) {
      case Success(:final data):
        state = AuthAuthenticated(user: data);
        return null;
      case Failure(:final error):
        return error.message;
    }
  }

  // ── Update Avatar ─────────────────────────────────────────────────────────
  /// Uploads a new profile photo from a local file path. Returns null error
  /// on success, error message on failure — same contract as completeProfile.
  Future<String?> updateAvatar(String imagePath) async {
    final result = await _repo.updateAvatar(imagePath);
    switch (result) {
      case Success(:final data):
        state = AuthAuthenticated(user: data);
        return null;
      case Failure(:final error):
        return error.message;
    }
  }

  // ── Force unauthenticated (called by auth interceptor on refresh failure) ──
  void forceUnauthenticated() {
    state = const AuthUnauthenticated();
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    await _repo.logout();
    state = const AuthUnauthenticated();
  }

  // ── Delete Account ────────────────────────────────────────────────────────
  /// Requests backend account deletion and resets auth state to unauthenticated.
  /// Returns error string if deletion request fails, or null on success.
  Future<String?> deleteAccount() async {
    final result = await _repo.deleteAccount();
    state = const AuthUnauthenticated();
    return switch (result) {
      Success() => null,
      Failure(:final error) => error.message,
    };
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Current authenticated user, or null if not logged in.
final currentUserProvider = Provider<UserProfile?>((ref) {
  return switch (ref.watch(authProvider)) {
    AuthAuthenticated(:final user) => user,
    _ => null,
  };
});

/// True while auth state is still being determined.
final authLoadingProvider = Provider<bool>((ref) {
  return ref.watch(authProvider) is AuthLoading;
});
