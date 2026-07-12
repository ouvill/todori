import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const timerNotificationCategoryId = 'todori_timer_v1';
const timerNotificationChannelId = 'todori_timers';

class TimerNotificationPayload {
  const TimerNotificationPayload({required this.sessionId});

  final String sessionId;

  String encode() => jsonEncode({
    'owner': timerNotificationCategoryId,
    'sessionId': sessionId,
  });

  static TimerNotificationPayload? decode(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?> ||
          decoded['owner'] != timerNotificationCategoryId ||
          decoded['sessionId'] is! String) {
        return null;
      }
      return TimerNotificationPayload(
        sessionId: decoded['sessionId']! as String,
      );
    } catch (_) {
      return null;
    }
  }
}

class TimerNotificationContent {
  const TimerNotificationContent({required this.title, required this.body});

  final String title;
  final String body;
}

abstract class TimerNotificationGateway {
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<void> schedule({
    required int notificationId,
    required DateTime scheduledAt,
    required TimerNotificationContent content,
    required TimerNotificationPayload payload,
  });
  Future<void> cancel(int notificationId);
}

class FlutterLocalTimerNotificationGateway implements TimerNotificationGateway {
  FlutterLocalTimerNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _timeZonesInitialized = false;

  @override
  Future<void> initialize() async {
    _initializeTimeZones();
  }

  @override
  Future<bool> requestPermissions() async {
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    final macos = await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    return ios ?? macos ?? android ?? true;
  }

  @override
  Future<void> schedule({
    required int notificationId,
    required DateTime scheduledAt,
    required TimerNotificationContent content,
    required TimerNotificationPayload payload,
  }) async {
    _initializeTimeZones();
    await _plugin.zonedSchedule(
      id: notificationId,
      title: content.title,
      body: content.body,
      scheduledDate: tz.TZDateTime.from(scheduledAt.toLocal(), tz.local),
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        android: AndroidNotificationDetails(
          timerNotificationChannelId,
          'Focus timers',
          channelDescription: 'Focus timer completion notifications',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload.encode(),
    );
  }

  @override
  Future<void> cancel(int notificationId) {
    return _plugin.cancel(id: notificationId);
  }

  void _initializeTimeZones() {
    if (_timeZonesInitialized) {
      return;
    }
    tz_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }
}

class TimerNotificationService {
  TimerNotificationService(this.gateway);

  final TimerNotificationGateway gateway;
  TimerNotificationContent? _content;

  Future<void> initialize(TimerNotificationContent content) async {
    _content = content;
    await gateway.initialize();
  }

  Future<bool> requestPermissions() async {
    try {
      return await gateway.requestPermissions();
    } catch (_) {
      return false;
    }
  }

  Future<void> schedule({
    required String sessionId,
    required DateTime scheduledAt,
  }) async {
    final content = _content;
    if (content == null || !scheduledAt.isAfter(DateTime.now())) {
      return;
    }
    try {
      await gateway.schedule(
        notificationId: notificationIdForTimer(sessionId),
        scheduledAt: scheduledAt,
        content: content,
        payload: TimerNotificationPayload(sessionId: sessionId),
      );
    } catch (_) {
      // Notifications are best-effort and never own timer correctness.
    }
  }

  Future<void> cancel(String sessionId) async {
    try {
      await gateway.cancel(notificationIdForTimer(sessionId));
    } catch (_) {
      // Permission and platform failures must not stop the timer engine.
    }
  }
}

@visibleForTesting
int notificationIdForTimer(String sessionId) {
  var hash = 0x4d3c2b1a;
  for (final codeUnit in sessionId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x3fffffff;
  }
  // Reminder IDs are strictly positive. Timer IDs use the negative half of
  // the signed 32-bit space so the two owners cannot collide.
  return -(hash + 1);
}
