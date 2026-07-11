import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/ui/theme.dart';

part 'design_lab_task_create_sheet_mock.dart';
part 'design_lab_task_detail_mock.dart';
part 'design_lab_product_direction_mock.dart';
part 'design_lab_product_system_mock.dart';
part 'design_lab_radical_direction_mock.dart';
part 'design_lab_interactive.dart';
part 'design_lab_production_coverage.dart';
part 'design_lab_support_mocks.dart';

enum DesignLabMock {
  taskList,
  calendar,
  listOverview,
  focusTimer,
  taskDetail,
  taskCreateSheet,
  search,
  settings,
  timerSetup,
  listTasks,
  taskDetailEditing,
  accountSignedOut,
  taskActions,
  dueDateSheet,
  systemStates,
  onboarding,
}

class DesignLabMockApp extends StatelessWidget {
  const DesignLabMockApp({required this.mock, super.key});

  final DesignLabMock mock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTodoriTheme(Brightness.light),
      home: switch (mock) {
        DesignLabMock.taskList => _RadicalHomeMock(onTaskFocus: () {}),
        DesignLabMock.calendar => _InteractiveCalendarMock(onTaskFocus: () {}),
        DesignLabMock.listOverview => const _RadicalListsMock(),
        DesignLabMock.focusTimer => const _RadicalFocusMock(),
        DesignLabMock.taskDetail => const _RadicalDetailMock(),
        DesignLabMock.taskCreateSheet => const _RadicalCreateMock(),
        DesignLabMock.search => const _RadicalSearchMock(),
        DesignLabMock.settings => const _RadicalAccountMock(),
        DesignLabMock.timerSetup => const _RadicalFocusSetupMock(),
        DesignLabMock.listTasks => _RadicalListTasksMock(onTaskFocus: () {}),
        DesignLabMock.taskDetailEditing => const _RadicalTaskEditMock(),
        DesignLabMock.accountSignedOut => const _RadicalAccountAccessMock(),
        DesignLabMock.taskActions => const _RadicalActionSheetMock(),
        DesignLabMock.dueDateSheet => const _RadicalDueDateSheetMock(),
        DesignLabMock.systemStates => const _RadicalSystemStatesMock(),
        DesignLabMock.onboarding => _RadicalOnboardingMock(onContinue: () {}),
      },
    );
  }
}

/// Typography variants explored by the `design_lab_typo_*` screenshots (see
/// `docs/design/ui-spec.md` セクション6 note on Newsreader / タイポグラフィ比較).
///
/// Each variant only changes font family / weight / letter-spacing (and, for
/// `jaMincho`, the heading copy); layout, spacing, colors, and every other
/// mock stay identical across variants so the four screenshots are a fair
/// side-by-side comparison of typography alone.
enum DesignLabTypoVariant { newsreaderA, loraB, sansOnlyC, jaMinchoD }

/// The two screens reused for the typography comparison: the Today task
/// list (`_TaskListMock`) and the running Focus timer (`_FocusTimerMock`).
enum DesignLabTypoScreen { today, focus }

/// Renders one (variant, screen) pair of the typography comparison using the
/// existing Today task list / Focus timer mocks with [_LabTypography]
/// injected.
class DesignLabTypoMockApp extends StatelessWidget {
  const DesignLabTypoMockApp({
    required this.variant,
    required this.screen,
    super.key,
  });

  final DesignLabTypoVariant variant;
  final DesignLabTypoScreen screen;

  @override
  Widget build(BuildContext context) {
    final typography = _typographyFor(variant);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTodoriTheme(Brightness.light),
      home: switch (screen) {
        DesignLabTypoScreen.today => _TaskListMock(typography: typography),
        DesignLabTypoScreen.focus => _FocusTimerMock(typography: typography),
      },
    );
  }
}

