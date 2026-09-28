import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';
import '../../../core/utils/image_url_helper.dart';

/// Route arguments for navigating to the OTP verification screen.
class OtpVerifyArgs extends Equatable {
  const OtpVerifyArgs({
    required this.identifier,
    required this.channel,
    this.resendAfterSeconds = 60,
  });

  final String identifier;
  final String channel;
  final int resendAfterSeconds;

  @override
  List<Object?> get props => [identifier, channel, resendAfterSeconds];
}

/// Result returned by OTP verify — carries tokens + user + new-user flag.
class AuthVerifyResult {
  const AuthVerifyResult({
    required this.access,
    required this.refresh,
    required this.user,
    required this.isNewUser,
  });
  final String access;
  final String refresh;
  final UserProfile user;
  final bool isNewUser;
}

/// User model matching the CalServices customer profile schema.
class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.phone,
    this.name,
    this.email,
    this.profilePictureUrl,
    this.isGuest = false,
  });

  final int id;
  final String phone;
  final String? name;
  final String? email;
  final String? profilePictureUrl;
  final bool isGuest;

  bool get isProfileComplete => name != null && name!.isNotEmpty;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['user_id'] ?? json['customer_id'];
    final firstName = json['first_name']?.toString() ?? '';
    final lastName = json['last_name']?.toString() ?? '';
    final fullName = ('$firstName $lastName').trim();
    final name = json['name']?.toString() ??
        json['full_name']?.toString() ??
        (fullName.isNotEmpty ? fullName : json['username']?.toString());

    return UserProfile(
      id: parseInt(rawId),
      phone: json['phone']?.toString() ?? json['email']?.toString() ?? json['username']?.toString() ?? '',
      name: name,
      email: json['email']?.toString(),
      // Fixed 2026-09-19: the real backend (accounts/customer_services.py:
      // get_customer_profile / update_customer_profile) returns the photo
      // under a bare `avatar` key — `profile_picture`/`avatar_url` were
      // guesses that never actually matched a live response, so an upload
      // would succeed server-side but never show up in the app until the
      // next full /auth/me/ resync happened to use a different field name.
      profilePictureUrl: ImageUrlHelper.resolve(
        json['avatar']?.toString() ??
            json['profile_picture']?.toString() ??
            json['avatar_url']?.toString(),
      ),
    );
  }

  factory UserProfile.guest() => const UserProfile(
        id: 0,
        phone: '',
        isGuest: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (profilePictureUrl != null) 'profile_picture': profilePictureUrl,
      };

  UserProfile copyWith({
    int? id,
    String? phone,
    String? name,
    String? email,
    String? profilePictureUrl,
    bool? isGuest,
  }) =>
      UserProfile(
        id: id ?? this.id,
        phone: phone ?? this.phone,
        name: name ?? this.name,
        email: email ?? this.email,
        profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
        isGuest: isGuest ?? this.isGuest,
      );

  @override
  List<Object?> get props => [id, phone, name, email, profilePictureUrl, isGuest];
}

/// Sealed auth state for the app.
sealed class AuthState extends Equatable {
  const AuthState();
}

/// Not yet determined — app is checking stored tokens on startup.
final class AuthLoading extends AuthState {
  const AuthLoading();
  @override
  List<Object?> get props => [];
}

/// No authenticated user — show login flow.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
  @override
  List<Object?> get props => [];
}

/// OTP has been sent — waiting for the code.
final class AuthOtpSent extends AuthState {
  const AuthOtpSent({required this.identifier, required this.channel});
  final String identifier;
  final String channel;
  @override
  List<Object?> get props => [identifier, channel];
}

/// Authenticated user exists. [user.isProfileComplete] indicates
/// whether to show the profile completion screen.
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user});
  final UserProfile user;
  @override
  List<Object?> get props => [user];
}
