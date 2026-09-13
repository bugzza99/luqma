import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  const zoneId = 'z1';

  group('merchant address model', () {
    test('carries address fields', () {
      const m = Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم الشاطئ',
        zoneId: zoneId,
        phone: '01000000000',
        landmarkId: 'l1',
        landmarkName: 'صيدلية النور',
        street: 'شارع البحر',
        lat: 31.3084,
        lng: 30.2939,
      );

      expect(m.landmarkId, 'l1');
      expect(m.landmarkName, 'صيدلية النور');
      expect(m.street, 'شارع البحر');
      expect(m.lat, 31.3084);
      expect(m.lng, 30.2939);
    });

    test('hasAddress is false when shop only has a zone', () {
      const bare = Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'بدون عنوان',
        zoneId: zoneId,
        phone: '01000000000',
      );

      expect(bare.hasAddress, isFalse);
      expect(bare.formatAddress(zoneName: 'إدكو'), isNull);
    });

    test('hasAddress is true with a landmark or street', () {
      const withLandmark = Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'معلم فقط',
        zoneId: zoneId,
        phone: '01000000000',
        landmarkName: 'صيدلية النور',
      );

      expect(withLandmark.hasAddress, isTrue);
      expect(withLandmark.formatAddress(zoneName: 'المعمورة'),
          'المعمورة · جنب صيدلية النور');

      const withStreet = Merchant(
        id: 'm2',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'شارع فقط',
        zoneId: zoneId,
        phone: '01000000000',
        street: 'شارع البحر',
      );

      expect(withStreet.hasAddress, isTrue);
      expect(withStreet.formatAddress(zoneName: 'المعمورة'),
          'المعمورة · شارع البحر');

      const full = Merchant(
        id: 'm3',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'كامل',
        zoneId: zoneId,
        phone: '01000000000',
        landmarkName: 'صيدلية النور',
        street: 'شارع البحر',
      );

      expect(full.hasAddress, isTrue);
      expect(full.formatAddress(zoneName: 'المعمورة'),
          'المعمورة · جنب صيدلية النور · شارع البحر');
    });

    test('serializes and deserializes address fields through json', () {
      final json = {
        'id': 'm1',
        'cityId': 'edku',
        'type': 'restaurant',
        'name': 'مطعم الشاطئ',
        'zoneId': zoneId,
        'phone': '01000000000',
        'landmarkId': 'l1',
        'landmarkName': 'صيدلية النور',
        'street': 'شارع البحر',
        'lat': 31.3084,
        'lng': 30.2939,
      };

      final m = Merchant.fromJson(json);
      expect(m.landmarkId, 'l1');
      expect(m.landmarkName, 'صيدلية النور');
      expect(m.street, 'شارع البحر');
      expect(m.lat, 31.3084);
      expect(m.lng, 30.2939);

      final out = m.toJson();
      expect(out['landmarkId'], 'l1');
      expect(out['landmarkName'], 'صيدلية النور');
      expect(out['street'], 'شارع البحر');
      expect(out['lat'], 31.3084);
      expect(out['lng'], 30.2939);
    });

    test('converts postgres snake_case columns via ColumnNames.toModel', () {
      final dbRow = {
        'id': 'm1',
        'city_id': 'edku',
        'type': 'restaurant',
        'name': 'مطعم الشاطئ',
        'zone_id': zoneId,
        'phone': '01000000000',
        'landmark_id': 'l1',
        'landmark_name': 'صيدلية النور',
        'street': 'شارع البحر',
        'lat': 31.3084,
        'lng': 30.2939,
      };

      final modelMap = ColumnNames.toModel(dbRow);
      final m = Merchant.fromJson(modelMap);
      expect(m.landmarkId, 'l1');
      expect(m.landmarkName, 'صيدلية النور');
      expect(m.street, 'شارع البحر');
      expect(m.lat, 31.3084);
      expect(m.lng, 30.2939);
    });
  });

  group('merchant repository write path', () {
    test('rowFor carries address fields', () {
      const m = Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم الشاطئ',
        zoneId: zoneId,
        phone: '01000000000',
        landmarkId: 'l1',
        landmarkName: 'صيدلية النور',
        street: 'شارع البحر',
        lat: 31.3084,
        lng: 30.2939,
      );

      final row = SupabaseMerchantRepository.rowFor(m);
      expect(row['landmark_id'], 'l1');
      expect(row['landmark_name'], 'صيدلية النور');
      expect(row['street'], 'شارع البحر');
      expect(row['lat'], 31.3084);
      expect(row['lng'], 30.2939);
    });

    test('rowFor normalizes half a pin to both null', () {
      const halfLat = Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'نصف دبوس',
        zoneId: zoneId,
        phone: '01000000000',
        lat: 31.3084,
        lng: null,
      );

      final row1 = SupabaseMerchantRepository.rowFor(halfLat);
      expect(row1['lat'], isNull);
      expect(row1['lng'], isNull);

      const halfLng = Merchant(
        id: 'm2',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'نصف دبوس آخر',
        zoneId: zoneId,
        phone: '01000000000',
        lat: null,
        lng: 30.2939,
      );

      final row2 = SupabaseMerchantRepository.rowFor(halfLng);
      expect(row2['lat'], isNull);
      expect(row2['lng'], isNull);
    });

    test('rowFor treats empty landmarkId as null', () {
      const m = Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'معلم فارغ',
        zoneId: zoneId,
        phone: '01000000000',
        landmarkId: '',
      );

      final row = SupabaseMerchantRepository.rowFor(m);
      expect(row['landmark_id'], isNull);
    });
  });
}
