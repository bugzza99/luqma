import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// Zones and landmarks, against a real Postgres.
///
/// The port of `test/geography_writes_test.dart`, which ran against an in-memory
/// Firestore. There is no in-memory Supabase, and after the audit that is a feature
/// rather than a gap: the fake was what let a broken query look green.
void main() {
  late LiveDatabase live;
  late SupabaseGeographyRepository repository;
  late String cityId;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseGeographyRepository(live.client);
  });

  setUp(() async {
    cityId = await live.makeCity();
  });

  tearDown(() => live.dropCity(cityId));
  tearDownAll(() => live.close());

  Zone newZone({String name = 'المعمورة', int fee = 1000, int sortOrder = 0}) =>
      Zone(id: '', cityId: cityId, name: name, defaultDeliveryFee: fee,
           sortOrder: sortOrder);

  group('zones', () {
    test('a new zone gets an id and comes back', () async {
      final saved = await repository.saveZone(newZone());

      expect(saved.valueOrNull?.id, isNotEmpty);
      final zones = await repository.zones(cityId: cityId);
      expect(zones.valueOrNull?.single.name, 'المعمورة');
    });

    test('editing a zone does not create a second one', () async {
      final created = (await repository.saveZone(newZone())).valueOrNull!;

      await repository.saveZone(created.copyWith(defaultDeliveryFee: 1200));

      final zones = (await repository.zones(cityId: cityId)).valueOrNull!;
      expect(zones, hasLength(1));
      expect(zones.single.defaultDeliveryFee, 1200);
    });

    // A zone with orders against it cannot simply vanish, or those addresses lose the one
    // field a courier reads first. Deactivating keeps history readable.
    test('a zone is deactivated rather than deleted', () async {
      final created = (await repository.saveZone(newZone())).valueOrNull!;

      await repository.setZoneActive(created.id, false);

      expect((await repository.zones(cityId: cityId)).valueOrNull, isEmpty);
      expect(
        (await repository.zones(cityId: cityId, includeInactive: true)).valueOrNull,
        hasLength(1),
      );
    });

    // The list is what an admin reorders and a customer scrolls, so the order is part of
    // the answer rather than something the screen sorts out afterwards.
    test('they arrive in the order the admin set', () async {
      await repository.saveZone(newZone(name: 'تالتة', sortOrder: 2));
      await repository.saveZone(newZone(name: 'أولى', sortOrder: 0));
      await repository.saveZone(newZone(name: 'تانية', sortOrder: 1));

      final zones = (await repository.zones(cityId: cityId)).valueOrNull!;
      expect(zones.map((z) => z.name), ['أولى', 'تانية', 'تالتة']);
    });

    // Every city-scoped read is filtered, and a query that forgets is a query that hands
    // Edku another city's zones.
    test('another city\'s zones are not in the list', () async {
      final other = await live.makeCity();
      await live.client.from('zones').insert({'city_id': other, 'name': 'برّه'});

      final zones = (await repository.zones(cityId: cityId)).valueOrNull!;
      expect(zones, isEmpty);

      await live.dropCity(other);
    });
  });

  group('landmarks', () {
    Future<String> aZone() async =>
        (await repository.saveZone(newZone())).valueOrNull!.id;

    test('a new landmark comes back in its zone', () async {
      final zoneId = await aZone();

      await repository.saveLandmark(
        Landmark(id: '', cityId: cityId, zoneId: zoneId, name: 'المسجد الكبير'),
      );

      final landmarks = (await repository.landmarks(cityId: cityId)).valueOrNull!;
      expect(landmarks.single.name, 'المسجد الكبير');
      expect(landmarks.single.zoneId, zoneId);
    });

    // An address keeps the landmark *name* it was saved with, so removing a wrong entry
    // costs no history — which is why these delete outright and zones do not.
    test('a landmark can be deleted outright', () async {
      final zoneId = await aZone();
      final created = (await repository.saveLandmark(
        Landmark(id: '', cityId: cityId, zoneId: zoneId, name: 'غلط'),
      )).valueOrNull!;

      await repository.deleteLandmark(created.id);

      expect((await repository.landmarks(cityId: cityId)).valueOrNull, isEmpty);
    });

    test('editing a landmark does not create a second one', () async {
      final zoneId = await aZone();
      final created = (await repository.saveLandmark(
        Landmark(id: '', cityId: cityId, zoneId: zoneId, name: 'المسجد'),
      )).valueOrNull!;

      await repository.saveLandmark(created.copyWith(name: 'المسجد الكبير'));

      final landmarks = (await repository.landmarks(cityId: cityId)).valueOrNull!;
      expect(landmarks, hasLength(1));
      expect(landmarks.single.name, 'المسجد الكبير');
    });
  });

  group('landmark suggestions', () {
    // What the query reads is the order's own copy of the address, which is exactly why
    // that copy exists: a courier cannot read another person's address collection.
    Future<void> placeOrder({required String zoneId, String? note}) async {
      final customerUid = await live.makeCustomer();

      final merchant = await live.client.from('merchants').insert({
        'city_id': cityId, 'type': 'restaurant', 'name': 'مطعم',
        'zone_id': zoneId, 'phone': '0100',
      }).select().single();

      await live.client.from('orders').insert({
        'city_id': cityId,
        'customer_uid': customerUid,
        'customer_name': 'عميل',
        'customer_phone': '0100',
        'merchant_id': merchant['id'],
        'merchant_name': 'مطعم',
        'zone_id': zoneId,
        'type': 'instant',
        'items': <dynamic>[],
        'pricing': <String, dynamic>{'total': 0},
        'address': note != null
            ? {'zoneId': zoneId, 'landmarkNote': note}
            : {'zoneId': zoneId, 'landmarkId': 'l1'},
      });
    }

    test('are read off recent orders', () async {
      final zoneId = await aZoneFor(repository, cityId);
      await placeOrder(zoneId: zoneId, note: 'جنب الصيدلية');

      final notes = (await repository.landmarkNotes(cityId: cityId)).valueOrNull!;
      expect(notes.single.text, 'جنب الصيدلية');
    });

    test('carry the zone the order was going to', () async {
      final zoneId = await aZoneFor(repository, cityId);
      await placeOrder(zoneId: zoneId, note: 'جنب الصيدلية');

      final notes = (await repository.landmarkNotes(cityId: cityId)).valueOrNull!;
      expect(notes.single.zoneId, zoneId);
    });

    // An order that picked a listed landmark says nothing new. Only the ones that had to
    // type their own are of any use here.
    test('an order that chose a listed landmark contributes nothing', () async {
      final zoneId = await aZoneFor(repository, cityId);
      await placeOrder(zoneId: zoneId);

      expect((await repository.landmarkNotes(cityId: cityId)).valueOrNull, isEmpty);
    });
  });
}

Future<String> aZoneFor(SupabaseGeographyRepository repo, String cityId) async =>
    (await repo.saveZone(
      Zone(id: '', cityId: cityId, name: 'منطقة', defaultDeliveryFee: 1000),
    )).valueOrNull!.id;
