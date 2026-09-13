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
String formatOrderDay(DateTime when, DateTime now, LuqmaStrings strings) =>
    // One copy, in luqma_core, since AdminApp's customer detail needed the same
    // sentence the same week. Two copies of a date bucket is two answers to
    // "was this yesterday" on either side of midnight.
    luqmaOrderDay(when, now, strings);

