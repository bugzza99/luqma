import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// The customer's home, watched against a real Postgres with realtime on.
///
/// The port of `test/home_section_repository_test.dart`, plus what only a real socket
/// can prove: that a change made after subscribing arrives on its own, and that what
/// happened while the socket was down is backfilled on reconnect — the failure mode
/// Firestore never had and Supabase always does.
void main() {
  late LiveDatabase live;
  late SupabaseHomeSectionRepository repository;
  late String cityId;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseHomeSectionRepository(live.client);
  });

  setUp(() async {
    cityId = await live.makeCity();
  });

  tearDown(() => live.dropCity(cityId));
  tearDownAll(() => live.close());

  HomeSection section(
    String key, {
    String type = 'merchantList',
    int sortOrder = 0,
    bool isVisible = true,
  }) =>
      HomeSection(
        key: key,
        type: type,
        sortOrder: sortOrder,
        isVisible: isVisible,
        cityId: cityId,
      );

  /// Collects a stream's emissions so tests can wait for the one they care about.
  Future<List<List<HomeSection>>> collect(Stream<List<HomeSection>> stream) async {
    final emissions = <List<HomeSection>>[];
    final sub = stream.listen(emissions.add);
    await waitFor(() => emissions.isNotEmpty,
        because: 'the watch never produced its first emission');
    return emissions;
  }

  test('sections come back in the order the owner set', () async {
    await repository.save(section('c', sortOrder: 2));
    await repository.save(section('a', sortOrder: 0));
    await repository.save(section('b', sortOrder: 1));

    final sections =
        await repository.watchSections(cityId: cityId).first;

    expect(sections.map((s) => s.key), ['a', 'b', 'c']);
  });

  // Hidden sections are still read: hiding is the app's decision to make, and the same
  // list feeds AdminApp's home builder, where a hidden section must remain visible to
  // the person who hid it.
  test('a hidden section is still returned, flagged as hidden', () async {
    await repository.save(section('a'));
    await repository.save(section('hidden', isVisible: false, sortOrder: 1));

    final sections = await repository.watchSections(cityId: cityId).first;

    expect(sections, hasLength(2));
    expect(sections.last.isVisible, isFalse);
  });

  test('another city’s home is not mixed in', () async {
    final other = await live.makeCity();
    await repository.save(section('here'));
    await repository.save(HomeSection(
      key: 'elsewhere',
      type: 'merchantList',
      cityId: other,
    ));

    final sections = await repository.watchSections(cityId: cityId).first;

    expect(sections.map((s) => s.key), ['here']);
  });

  // The registry in the app reads these; a param lost or renamed in the mapper draws
  // an ad slot with no idea how many ads it holds.
  test('parameters survive the round trip', () async {
    await repository.save(HomeSection(
      key: 'slot',
      type: 'adSlot',
      cityId: cityId,
      params: {'maxAds': 3, 'rotationSeconds': 6},
    ));

    final sections = await repository.watchSections(cityId: cityId).first;

    expect(sections.single.params['maxAds'], 3);
    expect(sections.single.params['rotationSeconds'], 6);
  });

  // A city with no home configured is a real state — a second city on its first day —
  // and it must read as "nothing arranged yet", not as a failure.
  test('a city with no sections yields an empty list, not an error', () async {
    final sections = await repository.watchSections(cityId: cityId).first;
    expect(sections, isEmpty);
  });

  group('live changes', () {
    // A section hidden in AdminApp must disappear from phones already open — that is
    // most of what "without shipping an update" means here.
    test('a section hidden after subscribing arrives changed on its own', () async {
      await repository.save(section('a'));

      final emissions =
          await collect(repository.watchSections(cityId: cityId));
      expect(emissions.first.single.isVisible, isTrue);

      await repository.setVisible('a', false);

      // The watch re-emits several times around start-up (fetch, subscribe, the
      // replication-grace sweep), so assertions read *any* emission for what changed,
      // never the count or the order of them.
      await waitFor(
        () => emissions.any((e) => e.any((s) => s.key == 'a' && !s.isVisible)),
        because: 'hiding a section never reached the open watch',
        timeout: const Duration(seconds: 15),
      );
    });

    test('a section added after subscribing arrives on its own', () async {
      await repository.save(section('a'));

      final emissions =
          await collect(repository.watchSections(cityId: cityId));

      await repository.save(section('b', sortOrder: 1));

      await waitFor(
        () => emissions.any((e) => e.any((s) => s.key == 'b')),
        because: 'the new section never reached the open watch',
        timeout: const Duration(seconds: 15),
      );
    });

    // The row that left the result is the hard case for hand-merged patches — and why
    // this helper refetches rather than merges.
    test('a deletion arrives too', () async {
      await repository.save(section('a'));
      await repository.save(section('b', sortOrder: 1));

      final emissions =
          await collect(repository.watchSections(cityId: cityId));
      expect(emissions.first, hasLength(2));

      await live.client.from('home_sections').delete().eq('key', 'b');

      await waitFor(
        () => emissions.any((e) => e.every((s) => s.key != 'b')),
        because: 'the deleted section never left the open watch',
        timeout: const Duration(seconds: 15),
      );
    });

    test('reordering lands as one statement', () async {
      await repository.save(section('c', sortOrder: 0));
      await repository.save(section('a', sortOrder: 1));
      await repository.save(section('b', sortOrder: 2));

      final emissions =
          await collect(repository.watchSections(cityId: cityId));

      final reordered = await repository.reorder(['c', 'b', 'a']);
      expect(reordered.failureOrNull, isNull,
          reason: 'the reorder call itself failed');

      await waitFor(
        () => emissions.any((e) => e.map((s) => s.key).join() == 'cba'),
        because: 'the reorder never reached the open watch',
        timeout: const Duration(seconds: 15),
      );
    });

    // Firestore backfilled what a listener missed while offline. Supabase does not, so
    // the helper refetches on every fresh subscription — this is the test the plan
    // demanded by name: a merchant whose phone slept through a change still sees it.
    test('what happened while the socket was down is backfilled', () async {
      await repository.save(section('a'));

      final emissions =
          await collect(repository.watchSections(cityId: cityId));
      expect(emissions.first.map((s) => s.key), ['a']);

      await live.client.realtime.disconnect();
      // Let the socket actually die before making the change nobody should see.
      await Future<void>.delayed(const Duration(seconds: 2));
      await repository.save(section('b', sortOrder: 1));

      // Sanity: while disconnected, the change must not have arrived.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(emissions.last.where((s) => s.key == 'b'), isEmpty);

      // ignore: invalid_use_of_internal_member
      await live.client.realtime.connect();

      await waitFor(
        () => emissions.any((e) => e.any((s) => s.key == 'b')),
        because: 'the reconnect never backfilled what was missed',
        timeout: const Duration(seconds: 20),
      );
    });
  });

  test('the fake applies the same city filter and ordering', () async {
    final fake = FakeHomeSectionRepository(seed: [
      HomeSection(key: 'b', type: 'merchantList', sortOrder: 1, cityId: cityId),
      HomeSection(key: 'a', type: 'categoryChips', sortOrder: 0, cityId: cityId),
      HomeSection(key: 'x', type: 'merchantList', cityId: 'rosetta'),
    ]);

    final sections = await fake.watchSections(cityId: cityId).first;

    expect(sections.map((s) => s.key), ['a', 'b']);
  });
}
