import 'fake_bridge_service.dart';

/// Stable handles for the realistic fake dataset shared by the interactive
/// Design Lab baseline and production Visual QA.
class DesignLabFixture {
  const DesignLabFixture({
    required this.fake,
    required this.homeListId,
    required this.parentWithSubtasksTitle,
    required this.parentWithSubtasksId,
    required this.visibleRootTaskId,
    required this.focusTaskId,
    required this.templateId,
  });

  final FakeBridgeService fake;
  final String homeListId;
  final String parentWithSubtasksTitle;
  final String parentWithSubtasksId;
  final String visibleRootTaskId;
  final String focusTaskId;
  final String templateId;
}

/// Builds the full production-facing Design Lab dataset without pumping UI.
///
/// The fixture deliberately exercises the information that tends to drift in
/// hand-built mocks: due and scheduled planning, priorities, a three-level
/// subtree, completed and wont-do outcomes, multiple reminders, templates,
/// recurrence, and mixed Japanese/English titles.
Future<DesignLabFixture> createDesignLabFixture({
  DateTime? referenceTime,
}) async {
  final fake = FakeBridgeService();
  await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  await fake.createList(name: '仕事', sortOrder: 'a1');
  final lists = await fake.getLists();
  final homeListId = lists[0].id;
  final workListId = lists[1].id;

  DateTime atMidnight(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  final now = referenceTime ?? DateTime.now();
  final today = atMidnight(now).millisecondsSinceEpoch;
  final todayExact = DateTime(
    now.year,
    now.month,
    now.day,
    14,
    30,
  ).millisecondsSinceEpoch;
  final todayScheduled = DateTime(
    now.year,
    now.month,
    now.day,
    10,
    15,
  ).millisecondsSinceEpoch;
  final tomorrow = atMidnight(
    now.add(const Duration(days: 1)),
  ).millisecondsSinceEpoch;
  final overdue = atMidnight(
    now.subtract(const Duration(days: 4)),
  ).millisecondsSinceEpoch;
  final upcoming = atMidnight(
    now.add(const Duration(days: 5)),
  ).millisecondsSinceEpoch;

  final uiTweaks = await fake.createTask(
    listId: homeListId,
    title: '地図アプリのUI微調整を仕上げる',
  );
  await fake.updateTask(
    taskId: uiTweaks.id,
    title: uiTweaks.title,
    note: 'Production baselineとCandidateの差分を確認する。',
    priority: 2,
    due: testDateTimeDueFromMillis(todayExact, timeZone: 'America/New_York'),
    scheduledAt: todayScheduled,
    estimatedMinutes: 35,
  );

  const parentWithSubtasksTitle = 'Plan the product launch event';
  final launch = await fake.createTask(
    listId: homeListId,
    title: parentWithSubtasksTitle,
  );
  await fake.updateTask(
    taskId: launch.id,
    title: launch.title,
    note: 'Keep the launch sequence calm and explicit.',
    priority: 2,
    due: testDateOnlyDueFromMillis(tomorrow),
    estimatedMinutes: 25,
  );
  await fake.createTaskReminder(
    taskId: launch.id,
    remindAt: tomorrow + const Duration(hours: 16, minutes: 30).inMilliseconds,
  );
  await fake.createTaskReminder(
    taskId: launch.id,
    remindAt: tomorrow + const Duration(hours: 17, minutes: 30).inMilliseconds,
  );

  final checklist = await fake.createTask(
    listId: homeListId,
    title: 'Draft the launch checklist',
    parentTaskId: launch.id,
  );
  await fake.updateTask(
    taskId: checklist.id,
    title: checklist.title,
    note: '',
    priority: 1,
    due: testDateOnlyDueFromMillis(today),
  );
  await fake.createTaskReminder(
    taskId: checklist.id,
    remindAt: tomorrow + const Duration(hours: 16, minutes: 30).inMilliseconds,
  );
  await fake.createTask(
    listId: homeListId,
    title: 'Review checklist with design',
    parentTaskId: launch.id,
  );
  final finalCopy = await fake.createTask(
    listId: homeListId,
    title: 'Confirm final copy in the hero panel',
    parentTaskId: checklist.id,
  );
  await fake.updateTask(
    taskId: finalCopy.id,
    title: finalCopy.title,
    note: '',
    priority: 0,
    due: testDateOnlyDueFromMillis(overdue),
  );
  await fake.setTaskStatus(taskId: finalCopy.id, status: 'done');
  await fake.createTask(
    listId: homeListId,
    title: 'デザインレビューのフィードバックを反映する',
    parentTaskId: launch.id,
  );

  final roadmap = await fake.createTask(
    listId: homeListId,
    title:
        'Draft the Q3 roadmap presentation for the leadership offsite '
        'meeting next week',
  );
  await fake.updateTask(
    taskId: roadmap.id,
    title: roadmap.title,
    note: 'Include churn metrics and the hiring plan.',
    priority: 3,
    due: testDateOnlyDueFromMillis(upcoming),
  );

  final groceries = await fake.createTask(
    listId: homeListId,
    title: '買い物リストを整理する',
  );
  await fake.updateTask(
    taskId: groceries.id,
    title: groceries.title,
    note: '',
    priority: 1,
  );

  final planning = await fake.createTask(
    listId: homeListId,
    title: 'Plan July archive review',
  );
  await fake.updateTask(
    taskId: planning.id,
    title: planning.title,
    note: '',
    priority: 1,
    due: testDateOnlyDueFromMillis(upcoming),
  );

  final passport = await fake.createTask(
    listId: homeListId,
    title: 'Renew passport before the trip',
  );
  await fake.updateTask(
    taskId: passport.id,
    title: passport.title,
    note: '',
    priority: 0,
    due: testDateOnlyDueFromMillis(overdue),
  );

  final standup = await fake.createTask(listId: homeListId, title: '朝会に参加する');
  await fake.updateTask(
    taskId: standup.id,
    title: standup.title,
    note: '',
    priority: 0,
    due: testDateOnlyDueFromMillis(today),
  );
  await fake.setTaskStatus(taskId: standup.id, status: 'done');

  final skipped = await fake.createTask(
    listId: homeListId,
    title: 'Replace the planning spreadsheet',
  );
  await fake.updateTask(
    taskId: skipped.id,
    title: skipped.title,
    note: '',
    priority: 0,
  );
  await fake.setTaskStatus(taskId: skipped.id, status: 'wont_do');

  final workReview = await fake.createTask(
    listId: workListId,
    title: '四半期レビュー資料を作成する',
  );
  await fake.updateTask(
    taskId: workReview.id,
    title: workReview.title,
    note: '',
    priority: 3,
    due: testDateOnlyDueFromMillis(today),
  );

  final template = await fake.saveTaskAsTemplate(
    taskId: launch.id,
    name: 'Weekly launch review',
    defaultListId: homeListId,
  );
  await fake.createSchedule(
    templateId: template.id,
    rrule: 'FREQ=WEEKLY',
    startsAt: DateTime(now.year, now.month, now.day, 9).millisecondsSinceEpoch,
    timeZone: 'Asia/Tokyo',
  );

  return DesignLabFixture(
    fake: fake,
    homeListId: homeListId,
    parentWithSubtasksTitle: parentWithSubtasksTitle,
    parentWithSubtasksId: launch.id,
    visibleRootTaskId: uiTweaks.id,
    focusTaskId: uiTweaks.id,
    templateId: template.id,
  );
}