/// A single role's font-family/weight/letter-spacing override, applied on
/// top of a base [TextTheme] style via [apply]. Every field is explicit
/// (rather than nullable-and-inherited) because `buildTodoriTheme` already
/// bakes Newsreader into `displayMedium` (the Today heading); an explicit
/// family here is required so every variant -- including 案A, which shares
/// production's Newsreader-scoped-to-heading direction but is not
/// byte-identical to it (see [_typoNewsreaderA]) -- renders each role
/// deliberately rather than inheriting that default.
class _LabTypoOverride {
  const _LabTypoOverride({
    required this.fontFamily,
    required this.fontWeight,
    this.letterSpacing,
  });

  final String fontFamily;
  final FontWeight fontWeight;
  final double? letterSpacing;

  TextStyle apply(TextStyle base) => base.copyWith(
    fontFamily: fontFamily,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
  );
}

/// Typography configuration threaded through `_TaskListMock` /
/// `_FocusTimerMock` so the same layout can be screenshotted under several
/// font choices. [_typoLegacyDefault] reproduces the mocks' original,
/// hardcoded-Newsreader-everywhere styling so existing `design_lab_task_list`
/// / `design_lab_focus_timer` screenshots stay pixel-identical.
class _LabTypography {
  const _LabTypography({
    required this.todayHeading,
    required this.tasksHeadline,
    required this.focusTitle,
    required this.timerDigit,
    required this.focusCardTitle,
    this.todayHeadingText = 'Today',
    this.focusTitleText = 'Focus',
    this.focusCardTitleText = 'Review design direction',
    this.taskTitles,
  });

  /// The "Today" home header (`displayMedium`, 48px) -- always serif when a
  /// variant has any serif at all.
  final _LabTypoOverride todayHeading;

  /// The "Tasks" section headline inside `_TasksPanel` (`headlineSmall`,
  /// 22px).
  final _LabTypoOverride tasksHeadline;

  /// The Focus screen's title-bar text (`titleLarge`).
  final _LabTypoOverride focusTitle;

  /// The running timer's large digit readout (`displayLarge`, 64px) --
  /// always serif when a variant has any serif at all.
  final _LabTypoOverride timerDigit;

  /// The selected task's title on the Focus screen's task card
  /// (`headlineSmall`) -- a "card内タスクタイトル", always Inter per
  /// `docs/design/ui-spec.md` セクション2 タイポグラフィ表.
  final _LabTypoOverride focusCardTitle;

  final String todayHeadingText;
  final String focusTitleText;
  final String focusCardTitleText;

  /// Overrides for `_tasks`' titles, in the same order, used by the
  /// `jaMincho` variant to show Japanese task titles. `null` keeps the
  /// original English/Japanese-mixed titles.
  final List<String>? taskTitles;
}

const _typoLegacyDefault = _LabTypography(
  todayHeading: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
  tasksHeadline: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
  focusTitle: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
  timerDigit: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
  focusCardTitle: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
);

/// A案: serif (Newsreader) restricted to the Today heading and timer digit
/// only (both ≥28px, at most 1-2 spots per screen); every other heading
/// (section headline, Focus title, card task title) is Inter.
const _typoNewsreaderA = _LabTypography(
  todayHeading: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
  tasksHeadline: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
  ),
  focusTitle: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
  ),
  timerDigit: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
  focusCardTitle: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w600,
  ),
);

/// B案: the pre-2026-07-06 production typography, where Lora reached the
/// AppBar/section headings too. Decommissioned from the shipped app by
/// task-34; kept here only as a comparison baseline against 案A (the
/// direction that replaced it).
const _typoLoraB = _LabTypography(
  todayHeading: _LabTypoOverride(
    fontFamily: 'Lora',
    fontWeight: FontWeight.w600,
  ),
  tasksHeadline: _LabTypoOverride(
    fontFamily: 'Lora',
    fontWeight: FontWeight.w700,
  ),
  focusTitle: _LabTypoOverride(fontFamily: 'Lora', fontWeight: FontWeight.w700),
  timerDigit: _LabTypoOverride(fontFamily: 'Lora', fontWeight: FontWeight.w600),
  focusCardTitle: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w600,
  ),
);

