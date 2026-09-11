import 'package:luqma_core/luqma_core.dart';

/// Presentation helpers for the orders list's timestamps.
///
/// They live here, not in `luqma_core`, because they are this one screen's formatting
/// rules rather than a shared contract — and they take plain [DateTime]s rather than a
/// clock provider so the day bucketing can be tested by moving a date instead of pumping
/// a widget.
///
/// `intl`'s `ar` locale is deliberately not used: it renders the MSA weekday names
/// (الأربعاء) and Arabic-Indic digits, and this app is colloquial Egyptian with Western
/// numerals throughout. [LuqmaStrings] supplies the words; the digits and punctuation are
/// assembled here.

/// [when] on a 12-hour clock, e.g. `8:45 م`.
///
/// The formatting is `luqmaClockTime` in `luqma_core` now. It had reached four copies
/// across three apps — this one, the opening hours beside it, and two written in the same
/// week in the merchant app that had gone further and hardcoded `ص` and `م` into a screen
/// while the l10n keys existed. The name stays because these call sites read better for
/// it and renaming twenty of them is churn.
String formatClockTime(DateTime when, LuqmaStrings strings) =>
    luqmaClockTime(when, strings);

/// The day [when] fell on, seen from [now]: `النهارده`, `امبارح`, a colloquial weekday
/// name within the last week, and a plain `d/m/yyyy` before that — order history runs
/// long, and a column of weekday names stops meaning anything past seven days.
String formatOrderDay(DateTime when, DateTime now, LuqmaStrings strings) {
  // Localised first, for the reason in [formatClockTime]: a UTC value would put the
  // calendar day in the wrong bucket either side of midnight.
  final local = when.toLocal();
  final localNow = now.toLocal();
  // Then compared as UTC-midnight dates so the day count is not thrown out by a DST
  // change sitting between the two local midnights — Egypt observes summer time. These
  // are calendar dates being counted, not instants.
  final startOfToday = DateTime.utc(localNow.year, localNow.month, localNow.day);
  final startOfThatDay = DateTime.utc(local.year, local.month, local.day);
  final daysApart = startOfToday.difference(startOfThatDay).inDays;

  if (daysApart <= 0) return strings.orderDayToday;
  if (daysApart == 1) return strings.orderDayYesterday;
  if (daysApart < 7) return _weekdayName(local.weekday, strings);
  return '${local.day}/${local.month}/${local.year}';
}

/// [weekday] is [DateTime.weekday] — 1 (Monday) to 7 (Sunday).
///
/// The `% 7` guards a value that cannot occur, and it is safe for one that could: Dart's
/// `%` is Euclidean and always returns a non-negative result for a positive divisor, so
/// `(0 - 1) % 7` is 6 rather than the -1 it would be in C or Java. A review flagged this
/// as a `RangeError` waiting to happen; it is not, and the language is the reason.
String _weekdayName(int weekday, LuqmaStrings strings) {
  final names = [
    strings.orderDayMon,
    strings.orderDayTue,
    strings.orderDayWed,
    strings.orderDayThu,
    strings.orderDayFri,
    strings.orderDaySat,
    strings.orderDaySun,
  ];
  return names[(weekday - 1) % 7];
}
