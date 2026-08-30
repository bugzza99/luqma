// freezed forwards `@JsonKey` from a constructor parameter onto the generated field,
// which is what `unknownEnumValue` needs. Scoped to this file.
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'converters.dart';
import 'merchant.dart';

part 'promotion.freezed.dart';
part 'promotion.g.dart';

/// Where a paid placement appears.
enum PromotionChannel {
  /// A banner in an `adSlot` section on the customer's home.
  homeBanner,

  /// The same, in a slot attached to one category.
  categoryBanner,

  /// A lift in the merchant lists. No artwork, nothing to design.
  boost,

  /// A marketing notification. The only channel that reaches somebody who is not
  /// looking at the app, which is why it is the one an admin scrutinises hardest.
  push,
}

/// The one lifecycle all four channels share, which is why they share a collection.
enum PromotionStatus {
  /// A merchant has asked. Nothing is live and nothing has been paid.
  requested,

  /// Signed off, but not necessarily running — `startAt` decides that.
  approved,
  active,
  rejected,
  ended,
}

/// How a banner is drawn.
///
/// The commercial decision, not a visual one: `text` is what lets a merchant with no
/// artwork and no designer buy a banner the same day they ask for one, which is most of
/// Edku. Without it, selling banners would mean first finding every merchant a designer.
enum PromotionRender {
  /// A colour, a title and a body. No artwork needed.
  ///
  /// The commercial half of the decision: this is what lets a merchant with no designer
  /// buy a banner the same day they ask for one, which is most of Edku.
  text,

  /// The artwork, whole, and nothing written over it.
  image,
}

/// One paid placement.
///
/// Four channels, one document shape, because they share a lifecycle: requested,
/// approved, live between two dates, ended. Four collections would mean four admin
/// queues, four expiry passes and four sets of rules for one idea.
@freezed
abstract class Promotion with _$Promotion {
  const factory Promotion({
    required String id,
    required String cityId,
    required String merchantId,
    @JsonKey(unknownEnumValue: PromotionChannel.homeBanner)
    required PromotionChannel channel,

    /// Anything this build does not recognise reads as [PromotionStatus.requested].
    /// Erring towards live would put an unapproved campaign in front of customers.
    @Default(PromotionStatus.requested)
    @JsonKey(unknownEnumValue: PromotionStatus.requested)
    PromotionStatus status,
    @Default(PromotionRender.text)
    @JsonKey(unknownEnumValue: PromotionRender.text)
    PromotionRender renderMode,

    /// The ground the words sit on, as `#RRGGBB`. Null is the brand gradient.
    ///
    /// Only a text banner has one — a picture brings its own. The text colour is not
    /// stored beside it on purpose: see [PromotionPalette.inkOn], which computes it, so
    /// there is no way to save a pale headline onto a pale ground.
    String? backgroundColor,

    @Default('') String title,
    @Default('') String body,
    String? mediaId,

    /// The url of [mediaId], once it has been resolved and approved.
    ///
    /// Not a column: the query embeds `media(url, status)` and this is what comes back.
    /// It is null both when there is no picture and when the one there is has not been
    /// approved yet — an unapproved image must never reach a customer's home screen,
    /// and that rule belongs here rather than in whichever screen happens to draw it.
    @JsonKey(includeToJson: false) String? imageUrl,

    /// Which `adSlot` section this belongs in, or null for any of them.
    String? sectionKey,

    /// Which category, for a `categoryBanner`.
    String? categoryId,

    /// Zones this reaches. **Empty means the whole city** — a merchant who did not
    /// narrow their campaign meant everybody, not nobody, and the opposite reading
    /// would silently waste what they paid for.
    @Default(<String>[]) List<String> zoneIds,
    @RequiredTimestampConverter() required DateTime startAt,
    @RequiredTimestampConverter() required DateTime endAt,

    /// Higher wins a contested slot. Set by the admin, not bought directly.
    @Default(0) int priority,

    /// Piastres agreed for this placement.
    @Default(0) int price,
    required String requestedBy,
    String? approvedBy,
    String? rejectionReason,
    @Default(0) int impressions,
    @Default(0) int clicks,
  }) = _Promotion;

  const Promotion._();

  factory Promotion.fromJson(Map<String, dynamic> json) => _$PromotionFromJson(json);

  /// Whether this should be on screen right now.
  ///
  /// Approved is not live: a campaign signed off today for next week must not start the
  /// moment somebody approved it.
  bool isLiveAt(DateTime now) {
    if (status != PromotionStatus.active && status != PromotionStatus.approved) {
      return false;
    }
    return !now.isBefore(startAt) && now.isBefore(endAt);
  }

  /// Whether the merchant who asked for this may still correct it.
  ///
  /// The same two conditions `merchant_edits_unstarted_promotion` enforces, so a screen
  /// cannot offer a button the database will refuse. A rejected or finished placement is
  /// not a draft, and a running one is in front of customers — editing it would either
  /// change what the city sees without review or take a live campaign dark mid-flight.
  bool isEditableAt(DateTime now) =>
      (status == PromotionStatus.requested ||
          status == PromotionStatus.approved) &&
      startAt.isAfter(now);

  bool reaches(String zoneId) => zoneIds.isEmpty || zoneIds.contains(zoneId);

  bool belongsIn(String sectionKey) =>
      this.sectionKey == null || this.sectionKey == sectionKey;

  /// Whether there is enough here to draw.
  ///
  /// A banner promising an image and carrying none renders as a broken box on the home
  /// screen of every customer in the city, so it simply does not render at all.
  bool get canRender {
    if (renderMode == PromotionRender.text) return title.isNotEmpty;
    return mediaId != null && mediaId!.isNotEmpty;
  }
}

/// Lifting merchants who paid for it.
abstract final class Boost {
  const Boost._();

  /// Puts [boosted] at the front, leaving everyone else exactly as they were.
  ///
  /// A lift, not a reshuffle. A merchant who bought nothing should find the list in the
  /// order they expect — boost is the only thing that moved, and it moved one way.
  static List<Merchant> apply(
    List<Merchant> merchants, {
    required Set<String> boosted,
  }) {
    if (boosted.isEmpty) return merchants;

    final lifted = <Merchant>[];
    final rest = <Merchant>[];
    for (final merchant in merchants) {
      (boosted.contains(merchant.id) ? lifted : rest).add(merchant);
    }
    return [...lifted, ...rest];
  }
}