/// C案: no serif anywhere. Hierarchy comes from weight/letter-spacing only.
const _typoSansOnlyC = _LabTypography(
  todayHeading: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  ),
  tasksHeadline: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
  ),
  focusTitle: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
  ),
  timerDigit: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
  ),
  focusCardTitle: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w600,
  ),
);

/// D案: same serif range as A案 (Today heading + timer digit only), but the
/// Today heading's Japanese copy renders in Zen Old Mincho (see
/// `tool/fetch_lab_fonts.sh`) and the other headings/task titles switch to
/// Japanese copy rendered in Inter (+ CJK fallback).
const _typoJaMinchoD = _LabTypography(
  todayHeading: _LabTypoOverride(
    fontFamily: 'ZenOldMincho',
    fontWeight: FontWeight.w600,
  ),
  tasksHeadline: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
  ),
  focusTitle: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
  ),
  timerDigit: _LabTypoOverride(
    fontFamily: 'Newsreader',
    fontWeight: FontWeight.w400,
  ),
  focusCardTitle: _LabTypoOverride(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w600,
  ),
  todayHeadingText: '今日',
  focusTitleText: 'フォーカス',
  focusCardTitleText: 'デザイン方向性をレビュー',
  taskTitles: [
    'デザイン方向性をレビュー',
    '復元フローの下書きを作成',
    'リリースノートを書く',
    '買い物リストの計画を立てる',
    '完了メモをアーカイブ',
  ],
);

_LabTypography _typographyFor(DesignLabTypoVariant variant) =>
    switch (variant) {
      DesignLabTypoVariant.newsreaderA => _typoNewsreaderA,
      DesignLabTypoVariant.loraB => _typoLoraB,
      DesignLabTypoVariant.sansOnlyC => _typoSansOnlyC,
      DesignLabTypoVariant.jaMinchoD => _typoJaMinchoD,
    };

class _LabTask {
  const _LabTask({
    required this.title,
    required this.dueLabel,
    required this.accent,
    this.subtasks = const [],
    this.contextLabel,
    this.isSelected = false,
    this.isDone = false,
  });

  final String title;
  final String dueLabel;
  final Color accent;
  final List<_LabSubtask> subtasks;
  final String? contextLabel;
  final bool isSelected;
  final bool isDone;

  _LabTask withTitle(String title) => _LabTask(
    title: title,
    dueLabel: dueLabel,
    accent: accent,
    subtasks: subtasks,
    contextLabel: contextLabel,
    isSelected: isSelected,
    isDone: isDone,
  );
}

class _LabSubtask {
  const _LabSubtask({
    required this.title,
    required this.dueLabel,
    this.contextLabel,
    this.isDone = false,
  });

  final String title;
  final String dueLabel;
  final String? contextLabel;
  final bool isDone;
}

const _tasks = [
  _LabTask(
    title: 'Review design direction',
    dueLabel: 'Today',
    accent: _priorityCoral,
    contextLabel: 'Design',
    isSelected: true,
    subtasks: [
      _LabSubtask(title: 'Collect references', dueLabel: 'Today', isDone: true),
      _LabSubtask(title: 'Define key screens', dueLabel: 'Today'),
      _LabSubtask(
        title: 'Align on visual rules',
        dueLabel: 'Tomorrow',
        contextLabel: 'UI',
      ),
    ],
  ),
  _LabTask(
    title: 'Draft restore flow',
    dueLabel: 'Today',
    accent: _priorityAmber,
    contextLabel: 'Product',
  ),
  _LabTask(
    title: 'Write release notes',
    dueLabel: 'Sat, Jul 11',
    accent: _priorityBlue,
    contextLabel: 'Docs',
  ),
  _LabTask(
    title: 'Plan grocery run',
    dueLabel: 'Sun, Jul 12',
    accent: _prioritySage,
    contextLabel: 'Personal',
  ),
  _LabTask(
    title: 'Archive finished notes',
    dueLabel: 'Completed',
    accent: _priorityGreen,
    isDone: true,
  ),
];

