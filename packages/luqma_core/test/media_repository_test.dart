import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The moderation queue.
///
/// Photography is what makes a food app read as premium, and one unreviewed photo of a
/// plate under a neon strip undoes a lot of it. This is the gate — and it only works if
/// it has exactly one door, which is why every image in the product is a `media`
/// document and there is no other path.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreMediaRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreMediaRepository(firestore);
  });

  Future<String> upload({
    MediaStatus status = MediaStatus.pending,
    MediaKind kind = MediaKind.menuItem,
  }) async {
    final doc = await firestore.collection('media').add({
      'kind': kind.name,
      'status': status.name,
      'url': 'https://example.test/a.webp',
      'thumbUrl': 'https://example.test/a-thumb.webp',
      'uploadedBy': 'u1',
      'width': 1200,
      'height': 900,
    });
    return doc.id;
  }

  group('the queue', () {
    test('holds what is waiting for review', () async {
      await upload();
      await upload();

      final pending = await repository.watchPending().first;

      expect(pending, hasLength(2));
    });

    test('leaves out what has already been decided', () async {
      await upload();
      await upload(status: MediaStatus.approved);
      await upload(status: MediaStatus.rejected);

      final pending = await repository.watchPending().first;

      expect(pending.single.status, MediaStatus.pending);
    });

    test('says which kind of image each one is', () async {
      await upload(kind: MediaKind.promotion);

      final pending = await repository.watchPending().first;

      // A banner and a dish photo are judged against different things, so the reviewer
      // has to be told which they are looking at.
      expect(pending.single.kind, MediaKind.promotion);
    });
  });

  group('deciding', () {
    test('approving makes an image visible', () async {
      final id = await upload();

      await repository.setStatus(id, MediaStatus.approved);

      expect(await repository.watchPending().first, isEmpty);
      final media = (await repository.get(id)).valueOrNull!;
      expect(media.status, MediaStatus.approved);
    });

    test('rejecting records who decided and why', () async {
      final id = await upload();

      await repository.setStatus(
        id,
        MediaStatus.rejected,
        reviewedBy: 'admin1',
        note: 'الصورة مش واضحة',
      );

      final media = (await repository.get(id)).valueOrNull!;
      expect(media.status, MediaStatus.rejected);
      expect(media.reviewedBy, 'admin1');
      expect(media.reviewNote, 'الصورة مش واضحة');
    });

    // A merchant who is told nothing simply uploads the same photo again.
    test('a rejection without a reason is still recorded as reviewed', () async {
      final id = await upload();

      await repository.setStatus(id, MediaStatus.rejected, reviewedBy: 'admin1');

      final media = (await repository.get(id)).valueOrNull!;
      expect(media.reviewedBy, 'admin1');
    });
  });
}
