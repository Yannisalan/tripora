/// Calendar-date helpers for trip dates.
///
/// Trip start/end dates are DATE-ONLY values: the backend serialises them
/// with `date.isoformat()` ("2026-11-19") and reads them back with
/// `date.fromisoformat(value[:10])`. They name a calendar day, not an
/// instant, so they must never move through a timezone conversion.
///
/// - [parseDate] keeps the written calendar day ("2026-11-19..." is
///   19 Nov in every timezone, even if a time or offset follows).
/// - [today] is the user's LOCAL calendar day.
/// - [daysBetween] counts calendar days with UTC arithmetic, so a
///   daylight-saving change (a 23 h or 25 h local day) cannot make
///   `Duration.inDays` round down by one.
class TripDates {
  TripDates._();

  static final RegExp _isoDate = RegExp(r'^\s*(\d{4})-(\d{2})-(\d{2})');

  /// Parses a trip date as a local calendar date (midnight, no shift).
  /// Returns null when [raw] is not a date.
  static DateTime? parseDate(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString();
    final m = _isoDate.firstMatch(text);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    final parsed = DateTime.tryParse(text);
    return parsed == null ? null : calendarDate(parsed);
  }

  /// [date]'s own calendar day as local midnight (no timezone conversion).
  static DateTime calendarDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// The user's local calendar day ([now] defaults to the current time; an
  /// instant given in UTC is first converted to local time).
  static DateTime today({DateTime? now}) {
    final local = (now ?? DateTime.now()).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Whole calendar days from [from] to [to] (negative if [to] is earlier).
  static int daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  /// Calendar days from the user's local today until [start].
  static int daysUntil(DateTime start, {DateTime? now}) =>
      daysBetween(today(now: now), start);
}