class _LabList {
  const _LabList({
    required this.label,
    required this.count,
    required this.accent,
    this.icon,
    this.isSelected = false,
  });

  final String label;
  final int count;
  final Color accent;
  final IconData? icon;
  final bool isSelected;
}

const _smartLists = [
  _LabList(
    label: 'Today',
    count: 8,
    accent: _priorityAmber,
    icon: LucideIcons.sun300,
  ),
  _LabList(label: 'Inbox', count: 3, accent: _prioritySage),
  _LabList(label: 'Upcoming', count: 5, accent: _priorityAmber),
  _LabList(label: 'Someday', count: 12, accent: Color(0xFF8F82C8)),
];

const _customLists = [
  _LabList(label: 'Design', count: 7, accent: _priorityGreen, isSelected: true),
  _LabList(label: 'Personal', count: 6, accent: Color(0xFF3C8DCE)),
  _LabList(label: 'Work', count: 9, accent: Color(0xFFF18A3A)),
  _LabList(label: 'Health', count: 4, accent: Color(0xFF66AA53)),
  _LabList(label: 'Learning', count: 3, accent: Color(0xFFE95A8A)),
];

const _labPageIvory = Color(0xFFFAF8F2);
const _labSurfaceWarm = Color(0xFFFEFDFB);
const _labSoftIvory = Color(0xFFF6F6EF);
const _taskPanelPadding = EdgeInsets.fromLTRB(
  AppSpacing.sm,
  AppSpacing.lg,
  AppSpacing.sm,
  AppSpacing.md,
);
const _taskCardPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
const _taskHeaderActionsPadding = EdgeInsets.symmetric(horizontal: 12);
const _taskHeaderPadding = EdgeInsets.symmetric(horizontal: 12);
const _taskTagPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 2);
const _taskPanelRadius = 20.0;
const _taskCardGap = 2.0;
const _taskBlockGap = AppSpacing.sm;
const _taskInlineGap = AppSpacing.sm;
const _taskMicroGap = AppSpacing.xs;
const _taskCheckTopOffset = 10.0;
const _taskPlayTopOffset = 2.0;
const _taskPriorityDotSize = 7.0;
const _taskControlStrokeWidth = 0.65;
const _subtaskLineWidth = _taskCheckSize + _taskInlineGap;
const _subtaskControlSize = 20.0;
const _subtaskPlaySize = 36.0;
const _subtaskConnectorHeight = _taskBlockGap;
const _subtaskTitleFontSize = 15.5;
const _subtaskTitleLineHeight = 1.18;
const _subtaskTagHeight = 18.0;
const _subtaskContentHeight =
    _subtaskTitleFontSize * _subtaskTitleLineHeight +
    _taskMicroGap +
    _subtaskTagHeight;
const _subtaskControlCenterY = _subtaskContentHeight / 2;
const _subtaskRowHeight = _subtaskContentHeight;
const _taskCheckSize = _subtaskControlSize;
const _taskCheckIconSize = 12.0;

class _TaskListMock extends StatelessWidget {
  const _TaskListMock({this.typography = _typoLegacyDefault});

  final _LabTypography typography;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tasks = typography.taskTitles == null
        ? _tasks
        : [
            for (var i = 0; i < _tasks.length; i += 1)
              _tasks[i].withTitle(typography.taskTitles![i]),
          ];
    return Scaffold(
      backgroundColor: _labPageIvory,
      floatingActionButton: const _AddTaskButton(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.sm,
            0,
            AppSpacing.xl * 3,
          ),
          children: [
            const Padding(
              padding: _taskHeaderActionsPadding,
              child: _TaskHeaderActions(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                typography.todayHeadingText,
                style: typography.todayHeading
                    .apply(theme.textTheme.displayMedium!)
                    .copyWith(
                      color: colorScheme.primary,
                      fontSize: 48,
                      height: 0.96,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Mon, Jul 6',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _TasksPanel(tasks: tasks, typography: typography),
            const SizedBox(height: AppSpacing.md),
            const _CompletedTodayRow(count: 1),
          ],
        ),
      ),
    );
  }
}

