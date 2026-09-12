import '../l10n/app_localizations.dart';

/// A time of day, the way this product writes one: `9:20 ص`.
///
/// Shared rather than private, because it had reached four copies in three apps — the
/// customer's order list and opening hours, and then two more written the same week in
/// the courier screen and the shop's roster, both of which had gone further and hardcoded
/// `ص` and `م` into a screen while the l10n keys for them already existed.
///
/// `CLAUDE.md` records what that habit costs here: seventeen private error views that
/// drifted into fifteen different versions. This is the cheap moment to stop it.
///
/// **Western digits and the ص/م marker only.** `intl`'s `ar` locale would bring
/// Arabic-Indic digits, which this product deliberately does not use — the same decision
/// prices are written under.
///
/// [when] is localised first. `.hour` on a UTC `DateTime` is the UTC hour, and Egypt is
/// two or three hours from it, so a value that slipped through unlocalised shows an order
/// placed ten minutes ago as three hours old and, across midnight, as yesterday.
/// Localising is a no-op for a value that is already local.
String luqmaClockTime(DateTime when, LuqmaStrings strings) {
  final local = when.toLocal();
  return luqmaClockMinute(local.hour * 60 + local.minute, strings, padHour: true);
}

/// The same clock, from a minute of the day — which is how opening hours are stored.
///
/// On-the-hour times drop the `:00` unless [padHour] asks otherwise, matching the
/// artboard's «مفتوح لحد 1 ص». A timestamp keeps its minutes because `9 ص` for something
/// that happened at 9:00 reads as an approximation.
String luqmaClockMinute(
  int minuteOfDay,
  LuqmaStrings strings, {
  bool padHour = false,
}) {
  final m = minuteOfDay % 1440;
  final isPm = m >= 720;
  var hour = (m ~/ 60) % 12;
  if (hour == 0) hour = 12;
  final minute = m % 60;
  final marker = isPm ? strings.clockPm : strings.clockAm;
  if (minute == 0 && !padHour) return '$hour $marker';
  return '$hour:${minute.toString().padLeft(2, '0')} $marker';
}

/// The day [when] fell on, seen from [now]: `النهارده`, `امبارح`, a colloquial weekday
/// name within the last week, and a plain `d/m/yyyy` before that.
String luqmaOrderDay(DateTime when, DateTime now, LuqmaStrings strings) {
  final local = when.toLocal();
  final localNow = now.toLocal();
  final startOfToday = DateTime.utc(localNow.year, localNow.month, localNow.day);
  final startOfThatDay = DateTime.utc(local.year, local.month, local.day);
  final daysApart = startOfToday.difference(startOfThatDay).inDays;

  if (daysApart <= 0) return strings.orderDayToday;
  if (daysApart == 1) return strings.orderDayYesterday;
  if (daysApart < 7) {
    return switch (local.weekday) {
      DateTime.monday => strings.orderDayMon,
      DateTime.tuesday => strings.orderDayTue,
      DateTime.wednesday => strings.orderDayWed,
      DateTime.thursday => strings.orderDayThu,
      DateTime.friday => strings.orderDayFri,
      DateTime.saturday => strings.orderDaySat,
      DateTime.sunday => strings.orderDaySun,
      _ => '${local.day}/${local.month}/${local.year}',
    };
  }
  return '${local.day}/${local.month}/${local.year}';
}

/// Arabic month names for join dates and history.
String luqmaMonthName(int month) {
  const months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  if (month < 1 || month > 12) return '';
  return months[month - 1];
}

