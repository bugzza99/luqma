import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreGeographyRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreGeographyRepository(firestore);
  });

  group('zones', () {
    test('a new zone gets an id and comes back', () async {
      final saved = await repository.saveZone(
        const Zone(id: '', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
      );

      expect(saved.valueOrNull?.id, isNotEmpty);
      final zones = await repository.zones(cityId: 'edku');
      expect(zones.valueOrNull?.single.name, 'المعمورة');
    });

    test('editing a zone does not create a second one', () async {
      final created = (await repository.saveZone(
        const Zone(id: '', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
      )).valueOrNull!;

      await repository.saveZone(created.copyWith(defaultDeliveryFee: 1200));

      final zones = (await repository.zones(cityId: 'edku')).valueOrNull!;
      expect(zones, hasLength(1));
      expect(zones.single.defaultDeliveryFee, 1200);
    });

    // A zone with orders against it cannot simply vanish, or those addresses lose the one
    // field a courier reads first. Deactivating keeps history readable.
    test('a zone is deactivated rather than deleted', () async {
      final created = (await repository.saveZone(
        const Zone(id: '', cityId: 'edku', name: 'الشط', defaultDeliveryFee: 1500),
      )).valueOrNull!;

      await repository.setZoneActive(created.id, false);

      expect((await repository.zones(cityId: 'edku')).valueOrNull, isEmpty);
      expect(
        (await repository.zones(cityId: 'edku', includeInactive: true)).valueOrNull,
        hasLength(1),
      );
    });
  });

  group('landmarks', () {
    test('a new landmark comes back in its zone', () async {
      await repository.saveLandmark(
        const Landmark(id: '', cityId: 'edku', zoneId: 'z1', name: 'صيدلية النور'),
      );

      final landmarks = (await repository.landmarks(cityId: 'edku')).valueOrNull!;
      expect(landmarks.single.name, 'صيدلية النور');
      expect(landmarks.single.zoneId, 'z1');
    });

    // Unlike a zone, a landmark is only ever a hint on an address — the address keeps the
    // name it was saved with, so removing a wrong one costs nothing.
    test('a landmark can be deleted outright', () async {
      final created = (await repository.saveLandmark(
        const Landmark(id: '', cityId: 'edku', zoneId: 'z1', name: 'خطأ'),
      )).valueOrNull!;

      await repository.deleteLandmark(created.id);

      expect((await repository.landmarks(cityId: 'edku')).valueOrNull, isEmpty);
    });

    test('editing a landmark does not create a second one', () async {
      final created = (await repository.saveLandmark(
        const Landmark(id: '', cityId: 'edku', zoneId: 'z1', name: 'صيدليه النور'),
      )).valueOrNull!;

      await repository.saveLandmark(created.copyWith(name: 'صيدلية النور'));

      final landmarks = (await repository.landmarks(cityId: 'edku')).valueOrNull!;
      expect(landmarks, hasLength(1));
      expect(landmarks.single.name, 'صيدلية النور');
    });
  });

  group('the notes customers typed', () {
    Future<void> order(String note, {String zoneId = 'z1'}) {
      return firestore.collection('orders').add({
        'cityId': 'edku',
        'zoneId': zoneId,
        'address': {'zoneId': zoneId, 'landmarkNote': note},
      });
    }

    test('are read off recent orders', () async {
      await order('صيدلية النور');
      await order('كافيه الركن');

      final notes = (await repository.landmarkNotes(cityId: 'edku')).valueOrNull!;

      expect(notes.map((n) => n.text), containsAll(['صيدلية النور', 'كافيه الركن']));
    });

    test('carry the zone the order was going to', () async {
      await order('الفرن', zoneId: 'z7');

      final notes = (await repository.landmarkNotes(cityId: 'edku')).valueOrNull!;

      expect(notes.single.zoneId, 'z7');
    });

    // Most orders pick a landmark from the list; only the ones that did not are of any
    // use here.
    test('an order that chose a listed landmark contributes nothing', () async {
      await firestore.collection('orders').add({
        'cityId': 'edku',
        'zoneId': 'z1',
        'address': {'zoneId': 'z1', 'landmarkId': 'l1', 'landmarkName': 'مسجد الفتح'},
      });

      expect((await repository.landmarkNotes(cityId: 'edku')).valueOrNull, isEmpty);
    });
  });
}