class _TaskHeaderActions extends StatelessWidget {
  const _TaskHeaderActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _QuietIconButton(icon: LucideIcons.menu300),
        Spacer(),
        _QuietIconButton(icon: LucideIcons.slidersHorizontal300),
        SizedBox(width: AppSpacing.sm),
        _QuietIconButton(icon: LucideIcons.moreHorizontal300),
      ],
    );
  }
}

class _TasksPanel extends StatelessWidget {
  const _TasksPanel({
    required this.tasks,
    this.typography = _typoLegacyDefault,
  });

  final List<_LabTask> tasks;
  final _LabTypography typography;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final openTasks = tasks.where((task) => !task.isDone).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(_taskPanelRadius),
        border: Border.symmetric(
          horizontal: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
      ),
      child: Padding(
        padding: _taskPanelPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _taskHeaderPadding,
              child: Row(
                children: [
                  Text(
                    'Tasks',
                    style: typography.tasksHeadline
                        .apply(theme.textTheme.headlineSmall!)
                        .copyWith(color: colorScheme.primary, fontSize: 22),
                  ),
                  const Spacer(),
                  _SmallPill(label: '${openTasks.length} pending'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var index = 0; index < openTasks.length; index += 1) ...[
              _TaskCard(task: openTasks[index]),
              if (index < openTasks.length - 1)
                const SizedBox(height: _taskCardGap),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final _LabTask task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: task.isSelected
            ? _labSoftIvory.withValues(alpha: 0.58)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: task.isSelected
              ? colorScheme.primary.withValues(alpha: 0.18)
              : colorScheme.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      child: Padding(
        padding: _taskCardPadding,
        child: Column(
          children: [
            _TaskRow(task: task),
            if (task.subtasks.isNotEmpty) ...[
              _SubtaskTree(subtasks: task.subtasks),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final _LabTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _taskCheckTopOffset),
          child: _CheckCircle(
            isDone: task.isDone,
            dimension: _taskCheckSize,
            checkSize: _taskCheckIconSize,
          ),
        ),
        const SizedBox(width: _taskInlineGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: task.isDone
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.62)
                      : colorScheme.onSurface.withValues(alpha: 0.74),
                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w300,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: _taskMicroGap),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: _taskMicroGap,
                runSpacing: _taskMicroGap,
                children: [
                  _PriorityMark(color: task.accent, size: _taskPriorityDotSize),
                  _TaskTagPill(label: task.dueLabel),
                  if (task.contextLabel != null)
                    _TaskTagPill(label: task.contextLabel!),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: _taskInlineGap),
        Padding(
          padding: const EdgeInsets.only(top: _taskPlayTopOffset),
          child: _PlayButton(active: task.isSelected),
        ),
      ],
    );
  }
}

class _SubtaskTree extends StatelessWidget {
  const _SubtaskTree({required this.subtasks});

  final List<_LabSubtask> subtasks;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _subtaskConnectorHeight + _subtaskRowHeight * subtasks.length,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SubtaskTreePainter(
                color: colorScheme.primary.withValues(alpha: 0.36),
                count: subtasks.length,
              ),
            ),
          ),
          Positioned(
            top: _subtaskConnectorHeight,
            left: 0,
            right: 0,
            child: Column(
              children: [
                for (final subtask in subtasks)
                  SizedBox(
                    height: _subtaskRowHeight,
                    child: _SubtaskRow(subtask: subtask),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({required this.subtask});

  final _LabSubtask subtask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = subtask.isDone
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.48)
        : colorScheme.onSurface.withValues(alpha: 0.7);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: _subtaskLineWidth),
        SizedBox(
          height: _subtaskContentHeight,
          child: Center(
            child: _CheckCircle(
              isDone: subtask.isDone,
              dimension: _subtaskControlSize,
              checkSize: 12,
            ),
          ),
        ),
        const SizedBox(width: _taskInlineGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtask.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  decoration: subtask.isDone
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: textColor,
                  fontSize: _subtaskTitleFontSize,
                  fontWeight: FontWeight.w300,
                  height: _subtaskTitleLineHeight,
                ),
              ),
              const SizedBox(height: _taskMicroGap),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: _taskMicroGap,
                runSpacing: _taskMicroGap,
                children: [
                  _TaskTagPill(label: subtask.dueLabel),
                  if (subtask.contextLabel != null)
                    _TaskTagPill(label: subtask.contextLabel!),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: _taskInlineGap),
        SizedBox(
          height: _subtaskContentHeight,
          child: Center(
            child: _PlayButton(active: false, dimension: _subtaskPlaySize),
          ),
        ),
      ],
    );
  }
}

