import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/task_due.dart';
import 'package:todori/src/rust/api.dart';

TaskDueDto testDateTimeDueFromMillis(int value, {String timeZone = 'UTC'}) =>
    dateTimeDueFromInstant(
      DateTime.fromMillisecondsSinceEpoch(value),
      timeZone: timeZone,
    );

void main() {
  test('date-only due keeps its civil date without an instant', () {
    final due = dateOnlyDue(DateTime(2026, 7, 12, 23, 30));

    expect(due, isA<TaskDueDto_Date>());
    expect(taskDueCivilDate(due), '2026-07-12');
    expect(taskDueInstant(due), isNull);
    expect(taskDueSavedTimeZone(due), isNull);
  });

  test('datetime due keeps the instant and IANA time zone', () {
    final local = DateTime(2026, 7, 12, 17, 30);
    final due = dateTimeDue(localDateTime: local, timeZone: 'Asia/Tokyo');

    expect(due, isA<TaskDueDto_DateTime>());
    expect(taskDueCivilDate(due), isNull);
    expect(taskDueInstant(due), DateTime.utc(2026, 7, 12, 8, 30));
    expect(taskDueSavedTimeZone(due), 'Asia/Tokyo');
    expect(taskDueDto(taskDueInput(due)), due);
  });

  test('datetime rejects a DST gap in the selected IANA time zone', () {
    expect(
      () => dateTimeDue(
        localDateTime: DateTime(2026, 3, 8, 2, 30),
        timeZone: 'America/New_York',
      ),
      throwsFormatException,
    );
  });

  test('datetime fold uses a deterministic instant and exposes its offset', () {
    final first = dateTimeDue(
      localDateTime: DateTime(2026, 11, 1, 1, 30),
      timeZone: 'America/New_York',
    );
    final second = dateTimeDue(
      localDateTime: DateTime(2026, 11, 1, 1, 30),
      timeZone: 'America/New_York',
    );
    final displayed = taskDueDisplayDate(first);

    expect(taskDueInstant(first), taskDueInstant(second));
    expect(displayed.hour, 1);
    expect(taskDueUtcOffsetLabel(displayed), anyOf('UTC-04:00', 'UTC-05:00'));
  });

  test('date-only becomes overdue on the next civil date only', () {
    final due = dateOnlyDue(DateTime(2026, 7, 12));

    expect(taskDueIsOverdue(due, now: DateTime(2026, 7, 12, 23, 59)), isFalse);
    expect(taskDueIsOverdue(due, now: DateTime(2026, 7, 13)), isTrue);
  });

  test('datetime becomes overdue at the exact instant', () {
    final due = dateTimeDue(
      localDateTime: DateTime(2026, 7, 12, 17),
      timeZone: 'Asia/Tokyo',
    );

    expect(
      taskDueIsOverdue(due, now: DateTime.utc(2026, 7, 12, 7, 59)),
      isFalse,
    );
    expect(
      taskDueIsOverdue(due, now: DateTime.utc(2026, 7, 12, 8)),
      isTrue,
    );
  });

  test('same-day datetime sorts before date-only due', () {
    final date = dateOnlyDue(DateTime(2026, 7, 12));
    final dateTime = dateTimeDue(
      localDateTime: DateTime(2026, 7, 12, 17),
      timeZone: 'Asia/Tokyo',
    );

    expect(compareTaskDue(dateTime, date), lessThan(0));
    expect(compareTaskDue(date, dateTime), greaterThan(0));
    expect(compareTaskDue(date, null), lessThan(0));
  });

  test('datetime display uses the saved IANA zone and offset', () {
    final due = testDateTimeDueFromMillis(
      DateTime.utc(2026, 7, 12, 12).millisecondsSinceEpoch,
      timeZone: 'America/New_York',
    );
    final displayed = taskDueDisplayDate(due);

    expect(displayed.hour, 8);
    expect(taskDueUtcOffsetLabel(displayed), 'UTC-04:00');
  });
}
