import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A short-lived hold on a fully-booked day, handed to a customer who asked to
/// be told when it frees up. It arrives as the `waitlist_claim` token inside
/// the "A service appointment is available" notification's link and must be
/// sent back with the slot lookup (`claim_token`) and the booking
/// (`future_capacity_claim_token`) — the backend then counts that customer's
/// own claim as their space instead of the day being full.
class CapacityClaim {
  const CapacityClaim({required this.token, this.serviceSlug, this.expiresAt});

  final String token;

  /// The service (sub-service slug) the claim is for.
  final String? serviceSlug;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

final capacityClaimProvider = StateProvider<CapacityClaim?>((ref) => null);
