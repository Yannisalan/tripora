import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Wraps flutter_local_notifications with:
/// - one-time timezone/plugin initialization
/// - permission requests for Android 13+ and iOS
/// - a single notification channel for trip reminders
/// - helpers to schedule/cancel notifications tied to a trip
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId = 'trip_reminders';
  static const String _channelName = 'Trip reminders';
  static const String _channelDescription =
      'Reminders about your upcoming trips and itineraries';

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    final String localName = DateTime.now().timeZoneName;
    try {
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      tz.setLocalLocation(tz.local);
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const windowsSettings = WindowsInitializationSettings(
      appName: 'Tripora',
      appUserModelId: 'com.tripora.app',
      guid: '5f7e3b0a-6c3d-4a91-9b2e-1d8f4c7a6e20',
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        windows: windowsSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

      return granted ?? false;
    }

    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      final granted = await androidImpl?.requestNotificationsPermission();

      return granted ?? true;
    }

    if (Platform.isWindows) {
      return true;
    }

    return true;
  }

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (!_initialized) await init();

    if (scheduledDate.isBefore(DateTime.now())) {
      if (kDebugMode) {
        debugPrint(
          'NotificationService: skipped id=$id, $scheduledDate is in the past',
        );
      }
      return;
    }

    final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancel(int id) async {
    if (!_initialized) await init();
    await _plugin.cancel(id: id);
  }

  Future<void> cancelAll(List<int> ids) async {
    if (!_initialized) await init();

    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  Future<List<PendingNotificationRequest>> pending() async {
    if (!_initialized) await init();
    return _plugin.pendingNotificationRequests();
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;

    if (payload == null) return;

    if (kDebugMode) {
      debugPrint('Notification tapped, payload=$payload');
    }

    // Example:
    // AppRouter.navigatorKey.currentState?.pushNamed(
    //   AppRoutes.tripDetails,
    //   arguments: payload,
    // );
  }
}
