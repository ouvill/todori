import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/notifications/reminder_notifications.dart';

import 'support/fake_bridge_service.dart';

void main() {
  test(
    'reminder provider saves schedules and clears local notifications',
    () async {
      final fakeBridge = FakeBridgeService();
      final gateway = _FakeReminderNotificationGateway();
      final list = await fakeBridge.createDefaultList(
        name: 'Inbox',
        sortOrder: 'a0',
      );
      final task = await fakeBridge.createTask(
        listId: list.id,
        title: 'Schedule reminder',
      );
      final container = ProviderContainer(
        overrides: [
          bridgeServiceProvider.overrideWithValue(fakeBridge),
          reminderNotificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(reminderNotificationServiceProvider);
      final content = _content;
      final permission = await service.requestPermissions();
      final reminder = await container
          .read(taskRemindersProvider(task.id).notifier)
          .setReminder(
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
          );
      if (permission) {
        await service.scheduleReminder(
          reminder: reminder,
          listId: list.id,
          content: content,
        );
      }

      expect(gateway.permissionRequests, 1);
      expect(gateway.scheduled.single.payload.reminderId, reminder.id);
      expect(await fakeBridge.getTaskReminders(taskId: task.id), [reminder]);

      await container
          .read(taskRemindersProvider(task.id).notifier)
          .clearReminders();

      expect(gateway.cancelled, [notificationIdForReminder(reminder.id)]);
      expect(await fakeBridge.getTaskReminders(taskId: task.id), isEmpty);
    },
  );

  test(
    'permission denial saves the reminder without scheduling plugin work',
    () async {
      final fakeBridge = FakeBridgeService();
      final gateway = _FakeReminderNotificationGateway(
        permissionsGranted: false,
      );
      final list = await fakeBridge.createDefaultList(
        name: 'Inbox',
        sortOrder: 'a0',
      );
      final task = await fakeBridge.createTask(
        listId: list.id,
        title: 'Denied reminder',
      );
      final container = ProviderContainer(
        overrides: [
          bridgeServiceProvider.overrideWithValue(fakeBridge),
          reminderNotificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      final permission = await container
          .read(reminderNotificationServiceProvider)
          .requestPermissions();
      final reminder = await container
          .read(taskRemindersProvider(task.id).notifier)
          .setReminder(
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
          );

      expect(permission, isFalse);
      expect(await fakeBridge.getTaskReminders(taskId: task.id), [reminder]);
      expect(gateway.scheduled, isEmpty);
    },
  );

  test(
    'snooze notification action updates reminder and reschedules it',
    () async {
      final fakeBridge = FakeBridgeService();
      final gateway = _FakeReminderNotificationGateway();
      final list = await fakeBridge.createDefaultList(
        name: 'Inbox',
        sortOrder: 'a0',
      );
      final task = await fakeBridge.createTask(
        listId: list.id,
        title: 'Snooze reminder',
      );
      final reminder = await fakeBridge.setTaskReminder(
        taskId: task.id,
        remindAt: DateTime.now()
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch,
      );
      final service = ReminderNotificationService(
        bridge: fakeBridge,
        gateway: gateway,
      );
      await service.initialize(_content);

      await service.handleResponse(
        ReminderNotificationResponse(
          actionId: reminderSnoozeActionId,
          payload: ReminderNotificationPayload(
            reminderId: reminder.id,
            taskId: task.id,
            listId: list.id,
          ),
        ),
      );

      final updated = (await fakeBridge.getTaskReminders(
        taskId: task.id,
      )).single;
      expect(updated.snoozedUntil, isNotNull);
      expect(gateway.scheduled.single.payload.reminderId, reminder.id);
      expect(
        gateway.scheduled.single.scheduledAt.millisecondsSinceEpoch,
        updated.snoozedUntil,
      );
    },
  );

  test('startup reschedules pending reminders for open tasks', () async {
    final fakeBridge = FakeBridgeService();
    final gateway = _FakeReminderNotificationGateway();
    final list = await fakeBridge.createDefaultList(
      name: 'Inbox',
      sortOrder: 'a0',
    );
    final task = await fakeBridge.createTask(
      listId: list.id,
      title: 'Startup reminder',
    );
    final reminder = await fakeBridge.setTaskReminder(
      taskId: task.id,
      remindAt: DateTime.now()
          .add(const Duration(hours: 2))
          .millisecondsSinceEpoch,
    );
    final service = ReminderNotificationService(
      bridge: fakeBridge,
      gateway: gateway,
    );

    await service.reschedulePending(_content);

    expect(gateway.scheduled.single.payload.reminderId, reminder.id);
  });
}

const _content = ReminderNotificationContent(
  title: 'Todori reminder',
  body: 'A task reminder is due.',
  snoozeActionTitle: '+1 hour',
);

class _FakeReminderNotificationGateway implements ReminderNotificationGateway {
  _FakeReminderNotificationGateway({this.permissionsGranted = true});

  final bool permissionsGranted;
  final scheduled = <_ScheduledReminder>[];
  final cancelled = <int>[];
  int permissionRequests = 0;
  NotificationResponseHandler? responseHandler;

  @override
  Future<ReminderNotificationResponse?> initialize({
    required String snoozeActionTitle,
    required NotificationResponseHandler onResponse,
  }) async {
    responseHandler = onResponse;
    return null;
  }

  @override
  Future<bool> requestPermissions() async {
    permissionRequests += 1;
    return permissionsGranted;
  }

  @override
  Future<void> schedule({
    required int notificationId,
    required DateTime scheduledAt,
    required ReminderNotificationContent content,
    required ReminderNotificationPayload payload,
  }) async {
    scheduled.add(
      _ScheduledReminder(
        notificationId: notificationId,
        scheduledAt: scheduledAt,
        content: content,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
  }
}

class _ScheduledReminder {
  const _ScheduledReminder({
    required this.notificationId,
    required this.scheduledAt,
    required this.content,
    required this.payload,
  });

  final int notificationId;
  final DateTime scheduledAt;
  final ReminderNotificationContent content;
  final ReminderNotificationPayload payload;
}
