import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Every paid placement a merchant buys, on any channel.
///
/// One collection and one document shape for four channels, because they share a
/// lifecycle: requested, approved, live between two dates, ended. Four collections would
/// be four admin queues and four expiry passes for one idea.
void main() {
  Promotion promotion({
    PromotionChannel channel = PromotionChannel.homeBanner,
    PromotionStatus status = PromotionStatus.active,
    PromotionRender render = PromotionRender.text,
    DateTime? startAt,
    DateTime? endAt,
    List<String> zoneIds = const [],
    String? mediaId,
    String? sectionKey,
    String? backgroundColor,
    String title = 'خصم النهارده',
    int priority = 0,
  }) =>
      Promotion(
        id: 'p1',
        cityId: 'edku',
        merchantId: 'm1',
        channel: channel,
        status: status,
        renderMode: render,
        backgroundColor: backgroundColor,
        title: title,
        body: 'كل الفراخ ١٥٪ أقل',
        mediaId: mediaId,
        sectionKey: sectionKey,
        zoneIds: zoneIds,
        startAt: startAt ?? DateTime(2026, 8, 1),
        endAt: endAt ?? DateTime(2026, 9, 1),
        priority: priority,
        requestedBy: 'owner1',
      );

  final now = DateTime(2026, 8, 24, 12);

  group('whether it is live', () {
    test('an approved run inside its dates is', () {
      expect(promotion().isLiveAt(now), isTrue);
    });

    // Approved is not live. A campaign somebody signed off for next week must not start
    // the moment it was approved.
    test('a run that has not started is not', () {
      expect(
        promotion(startAt: DateTime(2026, 9, 1), endAt: DateTime(2026, 9, 30))
            .isLiveAt(now),
        isFalse,
      );
    });

    test('a run that has finished is not', () {
      expect(
        promotion(startAt: DateTime(2026, 7, 1), endAt: DateTime(2026, 8, 1))
            .isLiveAt(now),
        isFalse,
      );
    });

    test('one still waiting for approval is not', () {
      expect(promotion(status: PromotionStatus.requested).isLiveAt(now), isFalse);
    });

    test('a rejected one never is', () {
      expect(promotion(status: PromotionStatus.rejected).isLiveAt(now), isFalse);
    });
  });

  group('who sees it', () {
    // No zones means everybody. A merchant who did not narrow their campaign meant the
    // whole city, not nobody — the opposite reading would silently waste what they paid.
    test('a campaign with no zones reaches the whole city', () {
      expect(promotion().reaches('z1'), isTrue);
      expect(promotion().reaches('z9'), isTrue);
    });

    test('a campaign naming zones reaches only those', () {
      final targeted = promotion(zoneIds: ['z1', 'z2']);

      expect(targeted.reaches('z1'), isTrue);
      expect(targeted.reaches('z9'), isFalse);
    });
  });

  group('how a banner is drawn', () {
    // The commercial point, not a visual one: it lets a merchant with no artwork and no
    // designer buy a banner the same day they ask for one, which is most of Edku.
    test('text alone needs no artwork', () {
      expect(promotion().canRender, isTrue);
    });

    // A banner promising an image and carrying none renders as a broken box on the home
    // screen of every customer in the city.
    test('an image mode with no image cannot be drawn', () {
      expect(promotion(render: PromotionRender.image).canRender, isFalse);
      expect(
        promotion(render: PromotionRender.image, mediaId: 'md1').canRender,
        isTrue,
      );
    });

    // A banner is a picture or it is words, and the ink on the words is computed from
    // the ground rather than stored — so there is no state that holds pale text on a
    // pale colour, and none that lays a headline over somebody's photograph.
    test('a colour is never needed to draw words', () {
      expect(promotion(title: 'خصم').canRender, isTrue);
      expect(
        promotion(title: 'خصم', backgroundColor: '#761812').canRender,
        isTrue,
      );
    });
  });

  group('which slot it belongs in', () {
    // Two ad slots on one screen — one near the top, one further down — are told apart
    // by the section key. A banner with none fits any slot.
    test('a banner without a slot fits anywhere', () {
      expect(promotion().belongsIn('top'), isTrue);
    });

    test('a banner naming a slot fits only that one', () {
      final pinned = promotion(sectionKey: 'top');

      expect(pinned.belongsIn('top'), isTrue);
      expect(pinned.belongsIn('bottom'), isFalse);
    });
  });

  group('serialization', () {
    test('survives a round trip', () {
      final restored = Promotion.fromJson(
        promotion(channel: PromotionChannel.boost, zoneIds: ['z1']).toJson(),
      );

      expect(restored.channel, PromotionChannel.boost);
      expect(restored.zoneIds, ['z1']);
      expect(restored.title, 'خصم النهارده');
    });

    // A channel added on the server before this build knew about it must not crash the
    // home screen of every customer in the city.
    test('an unknown channel falls back rather than throwing', () {
      final json = promotion().toJson()..['channel'] = 'skywriting';

      expect(Promotion.fromJson(json).channel, PromotionChannel.homeBanner);
    });

    test('an unknown status reads as requested, never as active', () {
      // Erring towards live would put an unapproved campaign in front of customers.
      final json = promotion().toJson()..['status'] = 'whatever';

      expect(Promotion.fromJson(json).status, PromotionStatus.requested);
    });
  });

  group('ranking a list of merchants', () {
    Merchant merchant(String id, {double rating = 0}) => Merchant(
          id: id,
          cityId: 'edku',
          type: MerchantType.restaurant,
          name: id,
          zoneId: 'z1',
          phone: '0100',
          status: MerchantStatus.approved,
          ratingAvg: rating,
        );

    test('a boosted merchant is lifted above the rest', () {
      final ranked = Boost.apply(
        [merchant('a'), merchant('b'), merchant('c')],
        boosted: {'c'},
      );

      expect(ranked.first.id, 'c');
    });

    // Boost lifts; it does not scramble. A merchant who paid for nothing should find
    // their list in the order it was in.
    test('the order of everyone else is untouched', () {
      final ranked = Boost.apply(
        [merchant('a'), merchant('b'), merchant('c')],
        boosted: {'c'},
      );

      expect(ranked.map((m) => m.id), ['c', 'a', 'b']);
    });

    test('several boosted merchants keep their order among themselves', () {
      final ranked = Boost.apply(
        [merchant('a'), merchant('b'), merchant('c')],
        boosted: {'a', 'c'},
      );

      expect(ranked.map((m) => m.id), ['a', 'c', 'b']);
    });

    test('nobody boosted changes nothing', () {
      final ranked = Boost.apply(
        [merchant('a'), merchant('b')],
        boosted: const {},
      );

      expect(ranked.map((m) => m.id), ['a', 'b']);
    });
  });
}
