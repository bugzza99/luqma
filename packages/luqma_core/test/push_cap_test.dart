import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The weekly push cap, answered by the server and mirrored by the fake.
///
/// The cap is on the *city* — what is being rationed is a customer's patience. The
/// repository seam exists so this can be argued with against the fake; the PGlite suite
/// argues the server function itself (`push_slot_available`).
void main() {
  Promotion push({
    required String id,
    PromotionStatus status = PromotionStatus.approved,
    DateTime? startAt,
  }) =>
      Promotion(
        id: id,
        cityId: 'edku',
        merchantId: 'm1',
        channel: PromotionChannel.push,
        status: status,
        renderMode: PromotionRender.text,
        title: 'خصم النهارده',
        body: 'كل الفراخ أقل',
        startAt: startAt ?? DateTime.now().subtract(const Duration(days: 1)),
        endAt: DateTime.now().add(const Duration(days: 1)),
        requestedBy: 'owner1',
      );

  Future<ProviderContainer> containerWith(FakePromotionRepository repo) async {
    // One push a week: every boundary below is one seed away.
    final service = RemoteConfigService(
      FakeConfigFetcher({'marketing_push_per_week': 1}),
    );
    await service.refresh();

    final container = ProviderContainer(
      overrides: [
        promotionRepositoryProvider.overrideWithValue(repo),
        remoteConfigServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a city with nothing sent has a slot', () async {
    final container = await containerWith(FakePromotionRepository());
    expect(await container.read(pushSlotAvailableProvider.future), isTrue);
  });

  test('an approved push that has started fills the slot', () async {
    final container = await containerWith(
      FakePromotionRepository(seed: [push(id: 'a')]),
    );
    expect(await container.read(pushSlotAvailableProvider.future), isFalse);
  });

  test('an ended push fills the slot', () async {
    final container = await containerWith(
      FakePromotionRepository(seed: [push(id: 'a', status: PromotionStatus.ended)]),
    );
    expect(await container.read(pushSlotAvailableProvider.future), isFalse);
  });

  test('an approved push that has not started does not fill the slot', () async {
    final container = await containerWith(
      FakePromotionRepository(seed: [
        push(
          id: 'a',
          startAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ]),
    );
    expect(await container.read(pushSlotAvailableProvider.future), isTrue);
  });
}
