import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:todori/src/core/bridge_service.dart';
import 'package:todori/src/rust/api.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const reminderNotificationCategoryId = 'todori_reminder_v1';
const reminderSnoozeActionId = 'todori_snooze_1h';
const reminderSnoozeDuration = Duration(hours: 1);

typedef NotificationResponseHandler =
    Future<void> Function(ReminderNotificationResponse response);

class ReminderNotificationPayload {
  const ReminderNotificationPayload({
    required this.reminderId,
    required this.taskId,
    required this.listId,
  });

  final String reminderId;
  final String taskId;
  final String listId;

  String encode() => jsonEncode({
    'reminderId': reminderId,
    'taskId': taskId,
    'listId': listId,
  });

  static ReminderNotificationPayload? decode(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final reminderId = decoded['reminderId'];
    final taskId = decoded['taskId'];
    final listId = decoded['listId'];
    if (reminderId is! String || taskId is! String || listId is! String) {
      return null;
    }
    return ReminderNotificationPayload(
      reminderId: reminderId,
      taskId: taskId,
      listId: listId,
    );
  }
}

class ReminderNotificationResponse {
  const ReminderNotificationResponse({required this.actionId, this.payload});

  final String actionId;
  final ReminderNotificationPayload? payload;
}

class ReminderNotificationContent {
  const ReminderNotificationContent({
    required this.title,
    required this.body,
    required this.snoozeActionTitle,
  });

  final String title;
  final String body;
  final String snoozeActionTitle;
}

abstract class ReminderNotificationGateway {
  Future<ReminderNotificationResponse?> initialize({
    required String snoozeActionTitle,
    required NotificationResponseHandler onResponse,
  });
  Future<bool> requestPermissions();
  Future<void> schedule({
    required int notificationId,
    required DateTime scheduledAt,
    required ReminderNotificationContent content,
    required ReminderNotificationPayload payload,
  });
  Future<void> cancel(int notificationId);
}

class FlutterLocalReminderNotificationGateway
    implements ReminderNotificationGateway {
  FlutterLocalReminderNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _timeZonesInitialized = false;

  @override
  Future<ReminderNotificationResponse?> initialize({
    required String snoozeActionTitle,
    required NotificationResponseHandler onResponse,
  }) async {
    _initializeTimeZones();
    final category = DarwinNotificationCategory(
      reminderNotificationCategoryId,
      actions: [
        DarwinNotificationAction.plain(
          reminderSnoozeActionId,
          snoozeActionTitle,
          options: {DarwinNotificationActionOption.foreground},
        ),
      ],
    );
    final settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [category],
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [category],
      ),
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        onResponse(_fromPluginResponse(response));
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    return launchResponse == null ? null : _fromPluginResponse(launchResponse);
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
    return ios ?? macos ?? true;
  }

  @override
  Future<void> schedule({
    required int notificationId,
    required DateTime scheduledAt,
    required ReminderNotificationContent content,
    required ReminderNotificationPayload payload,
  }) async {
    _initializeTimeZones();
    final scheduled = tz.TZDateTime.from(scheduledAt.toLocal(), tz.local);
    await _plugin.zonedSchedule(
      id: notificationId,
      title: content.title,
      body: content.body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          categoryIdentifier: reminderNotificationCategoryId,
        ),
        macOS: DarwinNotificationDetails(
          categoryIdentifier: reminderNotificationCategoryId,
        ),
        android: AndroidNotificationDetails(
          'todori_reminders',
          'Todori reminders',
          channelDescription: 'Local reminders scheduled by Todori',
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

class ReminderNotificationService {
  ReminderNotificationService({required this.bridge, required this.gateway});

  final BridgeService bridge;
  final ReminderNotificationGateway gateway;
  ReminderNotificationContent? _content;

  Future<void> initialize(ReminderNotificationContent content) async {
    _content = content;
    final launchResponse = await gateway.initialize(
      snoozeActionTitle: content.snoozeActionTitle,
      onResponse: handleResponse,
    );
    if (launchResponse != null) {
      await handleResponse(launchResponse);
    }
  }

  Future<bool> requestPermissions() {
    return gateway.requestPermissions();
  }

  Future<void> scheduleReminder({
    required ReminderDto reminder,
    required String listId,
    required ReminderNotificationContent content,
  }) async {
    final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
      effectiveReminderAt(reminder),
    );
    if (!scheduledAt.isAfter(DateTime.now())) {
      return;
    }
    await gateway.schedule(
      notificationId: notificationIdForReminder(reminder.id),
      scheduledAt: scheduledAt,
      content: content,
      payload: ReminderNotificationPayload(
        reminderId: reminder.id,
        taskId: reminder.taskId,
        listId: listId,
      ),
    );
  }

  Future<void> cancelReminder(ReminderDto reminder) {
    return gateway.cancel(notificationIdForReminder(reminder.id));
  }

  Future<void> cancelReminders(Iterable<ReminderDto> reminders) async {
    for (final reminder in reminders) {
      await cancelReminder(reminder);
    }
  }

  Future<void> reschedulePending(ReminderNotificationContent content) async {
    final reminders = await bridge.listPendingReminders(
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    for (final reminder in reminders) {
      final task = await _findTask(reminder.taskId);
      if (task == null) {
        continue;
      }
      await scheduleReminder(
        reminder: reminder,
        listId: task.listId,
        content: content,
      );
    }
  }

  Future<void> handleResponse(ReminderNotificationResponse response) async {
    final payload = response.payload;
    final content = _content;
    if (payload == null ||
        content == null ||
        response.actionId != reminderSnoozeActionId) {
      return;
    }
    final snoozedUntil = DateTime.now()
        .add(reminderSnoozeDuration)
        .millisecondsSinceEpoch;
    final reminder = await bridge.snoozeReminder(
      reminderId: payload.reminderId,
      snoozedUntil: snoozedUntil,
    );
    await scheduleReminder(
      reminder: reminder,
      listId: payload.listId,
      content: content,
    );
  }

  Future<TaskDto?> _findTask(String taskId) async {
    final lists = await bridge.getLists();
    for (final list in lists) {
      final tasks = await bridge.getTasks(listId: list.id);
      for (final task in tasks) {
        if (task.id == taskId) {
          return task;
        }
      }
    }
    return null;
  }
}

ReminderNotificationResponse reminderResponseFromPlugin(
  NotificationResponse response,
) {
  return _fromPluginResponse(response);
}

ReminderNotificationResponse _fromPluginResponse(
  NotificationResponse response,
) {
  return ReminderNotificationResponse(
    actionId: response.actionId ?? '',
    payload: ReminderNotificationPayload.decode(response.payload),
  );
}

int effectiveReminderAt(ReminderDto reminder) =>
    reminder.snoozedUntil ?? reminder.remindAt;

@visibleForTesting
int notificationIdForReminder(String reminderId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in reminderId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
