// Trip dates are date-only values (backend: date.isoformat()). The
// countdown must be the calendar-day difference between the user's LOCAL
// today and the trip's start day, with no timezone shift of the start day
// and no daylight-saving rounding.
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/utils/trip_dates.dart';
import 'package:frontend/models/trip_model.dart';

void main() {
  group('parseDate keeps the written calendar day', () {
    for (final raw in const [
      '2026-11-19', // what the backend sends
      '2026-11-19T00:00:00Z', // UTC midnight
      '2026-11-19T00:00:00+05:30', // east of UTC (instant is 18 Nov UTC)
      '2026-11-19T23:30:00-08:00', // west of UTC (instant is 20 Nov UTC)
      ' 2026-11-19 ',
    ]) {
      test(raw, () {
        final d = TripDates.parseDate(raw)!;
        expect(d.isUtc, isFalse);
        expect([d.year, d.month, d.day], [2026, 11, 19]);
        expect([d.hour, d.minute], [0, 0]);
      });
    }

    test('non-dates give null', () {
      expect(TripDates.parseDate(null), isNull);
      expect(TripDates.parseDate('not a date'), isNull);
    });

    test('TripModel uses it for start and end', () {
      final trip = TripModel.fromJson({
        'destination': 'Kyoto, Japan',
        'startDate': '2026-11-19T00:00:00+05:30',
        'endDate': '2026-11-26T00:00:00Z',
        'travelers': 1,
      });
      expect([trip.startDate.month, trip.startDate.day], [11, 19]);
      expect([trip.endDate.month, trip.endDate.day], [11, 26]);
      expect(trip.numberOfDays, 8);
    });
  });

  group('countdown = local calendar days', () {
    final start = TripDates.parseDate('2026-11-19')!;

    test('same answer at 00:01 and 23:59 local', () {
      expect(TripDates.daysUntil(start, now: DateTime(2026, 11, 14, 0, 1)), 5);
      expect(
        TripDates.daysUntil(start, now: DateTime(2026, 11, 14, 23, 59)),
        5,
      );
      expect(
        TripDates.daysUntil(start, now: DateTime(2026, 11, 18, 23, 59)),
        1,
      );
      expect(TripDates.daysUntil(start, now: DateTime(2026, 11, 19, 0, 0)), 0);
    });

    // Instants just either side of UTC midnight. Whatever timezone the
    // test machine is in, "today" must be the LOCAL calendar day of that
    // instant, not its UTC day.
    for (final now in [
      DateTime.utc(2026, 11, 13, 23, 30),
      DateTime.utc(2026, 11, 14, 0, 30),
      DateTime.utc(2026, 11, 13, 19, 0), // already 14 Nov in UTC+5:30
      DateTime.utc(2026, 11, 14, 5, 0), // still 13 Nov in UTC-8
    ]) {
      test('UTC/local midnight boundary: $now', () {
        final local = now.toLocal();
        final expected = DateTime.utc(
          2026,
          11,
          19,
        ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
        expect(
          TripDates.today(now: now),
          DateTime(local.year, local.month, local.day),
        );
        expect(TripDates.daysUntil(start, now: now), expected);
        // When the local and UTC days differ, the UTC day must NOT win.
        if (local.day != now.day) {
          final utcBased = DateTime.utc(
            2026,
            11,
            19,
          ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
          expect(TripDates.daysUntil(start, now: now), isNot(utcBased));
        }
      });
    }

    test('daylight-saving changes do not drop a day', () {
      // EU (29 Mar 2026, 25 Oct 2026) and US (8 Mar 2026, 1 Nov 2026)
      // transitions; local midnights there are 23 h or 25 h apart.
      expect(
        TripDates.daysBetween(DateTime(2026, 3, 27), DateTime(2026, 3, 31)),
        4,
      );
      expect(
        TripDates.daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)),
        2,
      );
      expect(
        TripDates.daysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 9)),
        2,
      );
      expect(
        TripDates.daysBetween(DateTime(2026, 10, 31), DateTime(2026, 11, 2)),
        2,
      );
      final trip = TripModel.fromJson({
        'destination': 'Paris, France',
        'startDate': '2026-03-27',
        'endDate': '2026-04-02',
        'travelers': 2,
      });
      expect(trip.numberOfDays, 7);
    });
  });
}