class _SubtaskTreePainter extends CustomPainter {
  const _SubtaskTreePainter({required this.color, required this.count});

  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) {
      return;
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = _taskControlStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = _taskCheckSize / 2;
    final firstY = _subtaskConnectorHeight + _subtaskControlCenterY;
    final lastY = (count - 1) * _subtaskRowHeight + firstY;
    canvas.drawLine(Offset(x, 0), Offset(x, lastY), paint);
    for (var index = 0; index < count; index += 1) {
      final y = index * _subtaskRowHeight + firstY;
      canvas.drawLine(
        Offset(x, y),
        Offset(_subtaskLineWidth - _taskMicroGap, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SubtaskTreePainter oldDelegate) {
    return color != oldDelegate.color || count != oldDelegate.count;
  }
}

class _FocusTimerMock extends StatelessWidget {
  const _FocusTimerMock({this.typography = _typoLegacyDefault});

  final _LabTypography typography;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: _labPageIvory,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                const _QuietIconButton(icon: LucideIcons.arrowLeft300),
                Expanded(
                  child: Center(
                    child: Text(
                      typography.focusTitleText,
                      style: typography.focusTitle
                          .apply(theme.textTheme.titleLarge!)
                          .copyWith(color: colorScheme.primary),
                    ),
                  ),
                ),
                const _QuietIconButton(icon: LucideIcons.moreHorizontal300),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _FocusTimerRing(typography: typography),
            const SizedBox(height: AppSpacing.lg),
            _FocusTaskCard(typography: typography),
            const SizedBox(height: AppSpacing.md),
            const _FocusActionRow(),
          ],
        ),
      ),
    );
  }
}

class _FocusTimerRing extends StatelessWidget {
  const _FocusTimerRing({this.typography = _typoLegacyDefault});

