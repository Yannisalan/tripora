import '../services/notification_service.dart';

/// Adjust these getters to match your actual Trip model — this file
/// assumes a Trip has `id` (String), `destination` (String),
/// `startDate` (DateTime) and `endDate` (DateTime). If your model
/// differs, only the field access below needs to change.
abstract class TripLike {
  String get id;
  String get destination;
  DateTime get startDate;
  DateTime get endDate;
}

enum _ReminderType {
  weekBefore(offsetKey: 0, hour: 10),
  dayBefore(offsetKey: 1, hour: 18),
  dayOf(offsetKey: 2, hour: 7);

  const _ReminderType({required this.offsetKey, required this.hour});

  /// Small integer baked into the notification id so each reminder type
  /// for the same trip gets a distinct, stable id.
  final int offsetKey;

  /// Local hour of day the reminder should fire at.
  final int hour;
}

/// Schedules and cancels local reminders for a trip's key dates.
///
/// Call [scheduleForTrip] whenever a trip is created or its dates are
/// edited (it clears old reminders for that trip first, so it's safe
/// to call again on every save). Call [cancelForTrip] when a trip is
/// deleted.
class TripReminderScheduler {
  TripReminderScheduler._();

  /// Schedules:
  /// - 7 days before the trip starts, 10:00 local time
  /// - 1 day before the trip starts, 18:00 local time (evening-before)
  /// - The morning of the trip, 07:00 local time
  ///
  /// Reminders whose fire time has already passed (e.g. trip starts in
  /// 3 days, so the "7 days before" reminder is moot) are silently
  /// skipped by NotificationService rather than causing an error.
  static Future<void> scheduleForTrip(TripLike trip) async {
    // Clear any reminders from a previous version of this trip first,
    // so editing a trip's dates doesn't leave stale notifications.
    await cancelForTrip(trip);

    final granted = await NotificationService.instance.requestPermission();
    if (!granted) return;

    final start = trip.startDate;

    final weekBeforeDate = DateTime(
      start.year,
      start.month,
      start.day - 7,
      _ReminderType.weekBefore.hour,
    );
    final dayBeforeDate = DateTime(
      start.year,
      start.month,
      start.day - 1,
      _ReminderType.dayBefore.hour,
    );
    final dayOfDate = DateTime(
      start.year,
      start.month,
      start.day,
      _ReminderType.dayOf.hour,
    );

    await NotificationService.instance.schedule(
      id: _idFor(trip.id, _ReminderType.weekBefore),
      title: 'Your trip to ${trip.destination} is a week away',
      body: 'Time to double-check bookings and start packing.',
      scheduledDate: weekBeforeDate,
      payload: trip.id,
    );

    await NotificationService.instance.schedule(
      id: _idFor(trip.id, _ReminderType.dayBefore),
      title: '${trip.destination} starts tomorrow',
      body: 'Last chance to review your itinerary before you go.',
      scheduledDate: dayBeforeDate,
      payload: trip.id,
    );

    await NotificationService.instance.schedule(
      id: _idFor(trip.id, _ReminderType.dayOf),
      title: 'Have a great trip to ${trip.destination}!',
      body: 'Tap to open today\'s itinerary.',
      scheduledDate: dayOfDate,
      payload: trip.id,
    );
  }

  static Future<void> cancelForTrip(TripLike trip) async {
    await cancelForTripId(trip.id);
  }

  /// Cancels reminders when only the trip id is available (e.g. a
  /// delete endpoint that takes just an id, with no destination/dates).
  static Future<void> cancelForTripId(String tripId) async {
    await NotificationService.instance.cancelAll([
      _idFor(tripId, _ReminderType.weekBefore),
      _idFor(tripId, _ReminderType.dayBefore),
      _idFor(tripId, _ReminderType.dayOf),
    ]);
  }

  /// Derives a stable, positive 32-bit notification id from the trip's
  /// string id plus the reminder type, so each (trip, reminder type)
  /// pair always maps to the same id across app runs.
  static int _idFor(String tripId, _ReminderType type) {
    final hash = tripId.hashCode & 0x7fffffff; // keep it positive
    // Reserve the low 2 bits for the reminder type (3 types fit in 2 bits),
    // shifting the trip hash left to make room without losing much
    // uniqueness across trips.
    return ((hash >> 2) << 2) | type.offsetKey;
  }
}