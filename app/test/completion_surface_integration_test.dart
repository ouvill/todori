import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskveil/main.dart';
import 'package:taskveil/src/core/providers.dart';
import 'package:taskveil/src/router.dart';
import 'package:taskveil/src/rust/api.dart';
import 'package:taskveil/src/screens/calendar_screen.dart';

import 'support/fake_bridge_service.dart';

void main() {
  for (final surface in ['home', 'list', 'calendar', 'detail']) {
    testWidgets('$surface completion saves restored work before done', (
      tester,
    ) async {
      final bridge = _SurfaceOrderingBridge();
      final list = await bridge.createDefaultList(
        name: 'Inbox',
        sortOrder: 'a0',
      );
      final today = DateTime.now();
      final task = await bridge.createTask(
        listId: list.id,
        title: 'Finish in order',
        due: testDateOnlyDueFromMillis(
          DateTime(today.year, today.month, today.day).millisecondsSinceEpoch,
        ),
      );
      final startedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      await bridge.startActiveTimerSession(
        session: ActiveTimerSessionDto(
          sessionId: '00000000-0000-4000-8000-000000000123',
          taskId: task.id,
          mode: TimerModeDto.stopwatch,
          phase: TimerPhaseDto.work,
          state: TimerRunStateDto.running,
          startedAt: startedAt,
          lastResumedAt: startedAt,
          accumulatedActiveMs: 0,
        ),
      );
      final router = buildAppRouter();
      await tester.pumpWidget(
        TaskveilApp(
          router: router,
          overrides: [bridgeServiceProvider.overrideWithValue(bridge)],
        ),
      );
      await tester.pumpAndSettle();

      switch (surface) {
        case 'home':
          break;
        case 'list':
          router.go('/lists/${list.id}/tasks');
        case 'calendar':
          router.go('/calendar');
        case 'detail':
          router.go('/lists/${list.id}/tasks/${task.id}');
      }
      await tester.pumpAndSettle();

      final checkbox = switch (surface) {
        'detail' => find.byKey(ValueKey('task-detail-done-${task.id}')),
        'calendar' => find.byKey(
          ValueKey(
            'calendar-occurrence-check-${await _calendarKey(bridge, task.id)}',
          ),
        ),
        _ => find.byKey(ValueKey('task-done-${task.id}')),
      };
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pump(const Duration(milliseconds: 300));

      expect(bridge.operations, ['finish', 'status:done']);
      expect((await bridge.getTasks(listId: list.id)).single.status, 'done');
      expect(await bridge.getActiveTimerSession(), isNull);
    });
  }
}

Future<CalendarOccurrenceKey> _calendarKey(
  FakeBridgeService bridge,
  String taskId,
) async {
  final occurrences = await bridge.getCalendarOccurrences(
    range: CalendarRange.day(DateTime.now()).toInput(),
  );
  return CalendarOccurrenceKey.fromOccurrence(
    occurrences.singleWhere(
      (occurrence) =>
          occurrence.task.id == taskId &&
          occurrence.kind is CalendarOccurrenceKindDto_DateDue,
    ),
  );
}

class _SurfaceOrderingBridge extends FakeBridgeService {
  final operations = <String>[];

  @override
  Future<bool> finishActiveTimerSession({
    required CompletedTimerSessionDto session,
  }) async {
    operations.add('finish');
    return super.finishActiveTimerSession(session: session);
  }

  @override
  Future<TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  }) async {
    operations.add('status:$status');
    return super.setTaskStatus(
      taskId: taskId,
      status: status,
      closedReason: closedReason,
    );
  }
}
