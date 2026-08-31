// freezed forwards `@JsonKey` from a constructor parameter onto the generated field,
// which is exactly what `unknownEnumValue` needs here — but the analyzer only knows the
// annotation's declared targets and reports the forwarding as invalid. Scoped to this
// file rather than turned off across the project.
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'daily_meal.freezed.dart';
part 'daily_meal.g.dart';

/// How a reserved portion reaches the customer.
enum DeliveryOption {
  /// They come and collect it. The default, and the simplest thing for somebody cooking
  /// at home with no courier of their own.
  pickup,

  /// Luqma's courier takes it.
  platformCourier,

  /// The two of them arrange it between themselves. It happens here, and pretending it
  /// does not would only mean it happens outside the app where nobody can help.
  sellerArrangement,
}

enum DailyMealStatus {
  /// Written but not announced. Nothing sees it.
  draft,
  published,

  /// Taken down early — the cook ran out of an ingredient, or is closing up. Distinct
  /// from sold out, which is a count reaching zero and is never stored.
  closed,
}

/// One home kitchen's meal for one day.
///
/// A different unit from a menu item, and the difference is the whole of what makes home
/// kitchens work. A menu item is a promise to cook on demand; this is a count of portions
/// somebody has already cooked, and when they are gone they are gone. That is why it
/// carries a quantity, a day and a collection window, and why reserving one is a
/// transaction rather than a write.
@freezed
abstract class DailyMeal with _$DailyMeal {
  const factory DailyMeal({
    required String id,
    required String merchantId,
    required String cityId,
    required String name,
    String? description,
    String? mediaId,

    /// The approved picture's address, resolved by the query that read this meal.
    ///
    /// A cook's photograph of today's food is the whole pitch for a home kitchen, and
    /// until the query embedded it every meal in أكل بيتي drew a tinted placeholder.
    String? imageUrl,

    /// Piastres.
    required int price,

    /// The calendar day, as `yyyy-MM-dd`.
    ///
    /// A day key rather than a timestamp because "today's meals" is an equality query,
    /// and an equality query against a timestamp matches one microsecond rather than a
    /// day. It also reads correctly in the console, sorts as a string, and cannot drift
    /// by a few hours if a device's clock or zone is wrong.
    required String date,
    required int totalQty,

    /// Decremented in a transaction by the server, never written by a client. Two people
    /// tapping the last portion at the same moment is the exact thing this collection
    /// exists to get right.
    required int remainingQty,

    /// Minutes from midnight, like `OpeningWindow` — plain integers that sort without
    /// parsing and survive a timezone change on the device.
    required int pickupWindowStart,
    required int pickupWindowEnd,
    @Default(DeliveryOption.pickup)
    @JsonKey(unknownEnumValue: DeliveryOption.pickup)
    DeliveryOption deliveryOption,
    @Default(DailyMealStatus.draft)
    @JsonKey(unknownEnumValue: DailyMealStatus.draft)
    DailyMealStatus status,
  }) = _DailyMeal;

  const DailyMeal._();

  factory DailyMeal.fromJson(Map<String, dynamic> json) => _$DailyMealFromJson(json);

  /// The day key for [when]. The one place this format is decided.
  static String dayKeyOf(DateTime when) {
    final month = when.month.toString().padLeft(2, '0');
    final day = when.day.toString().padLeft(2, '0');
    return '${when.year}-$month-$day';
  }

  bool isFor(DateTime when) => date == dayKeyOf(when);

  /// Derived from the count and never stored, so the two can never disagree.
  ///
  /// Below zero counts as sold out too: a negative number means two people got the last
  /// portion, and a screen reading "-1 left" is worse than one reading "sold out".
  bool get isSoldOut => remainingQty <= 0;

  int get remainingOrZero => remainingQty < 0 ? 0 : remainingQty;

  /// How much is left, between 0 and 1. Zero when the meal has no portions at all —
  /// that is a bug upstream, and dividing by it would be a crash on the home screen.
  double get fractionLeft =>
      totalQty <= 0 ? 0 : (remainingOrZero / totalQty).clamp(0, 1).toDouble();

  /// Whether somebody can still reserve a portion.
  ///
  /// The collection window closing stops orders, not just collection: reserving at half
  /// past three for a window that shuts at four is somebody who will not make it, and a
  /// portion held for them is a portion the cook could have sold.
  bool canBeOrderedAt(DateTime now) {
    if (status != DailyMealStatus.published) return false;
    if (isSoldOut) return false;
    if (!isFor(now)) return false;
    return now.hour * 60 + now.minute < pickupWindowEnd;
  }
}
