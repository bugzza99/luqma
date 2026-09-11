import 'package:luqma_core/luqma_core.dart';

/// The merchant screen's reading of "is this shop taking orders right now", and the
/// words for it.
///
/// [Merchant.acceptsOrdersAt] already folds status, the pause and a spent prepaid wallet
/// into one yes/no. The customer's own screen needs the "no" split in two, because the
/// two are not the same conversation: a shop that is **shut** is one to come back to
/// tomorrow, and a shop that is **busy** — the owner tapped that during a rush — is one
/// to try again in twenty minutes. The artboard draws only the open state; these three
/// all have to read correctly.
enum MerchantOpenState { open, paused, closed }

/// Which of the three [merchant] is in at [now].
///
/// The pause only reads as "busy" while a window is genuinely open behind it. Outside
/// trading hours a stale `pausedUntil` is just a closed shop, and saying "busy" there
/// would promise a reopening that the schedule does not.
MerchantOpenState merchantOpenState(Merchant merchant, DateTime now) {
  if (merchant.acceptsOrdersAt(now)) return MerchantOpenState.open;

  final pausedNow =
      merchant.pausedUntil != null && now.isBefore(merchant.pausedUntil!);
  final withinHours = merchant.status == MerchantStatus.approved &&
      merchant.openingHours.any((window) => window.contains(now));

  return pausedNow && withinHours
      ? MerchantOpenState.paused
      : MerchantOpenState.closed;
}

/// The minute-of-day the window covering [now] closes at, or null when none covers it or
/// the window never actually closes (a 24-hour window is stored as `0..1440`, and
/// "مفتوح لحد ١٢ ص" for a shop that does not shut is a time nobody needs).
int? closingMinuteAt(Merchant merchant, DateTime now) {
  for (final window in merchant.openingHours) {
    if (window.contains(now)) {
      // A shop that never shuts and a shop that shuts at midnight both end at minute
      // 1440, and taking that modulo 1440 collapses them into the same 0 — which hid the
      // closing time from every kitchen that closes at twelve. What separates them is the
      // *start*: only a window covering the whole day never closes.
      final neverCloses = window.openMinute <= 0 && window.closeMinute >= 1440;
      if (neverCloses) return null;
      // Midnight is minute 0 of the next day, and reads as «١٢ ص» — which is the truth
      // for a shop closing at twelve, and was the reason for the modulo in the first
      // place.
      return window.closeMinute % 1440;
    }
  }
  return null;
}

/// A minute-of-day as a 12-hour Egyptian clock label: `1 ص`, `11:30 م`.
///
/// On-the-hour times drop the `:00`, matching the artboard's «مفتوح لحد 1 ص». Western
/// digits and the ص/م marker only, for the same reason [formatClockTime] gives: `intl`'s
/// `ar` locale would bring Arabic-Indic digits this app does not use.
String formatDayMinute(int minuteOfDay, LuqmaStrings strings) =>
    luqmaClockMinute(minuteOfDay, strings);
