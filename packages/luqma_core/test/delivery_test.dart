import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Delivery is decided by zone, not by distance: Edku's streets are not numbered and the
/// map data is thin, so the zone is the unit the fee, the merchant's reach and the
/// courier's destination all hang off.
void main() {
  const zone = Zone(
    id: 'maamoura',
    cityId: 'edku',
    name: 'المعمورة',
    defaultDeliveryFee: 1000,
  );

  Merchant merchant({
    String zoneId = 'maamoura',
    List<String> servedZones = const [],
    int? override,
  }) {
    return Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم',
      zoneId: zoneId,
      phone: '01000000000',
      status: MerchantStatus.approved,
      servedZones: servedZones,
      deliveryFeeOverride: override,
    );
  }

  group('the fee', () {
    test('defaults to the zone the order is going to', () {
      expect(
        Delivery.feeFor(merchant: merchant(), zone: zone, config: LuqmaConfig.defaults),
        1000,
      );
    });

    test('a merchant may set its own', () {
      expect(
        Delivery.feeFor(
          merchant: merchant(override: 1500),
          zone: zone,
          config: LuqmaConfig.defaults,
        ),
        1500,
      );
    });

    // The bound exists in config and is enforced in the security rules; enforcing it
    // here too means the app never displays a fee the server is about to reject.
    test('an override below the floor is raised to it', () {
      expect(
        Delivery.feeFor(
          merchant: merchant(override: 100),
          zone: zone,
          config: LuqmaConfig.defaults,
        ),
        LuqmaConfig.defaults.deliveryFeeMin,
      );
    });

    test('an override above the ceiling is lowered to it', () {
      expect(
        Delivery.feeFor(
          merchant: merchant(override: 99999),
          zone: zone,
          config: LuqmaConfig.defaults,
        ),
        LuqmaConfig.defaults.deliveryFeeMax,
      );
    });

    test('free delivery set deliberately by a merchant is allowed through', () {
      expect(
        Delivery.feeFor(
          merchant: merchant(override: 0),
          zone: zone,
          config: LuqmaConfig.defaults,
        ),
        0,
        reason: 'zero is an offer, not a value out of range',
      );
    });
  });

  group('reach', () {
    test('a merchant always serves the zone it sits in', () {
      expect(
        Delivery.serves(merchant: merchant(servedZones: const []), zoneId: 'maamoura'),
        isTrue,
      );
    });

    test('a merchant does not serve a distant zone by default', () {
      expect(
        Delivery.serves(merchant: merchant(servedZones: const []), zoneId: 'shatt'),
        isFalse,
      );
    });

    test('an explicitly served zone is reachable', () {
      expect(
        Delivery.serves(
          merchant: merchant(servedZones: const ['shatt']),
          zoneId: 'shatt',
        ),
        isTrue,
      );
    });

    // Listing other zones must not accidentally drop the merchant's own.
    test('listing other zones keeps the merchant serving its own', () {
      expect(
        Delivery.serves(
          merchant: merchant(servedZones: const ['shatt']),
          zoneId: 'maamoura',
        ),
        isTrue,
      );
    });
  });

  group('an address as people here give it', () {
    test('reads back as zone, landmark, then the fine detail', () {
      const address = Address(
        id: 'a1',
        zoneId: 'maamoura',
        landmarkName: 'صيدلية النور',
        street: 'شارع البحر',
        building: '12',
        floor: '3',
        apartment: '5',
      );
      expect(
        address.format(zoneName: 'المعمورة'),
        'المعمورة · جنب صيدلية النور · شارع البحر · عمارة 12 · الدور 3 · شقة 5',
      );
    });

    test('missing parts are left out rather than shown empty', () {
      const address = Address(
        id: 'a1',
        zoneId: 'maamoura',
        landmarkName: 'مسجد الفتح',
      );
      expect(address.format(zoneName: 'المعمورة'), 'المعمورة · جنب مسجد الفتح');
    });

    // A courier reading "· · ·" learns nothing; an address with no landmark is a real
    // case and must still read as a sentence.
    test('an address with only a zone still reads cleanly', () {
      const address = Address(id: 'a1', zoneId: 'maamoura');
      expect(address.format(zoneName: 'المعمورة'), 'المعمورة');
    });

    test('a free-text note is used when no landmark was picked from the list', () {
      const address = Address(
        id: 'a1',
        zoneId: 'maamoura',
        landmarkNote: 'قدام الفرن البلدي',
      );
      expect(
        address.format(zoneName: 'المعمورة'),
        'المعمورة · جنب قدام الفرن البلدي',
      );
    });
  });
}
