import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The platform's own push names no shop; every other channel must (20261101330000).
///
/// The fake answers as the server's check does, so a screen that offers a shopless banner
/// fails its test here rather than on the first real attempt.
void main() {
  Promotion draft(PromotionChannel channel) => Promotion(
        id: '',
        cityId: 'edku',
        channel: channel,
        renderMode: PromotionRender.text,
        title: 'أهلًا بيكم في لقمة',
        startAt: DateTime(2026, 9, 24),
        endAt: DateTime(2026, 9, 30),
        requestedBy: 'a1',
      );

  test('a push may be the platform own', () async {
    final repo = FakePromotionRepository();
    final made = await repo.createApproved(draft(PromotionChannel.push), approvedBy: 'a1');
    expect(made.valueOrNull?.merchantId, isNull);
  });

  test('a banner with no shop is refused, as the server refuses it', () async {
    final repo = FakePromotionRepository();
    final made =
        await repo.createApproved(draft(PromotionChannel.homeBanner), approvedBy: 'a1');
    expect(made.failureOrNull, isA<ValidationFailure>());
  });
}
