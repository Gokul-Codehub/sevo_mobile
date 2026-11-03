import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../catalog/data/marketplace_catalog_repository.dart';
import '../../home/domain/home_flow_mode.dart';
import '../../logistics/data/logistics_repository.dart';

/// Whether we serve a place. `unknown` means "could not tell" (no location yet, network down, check still running):
/// it NEVER blocks anything, exactly like the big apps, which only stop you when they are sure.
enum Coverage { yes, no, unknown }

/// What we serve at the delivery point, per vertical. Services (technicians) and groceries (warehouse delivery) are
/// decided by different engines on the server (service zones vs warehouse polygons), so they genuinely differ: this
/// puts both answers in one place so the whole app agrees on what is available where.
class AreaCoverage extends Equatable {
  const AreaCoverage({
    this.services = Coverage.unknown,
    this.groceries = Coverage.unknown,
    this.servicesMessage,
    this.groceriesMessage,
  });

  final Coverage services;
  final Coverage groceries;
  final String? servicesMessage;
  final String? groceriesMessage;

  Coverage of(HomeFlowMode mode) => mode == HomeFlowMode.services ? services : groceries;
  String? messageOf(HomeFlowMode mode) => mode == HomeFlowMode.services ? servicesMessage : groceriesMessage;

  @override
  List<Object?> get props => [services, groceries, servicesMessage, groceriesMessage];
}

/// The "we are not here yet" state for the vertical the customer is looking at.
class NotServed extends Equatable {
  const NotServed({required this.mode, this.message, this.otherServed});

  final HomeFlowMode mode;
  final String? message;

  /// The other vertical, when it IS available here, so the customer is offered it instead of a dead end.
  final HomeFlowMode? otherServed;

  @override
  List<Object?> get props => [mode, message, otherServed];
}

/// Blocks only when we are SURE the active vertical is not served here.
NotServed? notServedFor(AreaCoverage c, HomeFlowMode mode) {
  if (c.of(mode) != Coverage.no) return null;
  final other = mode == HomeFlowMode.services ? HomeFlowMode.groceries : HomeFlowMode.services;
  return NotServed(mode: mode, message: c.messageOf(mode), otherServed: c.of(other) == Coverage.yes ? other : null);
}

/// Services coverage of the delivery point (the server's service zones). Needs real coordinates; without them, or if
/// the check fails, the answer is `unknown`: never a guess, never "available" by default.
final servicesCoverageProvider = FutureProvider<({Coverage coverage, String? message})>((ref) async {
  final point = ref.watch(deliveryPointProvider);
  if (point.lat == null || point.lng == null) return (coverage: Coverage.unknown, message: null);
  final result = await ref.watch(logisticsRepositoryProvider).checkServiceability(
        postalCode: point.pincode,
        latitude: point.lat,
        longitude: point.lng,
      );
  return switch (result) {
    Success(:final data) when data.isUnknown => (coverage: Coverage.unknown, message: null),
    Success(:final data) => (coverage: data.isServiceable ? Coverage.yes : Coverage.no, message: data.isServiceable ? null : data.message),
    Failure() => (coverage: Coverage.unknown, message: null),
  };
});

/// Everything we know about what is served at the delivery point.
final areaCoverageProvider = Provider<AreaCoverage>((ref) {
  final services = ref.watch(servicesCoverageProvider);
  final zone = ref.watch(deliveryZoneProvider);

  Coverage fromZone() {
    if (zone.isLoading) return Coverage.unknown;
    return switch (zone.valueOrNull?.status) {
      DeliveryZoneStatus.serviceable => Coverage.yes,
      DeliveryZoneStatus.unserviceable => Coverage.no,
      _ => Coverage.unknown,
    };
  }

  final s = services.isLoading ? null : services.valueOrNull;
  return AreaCoverage(
    services: s?.coverage ?? Coverage.unknown,
    servicesMessage: s?.message,
    groceries: fromZone(),
    groceriesMessage: zone.valueOrNull?.message,
  );
});