  final _LabTypography typography;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: SizedBox.square(
        dimension: 292,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              painter: _FocusRingPainter(
                trackColor: colorScheme.primary.withValues(alpha: 0.16),
                progressColor: colorScheme.primary.withValues(alpha: 0.88),
                progress: 0.82,
              ),
              child: const SizedBox.expand(),
            ),
            Positioned(
              top: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _labSurfaceWarm,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.primary, width: 4),
                ),
                child: const SizedBox.square(dimension: 22),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.leaf300,
                  color: colorScheme.primary.withValues(alpha: 0.82),
                  size: 28,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Focus time',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '24:30',
                  style: typography.timerDigit
                      .apply(theme.textTheme.displayLarge!)
                      .copyWith(
                        color: colorScheme.primary,
                        fontSize: 64,
                        height: 0.95,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '/ 25:00',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _FocusSessionPill(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({
    required this.trackColor,
    required this.progressColor,
    required this.progress,
  });

  final Color trackColor;
  final Color progressColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ringRect = rect.deflate(10);
    final strokeWidth = 9.0;
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(ringRect, -math.pi / 2, math.pi * 2, false, trackPaint);
    canvas.drawArc(
      ringRect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) {
    return trackColor != oldDelegate.trackColor ||
        progressColor != oldDelegate.progressColor ||
        progress != oldDelegate.progress;
  }
}

class _FocusSessionPill extends StatelessWidget {
  const _FocusSessionPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.sprout300,
              size: 16,
              color: colorScheme.primary.withValues(alpha: 0.72),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Session 1 of 4',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusTaskCard extends StatelessWidget {
  const _FocusTaskCard({this.typography = _typoLegacyDefault});

  final _LabTypography typography;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          children: [
            Text(
              typography.focusCardTitleText,
              textAlign: TextAlign.center,
              style: typography.focusCardTitle
                  .apply(theme.textTheme.headlineSmall!)
                  .copyWith(color: colorScheme.primary, height: 1.08),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: const [
                _TaskTagPill(label: 'Design'),
                _TaskTagPill(label: 'Timer 25m'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusActionRow extends StatelessWidget {
  const _FocusActionRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(LucideIcons.pause300),
            label: const Text('Pause'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              minimumSize: const Size.fromHeight(54),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.72),
              ),
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(LucideIcons.stopCircle300),
            label: const Text('Finish'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              minimumSize: const Size.fromHeight(54),
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTaskButton extends StatelessWidget {
  const _AddTaskButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return FilledButton.icon(
      onPressed: () {},
      icon: const Icon(LucideIcons.plus300),
      label: const Text('Add task'),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary.withValues(alpha: 0.94),
        foregroundColor: colorScheme.onPrimary,
        minimumSize: const Size(138, 46),
        textStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _CompletedTodayRow extends StatelessWidget {
  const _CompletedTodayRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: () {},
        icon: Icon(
          LucideIcons.chevronDown300,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.48),
          size: 18,
        ),
        label: Text(
          'Completed today  $count',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.54),
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// Retained for the legacy comparison while the unified system is reviewed.
// ignore: unused_element
class _ListOverviewMock extends StatelessWidget {
  const _ListOverviewMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: _labPageIvory,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.lg,
            0,
            AppSpacing.xl,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Lists',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontFamily: 'Newsreader',
                        color: colorScheme.primary,
                        fontSize: 48,
                        fontWeight: FontWeight.w400,
                        height: 0.96,
                      ),
                    ),
                  ),
                  const _ListHeaderIconButton(icon: LucideIcons.search300),
                  const SizedBox(width: AppSpacing.sm),
                  const _ListHeaderIconButton(
                    icon: LucideIcons.moreHorizontal300,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ListOverviewPanel(
              smartLists: _smartLists,
              customLists: _customLists,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListOverviewPanel extends StatelessWidget {
  const _ListOverviewPanel({
    required this.smartLists,
    required this.customLists,
  });

  final List<_LabList> smartLists;
  final List<_LabList> customLists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(_taskPanelRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.78),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ListSectionLabel(
              label: 'Smart Lists',
              trailing: Text(
                '28',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final list in smartLists)
              _OverviewListRow(list: list, iconMode: _ListIconMode.symbol),
            Divider(
              height: AppSpacing.lg,
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
            const _ListSectionLabel(
              label: 'Custom Lists',
              trailing: Icon(LucideIcons.chevronDown300, size: 28),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final list in customLists)
              _OverviewListRow(list: list, iconMode: _ListIconMode.dot),
            Divider(
              height: AppSpacing.lg,
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
            const _NewListRow(),
          ],
        ),
      ),
    );
  }
}

class _ListSectionLabel extends StatelessWidget {
  const _ListSectionLabel({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'Newsreader',
                color: colorScheme.primary,
                fontSize: 22,
                fontWeight: FontWeight.w400,
                height: 1.05,
              ),
            ),
          ),
          IconTheme(
            data: IconThemeData(color: colorScheme.primary),
            child: trailing,
          ),
        ],
      ),
    );
  }
}

enum _ListIconMode { symbol, dot }

class _OverviewListRow extends StatelessWidget {
  const _OverviewListRow({required this.list, required this.iconMode});

  final _LabList list;
  final _ListIconMode iconMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = list.isSelected
        ? colorScheme.primaryContainer.withValues(alpha: 0.42)
        : Colors.transparent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            _ListMark(list: list, mode: iconMode),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                list.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.94),
                  fontWeight: list.isSelected
                      ? FontWeight.w500
                      : FontWeight.w400,
                  height: 1.1,
                ),
              ),
            ),
            _ListCountBadge(count: list.count),
            if (list.isSelected) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                LucideIcons.moreHorizontal300,
                color: colorScheme.primary.withValues(alpha: 0.86),
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListMark extends StatelessWidget {
  const _ListMark({required this.list, required this.mode});

  final _LabList list;
  final _ListIconMode mode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox.square(
        dimension: 48,
        child: Center(
          child: switch (mode) {
            _ListIconMode.symbol when list.icon != null => Icon(
              list.icon,
              color: list.accent,
              size: 24,
            ),
            _ListIconMode.symbol => _ListDot(accent: list.accent),
            _ListIconMode.dot => _ListDot(accent: list.accent),
          },
        ),
      ),
    );
  }
}

