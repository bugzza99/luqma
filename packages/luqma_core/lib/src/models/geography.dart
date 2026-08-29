import 'package:freezed_annotation/freezed_annotation.dart';

import '../config/luqma_config.dart';
import 'merchant.dart';

part 'geography.freezed.dart';
part 'geography.g.dart';

@freezed
abstract class City with _$City {
  const factory City({
    required String id,
    required String name,
    @Default(true) bool isActive,
  }) = _City;

  factory City.fromJson(Map<String, dynamic> json) => _$CityFromJson(json);
}

/// The addressing unit, and the reason the app works at all in a town whose streets are
/// not numbered. A zone does three jobs at once: it prices delivery, it bounds which
/// merchants may receive an order, and it gives a courier a destination before they read
/// any detail.
@freezed
abstract class Zone with _$Zone {
  const factory Zone({
    required String id,
    required String cityId,
    required String name,

    /// Piastres, before any merchant override.
    @Default(0) int defaultDeliveryFee,
    @Default(true) bool isActive,
    @Default(0) int sortOrder,
  }) = _Zone;

  factory Zone.fromJson(Map<String, dynamic> json) => _$ZoneFromJson(json);
}

/// A named point the admin places on the branded map: a pharmacy, a mosque, a tuk-tuk
/// stop. Our own documents rather than Google Places results, so they cost nothing and
/// say what people here actually say.
@freezed
abstract class Landmark with _$Landmark {
  const factory Landmark({
    required String id,
    required String cityId,
    required String zoneId,
    required String name,
    double? lat,
    double? lng,
    String? icon,
  }) = _Landmark;

  factory Landmark.fromJson(Map<String, dynamic> json) => _$LandmarkFromJson(json);
}

@freezed
abstract class Address with _$Address {
  const factory Address({
    required String id,
    required String zoneId,

    /// Chosen from the admin's landmark list.
    String? landmarkId,
    String? landmarkName,

    /// What the customer typed when no listed landmark fit.
    String? landmarkNote,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? label,
    double? lat,
    double? lng,
  }) = _Address;

  const Address._();

  factory Address.fromJson(Map<String, dynamic> json) => _$AddressFromJson(json);

  /// One line for the courier, built from whatever parts exist.
  ///
  /// Empty parts are dropped rather than rendered as separators — a courier reading
  /// "· · ·" learns nothing, and an address that is only a zone and a landmark is a
  /// normal address here, not a broken one.
  String format({required String zoneName}) {
    final landmark = landmarkName ?? landmarkNote;
    final parts = <String>[
      zoneName,
      if (landmark != null && landmark.isNotEmpty) 'جنب $landmark',
      if (street != null && street!.isNotEmpty) street!,
      if (building != null && building!.isNotEmpty) 'عمارة $building',
      if (floor != null && floor!.isNotEmpty) 'الدور $floor',
      if (apartment != null && apartment!.isNotEmpty) 'شقة $apartment',
    ];
    return parts.join(' · ');
  }
}

/// Where an order can go, and what it costs to send it there.
abstract final class Delivery {
  const Delivery._();

  /// The fee for sending [merchant]'s order into [zone], in piastres.
  ///
  /// A merchant may set its own fee, but only inside the range the admin configured —
  /// clamped here as well as in the security rules, so the app never shows a customer a
  /// figure the server is about to reject.
  static int feeFor({
    required Merchant merchant,
    required Zone zone,
    required LuqmaConfig config,
  }) {
    final override = merchant.deliveryFeeOverride;
    if (override == null) return zone.defaultDeliveryFee;

    // Zero is a deliberate offer, not a value out of range.
    if (override == 0) return 0;
    return override.clamp(config.deliveryFeeMin, config.deliveryFeeMax);
  }

  /// Whether [merchant] delivers to [zoneId].
  ///
  /// Its own zone is always included, so filling in `servedZones` to reach further can
  /// never accidentally cut off the street the merchant is standing on.
  static bool serves({required Merchant merchant, required String zoneId}) {
    return merchant.zoneId == zoneId || merchant.servedZones.contains(zoneId);
  }
}
