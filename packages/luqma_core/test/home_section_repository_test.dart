import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Reading the home the owner arranged.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreHomeSectionRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreHomeSectionRepository(firestore);
  });

  Future<void> seed(
    String key, {
    String type = 'merchantList',
    int sortOrder = 0,
    bool isVisible = true,
    String cityId = 'edku',
    Map<String, dynamic> params = const {},
  }) {
    return firestore.collection('homeSections').doc(key).set({
      'key': key,
      'type': type,
      'titleAr': '',
      'sortOrder': sortOrder,
      'isVisible': isVisible,
      'cityId': cityId,
      'params': params,
    });
  }

  test('sections come back in the order the owner set', () async {
    await seed('c', sortOrder: 2);
    await seed('a', sortOrder: 0);
    await seed('b', sortOrder: 1);

    final sections = await repository.watchSections(cityId: 'edku').first;

    expect(sections.map((s) => s.key), ['a', 'b', 'c']);
  });

  // Hidden sections are still read: hiding is the app's decision to make, and the same
  // list feeds AdminApp's home builder, where a hidden section must remain visible to
  // the person who hid it.
  test('a hidden section is still returned, flagged as hidden', () async {
    await seed('a');
    await seed('hidden', isVisible: false, sortOrder: 1);

    final sections = await repository.watchSections(cityId: 'edku').first;

    expect(sections, hasLength(2));
    expect(sections.last.isVisible, isFalse);
  });

  test('another city’s home is not mixed in', () async {
    await seed('here');
    await seed('elsewhere', cityId: 'rosetta');

    final sections = await repository.watchSections(cityId: 'edku').first;

    expect(sections.map((s) => s.key), ['here']);
  });

  test('parameters survive the round trip', () async {
    await seed('slot', type: 'adSlot', params: {'maxAds': 3, 'rotationSeconds': 6});

    final sections = await repository.watchSections(cityId: 'edku').first;

    expect(sections.single.params['maxAds'], 3);
    expect(sections.single.params['rotationSeconds'], 6);
  });

  // A city with no home configured is a real state — a second city on its first day —
  // and it must read as "nothing arranged yet", not as a failure.
  test('a city with no sections yields an empty list, not an error', () async {
    final sections = await repository.watchSections(cityId: 'edku').first;
    expect(sections, isEmpty);
  });

  test('the fake applies the same city filter and ordering', () async {
    final fake = FakeHomeSectionRepository(seed: const [
      HomeSection(key: 'b', type: 'merchantList', sortOrder: 1, cityId: 'edku'),
      HomeSection(key: 'a', type: 'categoryChips', sortOrder: 0, cityId: 'edku'),
      HomeSection(key: 'x', type: 'merchantList', cityId: 'rosetta'),
    ]);

    final sections = await fake.watchSections(cityId: 'edku').first;

    expect(sections.map((s) => s.key), ['a', 'b']);
  });
}
