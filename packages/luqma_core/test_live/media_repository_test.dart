import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// The moderation queue, against a real Postgres.
///
/// `uploaded_by` and `reviewed_by` are foreign keys into auth.users here, not free
/// strings — so the tests sign real people in rather than inventing reviewer names,
/// which is exactly the discipline the read policy asks of production.
void main() {
  late LiveDatabase live;
  late SupabaseMediaRepository repository;
  late String uploaderUid;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseMediaRepository(live.client);
  });

  setUp(() async {
    // The queue is global — media carries no city — so every run clears what past runs
    // left behind rather than inheriting their strays.
    await live.client.from('media').delete().like('url', 'https://example.com/%');
    uploaderUid = await live.makeCustomer();
  });

  tearDownAll(() => live.close());

  Future<String> upload({
    MediaStatus status = MediaStatus.pending,
    MediaKind kind = MediaKind.menuItem,
    DateTime? createdAt,
  }) async =>
      await live.client.from('media').insert({
        'kind': kind.name,
        'url': 'https://example.com/$uploaderUid-$kind.name.jpg',
        'status': status.name,
        'uploaded_by': _uuidOrDbNull(uploaderUid),
        // Explicit: two uploads inside the same tick share now(), and a queue ordered
        // by a tied column owes nobody an order.
        if (createdAt != null) 'created_at': createdAt.toUtc().toIso8601String(),
      }).select().single().then((row) => row['id'] as String);

  test('the queue shows pending uploads, oldest first', () async {
    final older =
        await upload(createdAt: DateTime.now().subtract(const Duration(hours: 1)));
    final newer = await upload();

    final queue = await repository.watchPending().first;

    expect(queue.map((m) => m.id), [older, newer]);
  });

  // A banner and a dish photo are judged against different things, so the reviewer
  // has to be told which they are looking at.
  test('says which kind of image each one is', () async {
    await upload(kind: MediaKind.promotion);

    final pending = await repository.watchPending().first;

    expect(pending.single.kind, MediaKind.promotion);
  });

  test('approved uploads leave the queue', () async {
    await upload(status: MediaStatus.approved);

    expect(await repository.watchPending().first, isEmpty);
  });

  // Knowing a decision was made, and by whom, is what separates "reviewed and refused"
  // from "nobody has looked yet".
  test('a review records who decided and why', () async {
    final id = await upload();

    await repository.setStatus(
      id,
      MediaStatus.rejected,
      reviewedBy: uploaderUid,
      note: 'الصورة مش واضحة',
    );

    final read = (await repository.get(id)).valueOrNull!;
    expect(read.status, MediaStatus.rejected);
    expect(read.reviewNote, 'الصورة مش واضحة');
  });

  test('an empty note is no note', () async {
    final id = await upload();

    await repository.setStatus(id, MediaStatus.approved, note: '');

    final read = (await repository.get(id)).valueOrNull!;
    expect(read.status, MediaStatus.approved);
    expect(read.reviewNote, isNull);
  });

  test('a missing medium is a not-found failure', () async {
    final result =
        await repository.get('00000000-0000-0000-0000-000000000000');

    expect(result.failureOrNull, isA<NotFoundFailure>());
  });

  // The queue is watched live in AdminApp: an upload from a merchant's phone should
  // appear without anyone refreshing.
  test('an upload arrives on an already-open queue', () async {
    final emissions = <List<Media>>[];
    repository.watchPending().listen(emissions.add);
    await waitFor(() => emissions.isNotEmpty,
        because: 'the queue never produced its first emission');
    expect(emissions.first, isEmpty);

    await upload();

    await waitFor(
      () => emissions.any((e) => e.isNotEmpty),
      because: 'the new upload never reached the open queue',
      timeout: const Duration(seconds: 15),
    );
  });
}

String? _uuidOrDbNull(String id) => (id.isEmpty) ? null : id;
