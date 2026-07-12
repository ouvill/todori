import 'package:todori/src/rust/api.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

String civilDateFromLocal(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

DateTime localDateFromCivilDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw FormatException('Invalid civil date');
  }
  final date = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (civilDateFromLocal(date) != value) {
    throw FormatException('Invalid civil date');
  }
  return date;
}

TaskDueDto dateOnlyDue(DateTime value) =>
    TaskDueDto.date(dueOn: civilDateFromLocal(value));

TaskDueDto dateTimeDue({
  required DateTime localDateTime,
  required String timeZone,
}) {
  _ensureTimeZoneDatabase();
  final location = tz.getLocation(timeZone);
  final zoned = tz.TZDateTime(
    location,
    localDateTime.year,
    localDateTime.month,
    localDateTime.day,
    localDateTime.hour,
    localDateTime.minute,
  );
  if (zoned.year != localDateTime.year ||
      zoned.month != localDateTime.month ||
      zoned.day != localDateTime.day ||
      zoned.hour != localDateTime.hour ||
      zoned.minute != localDateTime.minute) {
    throw FormatException('Local deadline does not exist in $timeZone');
  }
  return TaskDueDto.dateTime(dueAt: zoned.toUtc(), timeZone: timeZone);
}

TaskDueDto dateTimeDueFromInstant(DateTime value, {String timeZone = 'UTC'}) =>
    TaskDueDto.dateTime(dueAt: value.toUtc(), timeZone: timeZone);

TaskDueInput taskDueInput(TaskDueDto value) => switch (value) {
  TaskDueDto_Date(:final dueOn) => TaskDueInput.date(dueOn: dueOn),
  TaskDueDto_DateTime(:final dueAt, :final timeZone) => TaskDueInput.dateTime(
    dueAt: dueAt,
    timeZone: timeZone,
  ),
};

TaskDueDto taskDueDto(TaskDueInput value) => switch (value) {
  TaskDueInput_Date(:final dueOn) => TaskDueDto.date(dueOn: dueOn),
  TaskDueInput_DateTime(:final dueAt, :final timeZone) => TaskDueDto.dateTime(
    dueAt: dueAt,
    timeZone: timeZone,
  ),
};

bool taskDueIsDateOnly(TaskDueDto value) => value is TaskDueDto_Date;

String? taskDueSavedTimeZone(TaskDueDto? value) => switch (value) {
  TaskDueDto_DateTime(:final timeZone) => timeZone,
  _ => null,
};

String? taskDueCivilDate(TaskDueDto? value) => switch (value) {
  TaskDueDto_Date(:final dueOn) => dueOn,
  _ => null,
};

DateTime? taskDueInstant(TaskDueDto? value) => switch (value) {
  TaskDueDto_DateTime(:final dueAt) => dueAt.toUtc(),
  _ => null,
};

DateTime taskDueLocalDate(TaskDueDto value) => switch (value) {
  TaskDueDto_Date(:final dueOn) => localDateFromCivilDate(dueOn),
  TaskDueDto_DateTime(:final dueAt) => dueAt.toLocal(),
};

DateTime taskDueDisplayDate(TaskDueDto value) => switch (value) {
  TaskDueDto_Date(:final dueOn) => localDateFromCivilDate(dueOn),
  TaskDueDto_DateTime(:final dueAt, :final timeZone) => () {
    _ensureTimeZoneDatabase();
    return tz.TZDateTime.from(dueAt.toUtc(), tz.getLocation(timeZone));
  }(),
};

bool taskDueIsOverdue(TaskDueDto? value, {DateTime? now}) {
  if (value == null) {
    return false;
  }
  final current = now ?? DateTime.now();
  return switch (value) {
    TaskDueDto_Date(:final dueOn) =>
      dueOn.compareTo(civilDateFromLocal(current)) < 0,
    TaskDueDto_DateTime(:final dueAt) => !current.toUtc().isBefore(
      dueAt.toUtc(),
    ),
  };
}

int compareTaskDue(TaskDueDto? a, TaskDueDto? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  final aDay = civilDateFromLocal(taskDueLocalDate(a));
  final bDay = civilDateFromLocal(taskDueLocalDate(b));
  final dayComparison = aDay.compareTo(bDay);
  if (dayComparison != 0) {
    return dayComparison;
  }
  if (a is TaskDueDto_DateTime && b is TaskDueDto_Date) {
    return -1;
  }
  if (a is TaskDueDto_Date && b is TaskDueDto_DateTime) {
    return 1;
  }
  if (a is TaskDueDto_DateTime && b is TaskDueDto_DateTime) {
    return a.dueAt.compareTo(b.dueAt);
  }
  return 0;
}

String taskDueUtcOffsetLabel(DateTime value) {
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hoursPart = (minutes ~/ 60).toString().padLeft(2, '0');
  final minutesPart = (minutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hoursPart:$minutesPart';
}

bool _timeZoneDatabaseInitialized = false;

void _ensureTimeZoneDatabase() {
  if (_timeZoneDatabaseInitialized) {
    return;
  }
  tz_data.initializeTimeZones();
  _timeZoneDatabaseInitialized = true;
}
