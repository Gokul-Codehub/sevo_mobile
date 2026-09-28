import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';

/// Customer address entity.
class Address extends Equatable {
  const Address({
    required this.id,
    required this.addressLine1,
    this.addressLine2,
    this.landmark,
    required this.city,
    this.state = 'Karnataka',
    required this.postalCode,
    this.addressType = 'home',
    this.latitude,
    this.longitude,
    this.isDefault = false,
  });

  final int id;
  final String addressLine1;
  final String? addressLine2;
  final String? landmark;
  final String city;
  final String state;
  final String postalCode;
  final String addressType;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  String get formattedAddress {
    final parts = <String>[
      if (addressLine1.isNotEmpty) addressLine1,
      if (addressLine2 != null && addressLine2!.isNotEmpty) addressLine2!,
      if (landmark != null && landmark!.isNotEmpty)
        landmark!.toLowerCase().startsWith('near ') ? landmark! : 'Near $landmark',
      if (city.isNotEmpty) city,
      if (state.isNotEmpty && postalCode.isNotEmpty)
        '$state - $postalCode'
      else if (postalCode.isNotEmpty)
        postalCode
      else if (state.isNotEmpty)
        state,
    ];
    return parts.join(', ');
  }

  static double? _parseDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return double.tryParse(trimmed);
    }
    return null;
  }

  static bool _parseBool(dynamic raw, {bool fallback = false}) {
    if (raw == null) return fallback;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final lower = raw.trim().toLowerCase();
      if (lower == 'true' || lower == '1' || lower == 'yes') return true;
      if (lower == 'false' || lower == '0' || lower == 'no') return false;
    }
    return fallback;
  }

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: parseInt(json['id']),
      addressLine1: (json['address_line_1'] ??
              json['address_line1'] ??
              json['flat_house_no'] ??
              json['house_no'] ??
              json['line1'] ??
              json['address'] ??
              '')
          .toString()
          .trim(),
      addressLine2: (json['address_line_2'] ??
              json['address_line2'] ??
              json['street_area'] ??
              json['street'] ??
              json['area'] ??
              json['locality'] ??
              json['line2'])
          ?.toString()
          .trim(),
      landmark: json['landmark']?.toString().trim(),
      city: (json['city'] ?? 'Bengaluru').toString().trim(),
      state: (json['state'] ?? 'Karnataka').toString().trim(),
      postalCode: (json['postal_code'] ??
              json['pincode'] ??
              json['zip_code'] ??
              json['pin'] ??
              '')
          .toString()
          .trim(),
      addressType: (json['address_type'] ??
              json['type'] ??
              json['label'] ??
              json['label_display'] ??
              'home')
          .toString()
          .toLowerCase()
          .trim(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      isDefault: _parseBool(json['is_default'] ?? json['default']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'address_line1': addressLine1,
        'address_line_1': addressLine1,
        'flat_house_no': addressLine1,
        if (addressLine2 != null) 'address_line2': addressLine2,
        if (addressLine2 != null) 'address_line_2': addressLine2,
        if (addressLine2 != null) 'street_area': addressLine2,
        if (landmark != null) 'landmark': landmark,
        'city': city,
        'state': state,
        'pincode': postalCode,
        'postal_code': postalCode,
        'type': addressType,
        'label': addressType,
        'address_type': addressType,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'is_default': isDefault,
      };

  Address copyWith({
    int? id,
    String? addressLine1,
    String? addressLine2,
    String? landmark,
    String? city,
    String? state,
    String? postalCode,
    String? addressType,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) =>
      Address(
        id: id ?? this.id,
        addressLine1: addressLine1 ?? this.addressLine1,
        addressLine2: addressLine2 ?? this.addressLine2,
        landmark: landmark ?? this.landmark,
        city: city ?? this.city,
        state: state ?? this.state,
        postalCode: postalCode ?? this.postalCode,
        addressType: addressType ?? this.addressType,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        isDefault: isDefault ?? this.isDefault,
      );

  @override
  List<Object?> get props => [
        id,
        addressLine1,
        addressLine2,
        landmark,
        city,
        state,
        postalCode,
        addressType,
        latitude,
        longitude,
        isDefault,
      ];
}
