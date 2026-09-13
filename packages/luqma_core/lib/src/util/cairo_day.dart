import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

final _cairo = (() {
  data.initializeTimeZones();
  return tz.getLocation('Africa/Cairo');
})();

/// Cairo's calendar date, encoded as UTC midnight for timezone-free date arithmetic.
/// The returned value represents a date, not the instant of midnight in Cairo.
DateTime cairoDay(DateTime instant) {
  final local = tz.TZDateTime.from(instant, _cairo);
  return DateTime.utc(local.year, local.month, local.day);
}
