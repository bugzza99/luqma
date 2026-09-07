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

/// [when] on a 12-hour clock, e.g. `8:45 م`. Western digits, no leading zero on the
/// hour, minutes padded to two. [strings] supplies only the ص/م marker.
String formatClockTime(DateTime when, LuqmaStrings strings) {
  // `.hour` on a UTC `DateTime` is the UTC hour. `TimestampConverter` already localises
  // everything parsed from the server, so nothing in the app reaches here with a UTC
  // value today — but these take a bare `DateTime` and a caller cannot see that
  // requirement from the signature. Egypt is UTC+2 or +3, so getting it wrong shows an
  // order placed ten minutes ago as three hours old, and across midnight as yesterday.
  // Localising is a no-op for a value that is already local.
  final local = when.toLocal();
  final isPm = local.hour >= 12;
  var hour = local.hour % 12;
  if (hour == 0) hour = 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${isPm ? strings.clockPm : strings.clockAm}';
}

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