class _ListHeaderIconButton extends StatelessWidget {
  const _ListHeaderIconButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: () {},
      icon: Icon(icon, size: 27),
      color: colorScheme.primary.withValues(alpha: 0.88),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _QuietIconButton extends StatelessWidget {
  const _QuietIconButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: () {},
      icon: Icon(icon, size: 27),
      color: colorScheme.primary.withValues(alpha: 0.88),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({
    this.isDone = false,
    this.dimension = 30,
    this.checkSize = 16,
  });

  final bool isDone;
  final double dimension;
  final double checkSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDone ? colorScheme.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: isDone ? 0.88 : 0.72),
          width: _taskControlStrokeWidth,
        ),
      ),
      child: SizedBox.square(
        dimension: dimension,
        child: isDone
            ? Icon(
                LucideIcons.check300,
                color: colorScheme.onPrimary,
                size: checkSize,
              )
            : null,
      ),
    );
  }
}

class _PriorityMark extends StatelessWidget {
  const _PriorityMark({required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.active, this.dimension = 36});

  final bool active;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? colorScheme.primary.withValues(alpha: 0.92)
            : _labSurfaceWarm.withValues(alpha: 0.72),
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: active ? 0.92 : 0.72),
          width: _taskControlStrokeWidth,
        ),
      ),
      child: SizedBox.square(
        dimension: dimension,
        child: IconButton(
          onPressed: () {},
          padding: EdgeInsets.zero,
          icon: Icon(
            Icons.play_arrow_rounded,
            color: active
                ? colorScheme.onPrimary
                : colorScheme.primary.withValues(alpha: 0.92),
            size: 27,
          ),
          style: IconButton.styleFrom(
            minimumSize: Size(dimension, dimension),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TaskTagPill extends StatelessWidget {
  const _TaskTagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.26),
        ),
      ),
      child: Padding(
        padding: _taskTagPadding,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.primary.withValues(alpha: 0.82),
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
            height: 1.12,
          ),
        ),
      ),
    );
  }
}

class _ListDot extends StatelessWidget {
  const _ListDot({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 16),
    );
  }
}

class _ListCountBadge extends StatelessWidget {
  const _ListCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(
        width: 44,
        height: 36,
        child: Center(
          child: Text(
            '$count',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.9),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewListRow extends StatelessWidget {
  const _NewListRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _labSoftIvory.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Icon(LucideIcons.plus300, color: colorScheme.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'New list',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.94),
                fontWeight: FontWeight.w400,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _priorityGreen = Color(0xFF2F6F4E);
const _prioritySage = Color(0xFFA9BFAE);
const _priorityAmber = Color(0xFFF0B83F);
const _priorityCoral = Color(0xFFE8755A);
const _priorityBlue = Color(0xFF3D7FDB);
