import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// What customers said, as the merchant reads it.
///
/// Private on purpose. The stars aggregate onto the merchant and are public; the words
/// stay between the customer, this merchant and the admin until the public-comments flag
/// is turned on. A merchant who reads honest criticism in private fixes it; one who
/// reads it in public argues with it.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreFeedbackRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreFeedbackRepository(firestore);
  });

  Future<void> seed({
    String id = 'o1',
    String merchantId = 'm1',
    int stars = 5,
    String? comment,
    DateTime? at,
  }) async {
    await firestore.collection('ratings').doc(id).set({
      'orderId': id,
      'customerUid': 'u1',
      'merchantId': merchantId,
      'stars': stars,
      'comment': ?comment,
      'createdAt': at ?? DateTime(2026, 8, 20),
    });
  }

  test('only this merchant\'s', () async {
    await seed(id: 'mine', merchantId: 'm1', comment: 'ممتاز');
    await seed(id: 'theirs', merchantId: 'm2', comment: 'وحش');

    final feedback = await repository.watchFeedback('m1').first;

    expect(feedback.map((f) => f.orderId), ['mine']);
  });

  test('the stars and the words both come through', () async {
    await seed(stars: 2, comment: 'الأكل وصل بارد');

    final one = (await repository.watchFeedback('m1').first).single;

    expect(one.stars, 2);
    expect(one.comment, 'الأكل وصل بارد');
  });

  // Most people rate without typing. Dropping those would make the list look like
  // nothing but complaints, because complaints are what people write.
  test('a rating with no comment is still feedback', () async {
    await seed(stars: 5);

    final one = (await repository.watchFeedback('m1').first).single;

    expect(one.stars, 5);
    expect(one.comment, isNull);
  });

  test('newest first', () async {
    await seed(id: 'old', at: DateTime(2026, 8, 1));
    await seed(id: 'new', at: DateTime(2026, 8, 20));

    final feedback = await repository.watchFeedback('m1').first;

    expect(feedback.map((f) => f.orderId), ['new', 'old']);
  });

  group('the fake', () {
    test('gives back what it was seeded with', () async {
      final fake = FakeFeedbackRepository(seed: const [
        CustomerRating(orderId: 'o1', merchantId: 'm1', stars: 4, comment: 'حلو'),
      ]);

      expect((await fake.watchFeedback('m1').first).single.stars, 4);
    });

    test('reports the failure it was given', () async {
      final fake = FakeFeedbackRepository(failure: const OfflineFailure());

      expect(fake.watchFeedback('m1').first, throwsA(isA<OfflineFailure>()));
    });
  });
}
