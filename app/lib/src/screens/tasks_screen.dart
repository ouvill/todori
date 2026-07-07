import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/core/task_tree.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/dialogs.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/task_components.dart';
import 'package:todori/src/ui/theme.dart';

/// The task list screen for a single list (route
/// `/lists/:listId/tasks`).
///
/// F-02 "シンプルUI" skeleton: shows active tasks with a checkbox to mark
/// them done and a FAB to create a new one. Tapping a task navigates to its
/// detail screen.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({
    super.key,
    required this.listId,
    this.listName,
    this.isHome = false,
  }) : isTodaySmartView = false;

  const TasksScreen.today({super.key})
    : listId = '_today',
      listName = null,
      isHome = true,
      isTodaySmartView = true;

  final String listId;
  final String? listName;
  final bool isHome;
  final bool isTodaySmartView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final AsyncValue<List<TaskDto>> tasksAsync;
    final Map<String, String> homeListNameByTaskId;
    final List<HomeTaskDto> homeTaskEntries;
    if (isTodaySmartView) {
      final homeTasksAsync = ref.watch(homeTasksProvider);
      homeTaskEntries = homeTasksAsync.value ?? const <HomeTaskDto>[];
      homeListNameByTaskId = {
        for (final homeTask in homeTaskEntries)
          homeTask.task.id: homeTask.listName,
      };
      tasksAsync = homeTasksAsync.whenData(
        (homeTasks) =>
            homeTasks.map((homeTask) => homeTask.task).toList(growable: false),
      );
    } else {
      homeTaskEntries = const <HomeTaskDto>[];
      homeListNameByTaskId = const {};
      tasksAsync = ref.watch(tasksProvider(listId));
    }
    final listsAsync = ref.watch(listsProvider);
    final archivedListsAsync = ref.watch(archivedListsProvider);
    final sortMode = ref.watch(taskSortModeProvider(listId));
    final effectiveSortMode =
        isTodaySmartView && sortMode == TaskSortMode.manual
        ? TaskSortMode.dueDate
        : sortMode;
    final activeLists = listsAsync.value;
    final archivedLists = archivedListsAsync.value;
    final currentList =
        _findList(listId, activeLists) ?? _findList(listId, archivedLists);
    final defaultList = activeLists == null
        ? null
        : _findDefaultList(activeLists);
    final createListOptions = _mergeListOptions(activeLists, archivedLists);
    final createInitialListId = isTodaySmartView
        ? defaultList?.id
        : currentList?.id;
    final createInitialDueAt = isTodaySmartView
        ? homeLocalRangesMs().todayStartMs
        : null;
    final isDefaultInbox =
        currentList?.archivedAt == null && currentList?.isDefault == true;

    final sortMenu = _TaskSortMenu(
      selectedMode: effectiveSortMode,
      availableModes: isTodaySmartView
          ? const [
              TaskSortMode.dueDate,
              TaskSortMode.priority,
              TaskSortMode.createdAt,
            ]
          : TaskSortMode.values,
      onSelected: (mode) {
        ref.read(taskSortModeProvider(listId).notifier).setMode(mode);
      },
    );
    final listActionsMenu = isTodaySmartView || currentList == null
        ? null
        : _ListActionsMenu(
            list: currentList,
            isDefaultInbox: isDefaultInbox,
            onRename: () => _renameList(context, ref, currentList),
            onArchive: () => _archiveList(ref, currentList),
            onUnarchive: () => _unarchiveList(ref, currentList),
            onDelete: () => _deleteList(context, ref, currentList),
          );

    return Scaffold(
      appBar: isHome
          ? null
          : AppBar(
              title: Text(l10n.tasksTitle),
              actions: [
                ?listActionsMenu,
                sortMenu,
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
      body: tasksAsync.when(
        loading: () => const AppLoadingState(),
        error: (error, stackTrace) =>
            AppErrorState(message: l10n.failedToLoadTasks(error.toString())),
        data: (tasks) {
          return _TasksBody(
            listId: listId,
            listName: listName,
            isHome: isHome,
            isTodaySmartView: isTodaySmartView,
            tasks: tasks,
            sortMode: effectiveSortMode,
            sortMenu: sortMenu,
            listActionsMenu: listActionsMenu,
            homeListNameByTaskId: homeListNameByTaskId,
            homeTaskEntries: homeTaskEntries,
            onCompleteTask: (task) => _completeTask(context, ref, task, tasks),
            onReopenTask: (task) => _reopenTask(ref, task),
            onChangeDueDate: (task, dueAt) => _changeDueDate(ref, task, dueAt),
            onMoveTask: ({required task, previousTaskId, nextTaskId}) {
              return ref
                  .read(tasksProvider(listId).notifier)
                  .reorderTask(
                    taskId: task.id,
                    previousTaskId: previousTaskId,
                    nextTaskId: nextTaskId,
                  );
            },
          );
        },
      ),
      bottomNavigationBar: QuickAddBar(
        listOptions: createListOptions,
        initialListId: createInitialListId,
        initialDueAt: createInitialDueAt,
        errorMessage: l10n.quickAddCreateError,
        onCreate:
            ({
              required listId,
              required title,
              required note,
              required dueAt,
            }) => _createTask(
              ref,
              listId: listId,
              title: title,
              note: note,
              dueAt: dueAt,
            ),
      ),
    );
  }

  Future<void> _createTask(
    WidgetRef ref, {
    required String listId,
    required String title,
    required String note,
    required int? dueAt,
  }) async {
    if (isTodaySmartView) {
      await ref
          .read(homeTasksProvider.notifier)
          .createTask(listId: listId, title: title, note: note, dueAt: dueAt);
      return;
    }
    await ref
        .read(tasksProvider(listId).notifier)
        .createTask(title, note: note, dueAt: dueAt);
  }

  Future<bool> _completeTask(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
    List<TaskDto> tasks,
  ) async {
    final descendantScope = isTodaySmartView
        ? await ref.read(tasksProvider(task.listId).future)
        : tasks;
    if (!context.mounted) {
      return false;
    }
    if (hasIncompleteDescendants(task.id, descendantScope)) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: l10n.completeTaskDialogTitle,
        message: l10n.completeTaskDialogMessage,
        cancelLabel: l10n.cancelButton,
        confirmLabel: l10n.continueButton,
      );
      if (!confirmed) {
        return false;
      }
    }

    if (isTodaySmartView) {
      await ref.read(homeTasksProvider.notifier).setStatus(task.id, 'done');
    } else {
      await ref.read(tasksProvider(listId).notifier).setStatus(task.id, 'done');
    }
    if (!context.mounted) {
      return true;
    }
    await _showLatestUndoSnackBar(context);
    return true;
  }

  Future<void> _reopenTask(WidgetRef ref, TaskDto task) {
    if (isTodaySmartView) {
      return ref.read(homeTasksProvider.notifier).setStatus(task.id, 'todo');
    }
    return ref.read(tasksProvider(listId).notifier).setStatus(task.id, 'todo');
  }

  Future<void> _changeDueDate(WidgetRef ref, TaskDto task, int dueAt) {
    if (isTodaySmartView) {
      return ref.read(homeTasksProvider.notifier).updateDueDate(task, dueAt);
    }
    return ref
        .read(tasksProvider(task.listId).notifier)
        .updateDueDate(task, dueAt);
  }

  Future<void> _renameList(
    BuildContext context,
    WidgetRef ref,
    ListDto list,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showAppTextInputDialog(
      context: context,
      title: l10n.renameListTitle,
      label: l10n.nameLabel,
      cancelLabel: l10n.cancelButton,
      submitLabel: l10n.saveButton,
      initialValue: list.name,
    );
    final trimmedName = name?.trim();
    if (trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName == list.name) {
      return;
    }
    await ref.read(listsProvider.notifier).renameList(list.id, trimmedName);
  }

  Future<void> _archiveList(WidgetRef ref, ListDto list) {
    return ref.read(listsProvider.notifier).archiveList(list.id);
  }

  Future<void> _unarchiveList(WidgetRef ref, ListDto list) {
    return ref.read(archivedListsProvider.notifier).unarchiveList(list.id);
  }

  Future<void> _deleteList(
    BuildContext context,
    WidgetRef ref,
    ListDto list,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final taskCount = await ref
        .read(listsProvider.notifier)
        .countTasks(list.id);
    if (!context.mounted) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l10n.deleteListDialogTitle(list.name),
      message: l10n.deleteListDialogMessage(taskCount),
      cancelLabel: l10n.cancelButton,
      confirmLabel: l10n.deleteButton,
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(listsProvider.notifier).deleteList(list.id);
    if (!context.mounted) {
      return;
    }
    context.go('/lists');
  }
}

class _TasksBody extends StatefulWidget {
  const _TasksBody({
    required this.listId,
    required this.listName,
    required this.isHome,
    required this.isTodaySmartView,
    required this.tasks,
    required this.sortMode,
    required this.sortMenu,
    required this.listActionsMenu,
    required this.homeListNameByTaskId,
    required this.homeTaskEntries,
    required this.onCompleteTask,
    required this.onReopenTask,
    required this.onChangeDueDate,
    required this.onMoveTask,
  });

  final String listId;
  final String? listName;
  final bool isHome;
  final bool isTodaySmartView;
  final List<TaskDto> tasks;
  final TaskSortMode sortMode;
  final Widget sortMenu;
  final Widget? listActionsMenu;
  final Map<String, String> homeListNameByTaskId;
  final List<HomeTaskDto> homeTaskEntries;
  final Future<bool> Function(TaskDto task) onCompleteTask;
  final Future<void> Function(TaskDto task) onReopenTask;
  final Future<void> Function(TaskDto task, int dueAt) onChangeDueDate;
  final Future<void> Function({
    required TaskDto task,
    required String? previousTaskId,
    required String? nextTaskId,
  })
  onMoveTask;

  @override
  State<_TasksBody> createState() => _TasksBodyState();
}

class _TasksBodyState extends State<_TasksBody> {
  bool _showCompleted = false;
  final Set<_HomeSectionKind> _collapsedHomeSections = {};
  final Map<String, _PendingHomeCompletion> _pendingHomeCompletions = {};
  final Map<String, Timer> _pendingHomeCompletionTimers = {};
  final Map<String, Future<bool>> _homeCompletionOperations = {};
  final Set<String> _optimisticHomeCompletionIds = {};
  _TaskDropIndicator? _dropIndicator;

  @override
  void didUpdateWidget(covariant _TasksBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_showCompleted && !_hasClosedRoot(widget.tasks)) {
      _showCompleted = false;
    }
    _syncPendingHomeCompletionsWithWidget();
    _syncOptimisticHomeCompletionsWithWidget();
  }

  @override
  void dispose() {
    for (final timer in _pendingHomeCompletionTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.isHome) {
      final closedRows = _buildHomeClosedRows(context);
      final children = <Widget>[
        _HomeTasksHeader(
          sortMenu: widget.sortMenu,
          listActionsMenu: widget.listActionsMenu,
        ),
        const SizedBox(height: AppSpacing.md),
        _HomeSectionsPanel(
          sections: _buildHomeSections(context),
          collapsedSections: _collapsedHomeSections,
          onToggleSection: (section) {
            setState(() {
              if (!_collapsedHomeSections.add(section)) {
                _collapsedHomeSections.remove(section);
              }
            });
          },
        ),
        if (closedRows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _CompletedSectionHeader(
            count: closedRows.length,
            isExpanded: _showCompleted,
            onTap: () => setState(() => _showCompleted = !_showCompleted),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _showCompleted
                ? Column(
                    children: [
                      for (final row in closedRows) ...[
                        const SizedBox(height: AppSpacing.sm),
                        row,
                      ],
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ];
      return SafeArea(
        top: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xl * 3,
          ),
          children: children,
        ),
      );
    }

    final roots = buildTaskTree(widget.tasks, sortMode: widget.sortMode);
    final activeRoots = roots
        .where((node) => !isTaskClosed(node.task))
        .toList(growable: false);
    final completedRoots = roots
        .where((node) => isTaskClosed(node.task))
        .toList(growable: false);
    final activeNodes = flattenTaskTree(activeRoots);
    final completedNodes = flattenTaskTree(completedRoots);
    final activeReorderTasks = activeNodes
        .map((node) => node.task)
        .where((task) => !isTaskClosed(task))
        .toList(growable: false);
    if (!widget.isHome && activeNodes.isEmpty && completedNodes.isEmpty) {
      return AppEmptyState(
        icon: Icons.checklist_outlined,
        title: l10n.tasksEmptyTitle,
        body: l10n.tasksEmptyBody,
      );
    }

    final children = <Widget>[];
    void addGap(double height) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: height));
      }
    }

    final activeRows = [
      for (final node in activeNodes)
        _buildTaskRow(
          context,
          node,
          activeReorderTasks,
          isCompletedSection: false,
          framed: !widget.isHome,
        ),
    ];
    for (final row in activeRows) {
      addGap(AppSpacing.sm);
      children.add(row);
    }

    if (completedNodes.isNotEmpty) {
      addGap(activeNodes.isEmpty ? AppSpacing.sm : AppSpacing.lg);
      children.add(
        _CompletedSectionHeader(
          count: completedRoots.length,
          isExpanded: _showCompleted,
          onTap: () => setState(() => _showCompleted = !_showCompleted),
        ),
      );
      children.add(
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _showCompleted
              ? Column(
                  children: [
                    for (final node in completedNodes) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _buildTaskRow(
                        context,
                        node,
                        const <TaskDto>[],
                        isCompletedSection: true,
                      ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl * 3,
        ),
        children: children,
      ),
    );
  }

  List<_HomeSectionData> _buildHomeSections(BuildContext context) {
    final ranges = homeLocalRangesMs();
    final pendingRowsByTaskId = _pendingHomeCompletionRowsByTaskId();
    final pendingRootIds = _pendingHomeCompletions.keys.toSet();
    final sortedEntries =
        widget.homeTaskEntries
            .map((entry) {
              final pendingRow = pendingRowsByTaskId[entry.task.id];
              if (pendingRow == null) {
                return entry;
              }
              return HomeTaskDto(
                task: pendingRow.node.task,
                listName: entry.listName,
                isHomeTarget:
                    entry.isHomeTarget ||
                    pendingRootIds.contains(entry.task.id),
              );
            })
            .toList(growable: false)
          ..sort((a, b) => _compareHomeEntries(a, b, widget.sortMode));
    final pendingIds = _pendingHomeCompletionTaskIds();
    final bySection = {
      for (final section in _HomeSectionKind.values)
        section: <_HomeSectionRowData>[],
    };
    final countBySection = {
      for (final section in _HomeSectionKind.values) section: 0,
    };
    final taskById = {
      for (final entry in sortedEntries) entry.task.id: entry.task,
    };
    final targetSectionByTaskId = <String, _HomeSectionKind>{};
    for (final entry in sortedEntries.where((entry) => entry.isHomeTarget)) {
      final pending = _pendingHomeCompletions[entry.task.id];
      if (pending != null) {
        targetSectionByTaskId[entry.task.id] = pending.section;
        countBySection[pending.section] = countBySection[pending.section]! + 1;
        continue;
      }
      if (pendingIds.contains(entry.task.id)) {
        continue;
      }
      if (isTaskClosed(entry.task)) {
        continue;
      }
      final dueAt = entry.task.dueAt;
      if (dueAt == null) {
        continue;
      }
      final section = _homeSectionForDueAt(dueAt, ranges);
      targetSectionByTaskId[entry.task.id] = section;
      countBySection[section] = countBySection[section]! + 1;
    }
    final standaloneTaskIds = targetSectionByTaskId.keys.toSet();
    final childrenByParent = <String, List<TaskDto>>{};
    for (final entry in sortedEntries) {
      final parentId = entry.task.parentTaskId;
      if (parentId == null) {
        continue;
      }
      childrenByParent.putIfAbsent(parentId, () => <TaskDto>[]).add(entry.task);
    }
    for (final children in childrenByParent.values) {
      children.sort((a, b) => compareTasksForSortMode(a, b, widget.sortMode));
    }

    TaskTreeNode buildHomeNode(TaskDto task, int depth, Set<String> path) {
      if (path.contains(task.id)) {
        return TaskTreeNode(task: task, depth: depth, children: const []);
      }
      final nextPath = {...path, task.id};
      return TaskTreeNode(
        task: task,
        depth: depth,
        children: [
          for (final child in childrenByParent[task.id] ?? const <TaskDto>[])
            if (!standaloneTaskIds.contains(child.id))
              buildHomeNode(child, depth + 1, nextPath),
        ],
      );
    }

    for (final entry in sortedEntries.where((entry) => entry.isHomeTarget)) {
      final task = entry.task;
      if (pendingIds.contains(task.id) && !pendingRootIds.contains(task.id)) {
        continue;
      }
      final section = targetSectionByTaskId[task.id];
      if (section == null) {
        continue;
      }
      final roots = [buildHomeNode(task, 0, const <String>{})];
      bySection[section]!.addAll(
        flattenTaskTree(roots).map(
          (node) => _HomeSectionRowData(
            node: node,
            rootListId: task.listId,
            parentTaskName:
                pendingRowsByTaskId[node.task.id]?.parentTaskName ??
                (node.depth == 0
                    ? taskById[node.task.parentTaskId]?.title
                    : null),
            countsInSection: node.depth == 0,
            pendingExitPhase:
                pendingRowsByTaskId[node.task.id]?.pendingExitPhase ??
                _PendingHomeExitPhase.none,
            disableInteractions:
                pendingRowsByTaskId[node.task.id]?.disableInteractions ?? false,
            isPendingRoot: pendingRootIds.contains(node.task.id),
          ),
        ),
      );
    }
    return [
      for (final section in _HomeSectionKind.values)
        _HomeSectionData(
          kind: section,
          count: countBySection[section]!,
          rows: [
            for (final row in bySection[section]!)
              _buildHomeTaskRow(
                context,
                row.node,
                section,
                rootListId: row.rootListId,
                parentTaskName: row.parentTaskName,
                countsInSection: row.countsInSection,
                pendingExitPhase: row.pendingExitPhase,
                disableInteractions: row.disableInteractions,
                isPendingRoot: row.isPendingRoot,
              ),
          ],
        ),
    ];
  }

  List<Widget> _buildHomeClosedRows(BuildContext context) {
    final pendingIds = _pendingHomeCompletionTaskIds();
    final closedRoots =
        widget.homeTaskEntries
            .map((entry) => entry.task)
            .where((task) => task.parentTaskId == null && isTaskClosed(task))
            .where((task) => !pendingIds.contains(task.id))
            .toList(growable: false)
          ..sort((a, b) => compareTasksForSortMode(a, b, widget.sortMode));
    return [
      for (final task in closedRoots)
        _buildHomeTaskRow(
          context,
          FlattenedTaskTreeNode(
            node: TaskTreeNode(task: task, depth: 0, children: const []),
            isLastSibling: task == closedRoots.last,
            ancestorLineContinuations: const <bool>[],
          ),
          task.dueAt == null
              ? _HomeSectionKind.today
              : _homeSectionForDueAt(task.dueAt!, homeLocalRangesMs()),
          rootListId: task.listId,
          parentTaskName: null,
        ),
    ];
  }

  Widget _buildHomeTaskRow(
    BuildContext context,
    FlattenedTaskTreeNode node,
    _HomeSectionKind section, {
    required String rootListId,
    required String? parentTaskName,
    bool countsInSection = false,
    _PendingHomeExitPhase pendingExitPhase = _PendingHomeExitPhase.none,
    bool disableInteractions = false,
    bool isPendingRoot = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final sourceTask = node.task;
    final task =
        _optimisticHomeCompletionIds.contains(sourceTask.id) &&
            !isTaskClosed(sourceTask)
        ? _taskSnapshotWithStatus(sourceTask, 'done')
        : sourceTask;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dueLabel = task.dueAt == null
        ? null
        : formatRelativeDueDate(l10n, locale, task.dueAt);
    final taskDueSection = task.dueAt == null
        ? section
        : _homeSectionForDueAt(task.dueAt!, homeLocalRangesMs());
    final row = _TaskEntryMotion(
      slide: false,
      child: AppHomeTaskRow(
        key: ValueKey('task-row-${task.id}'),
        checkboxKey: ValueKey('task-done-${task.id}'),
        title: task.title,
        isDone: isTaskClosed(task),
        depth: node.depth,
        hierarchyGuideKey: ValueKey('task-hierarchy-guide-${task.id}'),
        hierarchyGuideHorizontalKey: ValueKey(
          'task-hierarchy-horizontal-${task.id}',
        ),
        isLastSibling: node.isLastSibling,
        ancestorLineContinuations: node.ancestorLineContinuations,
        parentTaskName: parentTaskName,
        parentTaskSemanticLabel: parentTaskName == null
            ? null
            : l10n.parentTaskLinkSemantics(parentTaskName),
        listName: node.depth > 0 && task.listId == rootListId
            ? ''
            : widget.homeListNameByTaskId[task.id] ?? '',
        dueLabel: dueLabel,
        dueTone: switch (taskDueSection) {
          _HomeSectionKind.overdue => HomeDueDateTone.overdue,
          _HomeSectionKind.today => HomeDueDateTone.today,
          _ => HomeDueDateTone.future,
        },
        dueSemanticLabel:
            taskDueSection == _HomeSectionKind.overdue && dueLabel != null
            ? l10n.taskDueOverdue(dueLabel)
            : null,
        priority: task.priority,
        priorityDotKey: ValueKey('task-priority-dot-${task.id}'),
        prioritySemanticLabel: l10n.taskPriority(
          taskPriorityLabel(l10n, task.priority),
        ),
        toggleDoneTooltip: isTaskClosed(task)
            ? l10n.reopenTaskTooltip
            : l10n.completeTaskTooltip,
        onToggleDone: disableInteractions
            ? null
            : isTaskClosed(task)
            ? () => _handleHomeReopenTask(task)
            : () => _handleHomeCompleteTask(
                context,
                node,
                section,
                rootListId: rootListId,
                parentTaskName: parentTaskName,
                countsInSection: countsInSection,
              ),
        onTap: () => context.push('/lists/${task.listId}/tasks/${task.id}'),
      ),
    );
    final effectiveRow = pendingExitPhase != _PendingHomeExitPhase.exiting
        ? row
        : _PendingHomeCompletionExit(
            taskId: task.id,
            useGenericKey: isPendingRoot,
            child: row,
          );
    final swipeRow = _TaskSwipeActions(
      key: ValueKey('task-swipe-actions-${task.id}'),
      task: task,
      isClosed: isTaskClosed(task),
      onLeadingAction: disableInteractions
          ? () async {}
          : isTaskClosed(task)
          ? () => _handleHomeReopenTask(task)
          : () => _handleHomeCompleteTask(
              context,
              node,
              section,
              rootListId: rootListId,
              parentTaskName: parentTaskName,
              countsInSection: countsInSection,
            ),
      onChangeDueDate: widget.onChangeDueDate,
      child: effectiveRow,
    );
    return IgnorePointer(ignoring: disableInteractions, child: swipeRow);
  }

  Future<void> _handleHomeCompleteTask(
    BuildContext context,
    FlattenedTaskTreeNode node,
    _HomeSectionKind section, {
    required String rootListId,
    required String? parentTaskName,
    required bool countsInSection,
  }) async {
    final task = node.task;
    if (_pendingHomeCompletionTaskIds().contains(task.id) ||
        _optimisticHomeCompletionIds.contains(task.id)) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      await widget.onCompleteTask(task);
      return;
    }
    final needsConfirmation = hasIncompleteDescendants(task.id, widget.tasks);
    if (!countsInSection) {
      _startOptimisticHomeCompletion(task.id);
      final operation = widget.onCompleteTask(task);
      _homeCompletionOperations[task.id] = operation;
      try {
        final completed = await operation;
        _homeCompletionOperations.remove(task.id);
        if (!completed) {
          _cancelOptimisticHomeCompletion(task.id);
        }
      } catch (_) {
        _cancelOptimisticHomeCompletion(task.id);
        rethrow;
      }
      return;
    }

    if (needsConfirmation) {
      final operation = widget.onCompleteTask(task);
      _homeCompletionOperations[task.id] = operation;
      try {
        final completed = await operation;
        _homeCompletionOperations.remove(task.id);
        if (completed && mounted) {
          _startPendingHomeCompletion(
            task: task,
            node: node,
            section: section,
            rootListId: rootListId,
            parentTaskName: parentTaskName,
            countsInSection: countsInSection,
          );
        }
      } catch (_) {
        _homeCompletionOperations.remove(task.id);
        rethrow;
      }
      return;
    }

    _startPendingHomeCompletion(
      task: task,
      node: node,
      section: section,
      rootListId: rootListId,
      parentTaskName: parentTaskName,
      countsInSection: countsInSection,
    );
    final operation = widget.onCompleteTask(task);
    _homeCompletionOperations[task.id] = operation;
    try {
      final completed = await operation;
      _homeCompletionOperations.remove(task.id);
      if (!completed) {
        _cancelPendingHomeCompletion(task.id);
      }
    } catch (_) {
      _cancelPendingHomeCompletion(task.id);
      rethrow;
    }
  }

  Future<void> _handleHomeReopenTask(TaskDto task) async {
    final operation = _homeCompletionOperations[task.id];
    if (operation != null) {
      await operation;
      _homeCompletionOperations.remove(task.id);
    }
    _cancelPendingHomeCompletion(task.id);
    _cancelOptimisticHomeCompletion(task.id);
    await widget.onReopenTask(task);
  }

  void _startOptimisticHomeCompletion(String taskId) {
    setState(() {
      _optimisticHomeCompletionIds.add(taskId);
    });
  }

  void _cancelOptimisticHomeCompletion(String taskId) {
    if (!_optimisticHomeCompletionIds.contains(taskId)) {
      return;
    }
    if (!mounted) {
      _optimisticHomeCompletionIds.remove(taskId);
      return;
    }
    setState(() {
      _optimisticHomeCompletionIds.remove(taskId);
    });
  }

  void _startPendingHomeCompletion({
    required TaskDto task,
    required FlattenedTaskTreeNode node,
    required _HomeSectionKind section,
    required String rootListId,
    required String? parentTaskName,
    required bool countsInSection,
  }) {
    final completedTask = _taskSnapshotWithStatus(task, 'done');
    final completedTree = TaskTreeNode(
      task: completedTask,
      depth: node.node.depth,
      children: node.node.children,
    );
    final rows = flattenTaskTree([completedTree])
        .asMap()
        .entries
        .map(
          (entry) => _HomeSectionRowData(
            node: entry.value,
            rootListId: rootListId,
            parentTaskName: entry.key == 0 ? parentTaskName : null,
            countsInSection: entry.key == 0 && countsInSection,
            pendingExitPhase: _PendingHomeExitPhase.holding,
            disableInteractions: entry.key != 0,
            isPendingRoot: entry.key == 0,
          ),
        )
        .toList(growable: false);
    setState(() {
      _pendingHomeCompletions[task.id] = _PendingHomeCompletion(
        rows: rows,
        section: section,
      );
    });
    _pendingHomeCompletionTimers[task.id]?.cancel();
    _pendingHomeCompletionTimers[task.id] = Timer(
      const Duration(milliseconds: 800),
      () {
        if (!mounted || !_pendingHomeCompletions.containsKey(task.id)) {
          return;
        }
        setState(() {
          final current = _pendingHomeCompletions[task.id]!;
          _pendingHomeCompletions[task.id] = current.copyWith(
            rows: [
              for (final row in current.rows)
                row.copyWith(
                  pendingExitPhase: _PendingHomeExitPhase.exiting,
                  disableInteractions: true,
                ),
            ],
          );
        });
        _pendingHomeCompletionTimers[task.id]?.cancel();
        _pendingHomeCompletionTimers[task.id] = Timer(
          const Duration(milliseconds: 200),
          () => _cancelPendingHomeCompletion(task.id),
        );
      },
    );
  }

  void _cancelPendingHomeCompletion(String taskId) {
    _pendingHomeCompletionTimers.remove(taskId)?.cancel();
    _homeCompletionOperations.remove(taskId);
    if (!_pendingHomeCompletions.containsKey(taskId)) {
      return;
    }
    if (!mounted) {
      _pendingHomeCompletions.remove(taskId);
      return;
    }
    setState(() {
      _pendingHomeCompletions.remove(taskId);
    });
  }

  void _syncPendingHomeCompletionsWithWidget() {
    if (_pendingHomeCompletions.isEmpty) {
      return;
    }
    final taskById = {
      for (final entry in widget.homeTaskEntries) entry.task.id: entry.task,
    };
    final restoredTaskIds = <String>[];
    for (final pending in _pendingHomeCompletions.values) {
      final task = taskById[pending.rows.first.node.task.id];
      if (task != null &&
          !isTaskClosed(task) &&
          !_homeCompletionOperations.containsKey(task.id) &&
          task.updatedAt > pending.rows.first.node.task.updatedAt) {
        restoredTaskIds.add(task.id);
      }
    }
    for (final taskId in restoredTaskIds) {
      _cancelPendingHomeCompletion(taskId);
    }
  }

  void _syncOptimisticHomeCompletionsWithWidget() {
    if (_optimisticHomeCompletionIds.isEmpty) {
      return;
    }
    final taskById = {
      for (final entry in widget.homeTaskEntries) entry.task.id: entry.task,
    };
    _optimisticHomeCompletionIds.removeWhere((taskId) {
      final task = taskById[taskId];
      return task == null || isTaskClosed(task);
    });
  }

  Set<String> _pendingHomeCompletionTaskIds() {
    return {
      for (final pending in _pendingHomeCompletions.values)
        for (final row in pending.rows) row.node.task.id,
    };
  }

  Map<String, _HomeSectionRowData> _pendingHomeCompletionRowsByTaskId() {
    return {
      for (final pending in _pendingHomeCompletions.values)
        for (final row in pending.rows) row.node.task.id: row,
    };
  }

  Widget _buildTaskRow(
    BuildContext context,
    FlattenedTaskTreeNode node,
    List<TaskDto> reorderScope, {
    required bool isCompletedSection,
    bool framed = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final task = node.task;
    final stats = descendantStatsOf(task.id, widget.tasks);
    final canDragReorder =
        !widget.isHome &&
        !isCompletedSection &&
        !isTaskClosed(task) &&
        widget.sortMode == TaskSortMode.manual;
    final siblings = canDragReorder
        ? _siblingsOf(task, reorderScope)
        : const <TaskDto>[];
    final siblingIndex = siblings.indexWhere(
      (sibling) => sibling.id == task.id,
    );
    final row = _TaskEntryMotion(
      child: AppTaskRow(
        key: ValueKey('task-row-${task.id}'),
        checkboxKey: ValueKey('task-done-${task.id}'),
        title: task.title,
        isDone: isTaskClosed(task),
        depth: node.depth,
        priority: task.priority,
        priorityDotKey: ValueKey('task-priority-dot-${task.id}'),
        prioritySemanticLabel: l10n.taskPriority(
          taskPriorityLabel(l10n, task.priority),
        ),
        hierarchyGuideKey: ValueKey('task-hierarchy-guide-${task.id}'),
        hierarchyGuideHorizontalKey: ValueKey(
          'task-hierarchy-horizontal-${task.id}',
        ),
        isLastSibling: node.isLastSibling,
        ancestorLineContinuations: node.ancestorLineContinuations,
        toggleDoneTooltip: isTaskClosed(task)
            ? l10n.reopenTaskTooltip
            : l10n.completeTaskTooltip,
        metadata: taskMetadataItemsFor(
          l10n: l10n,
          locale: Localizations.localeOf(context).toLanguageTag(),
          task: task,
          stats: stats,
          includeSubtaskProgress: false,
          includeWontDoStatus: !widget.isTodaySmartView,
          listName: widget.isTodaySmartView
              ? widget.homeListNameByTaskId[task.id]
              : null,
        ),
        framed: framed,
        onToggleDone: isTaskClosed(task)
            ? () => widget.onReopenTask(task)
            : () => widget.onCompleteTask(task),
        onTap: () => context.push('/lists/${task.listId}/tasks/${task.id}'),
      ),
    );
    final swipeRow = _TaskSwipeActions(
      key: ValueKey('task-swipe-actions-${task.id}'),
      task: task,
      isClosed: isTaskClosed(task),
      onLeadingAction: isTaskClosed(task)
          ? () => widget.onReopenTask(task)
          : () => widget.onCompleteTask(task),
      onChangeDueDate: widget.onChangeDueDate,
      child: row,
    );

    if (!canDragReorder || siblingIndex < 0) {
      return swipeRow;
    }

    return _TaskDragReorderTarget(
      key: ValueKey('task-drop-target-${task.id}'),
      task: task,
      siblings: siblings,
      siblingIndex: siblingIndex,
      dropIndicator: _dropIndicator,
      onHover: (indicator) => setState(() => _dropIndicator = indicator),
      onLeave: () => setState(() => _dropIndicator = null),
      onDrop:
          ({
            required draggedTask,
            required targetTask,
            required dropAfterTarget,
          }) async {
            setState(() => _dropIndicator = null);
            final boundary = _reorderBoundaryForDrop(
              draggedTask: draggedTask,
              targetTask: targetTask,
              dropAfterTarget: dropAfterTarget,
              siblings: _siblingsOf(targetTask, reorderScope),
            );
            if (boundary == null) {
              return;
            }
            await widget.onMoveTask(
              task: draggedTask,
              previousTaskId: boundary.previousTaskId,
              nextTaskId: boundary.nextTaskId,
            );
          },
      onMoveUp: siblingIndex > 0
          ? () {
              final boundary = _reorderBoundaryForAdjacentMove(
                siblingIndex: siblingIndex,
                siblings: siblings,
                direction: _TaskMoveDirection.up,
              );
              unawaited(
                widget.onMoveTask(
                  task: task,
                  previousTaskId: boundary.previousTaskId,
                  nextTaskId: boundary.nextTaskId,
                ),
              );
            }
          : null,
      onMoveDown: siblingIndex < siblings.length - 1
          ? () {
              final boundary = _reorderBoundaryForAdjacentMove(
                siblingIndex: siblingIndex,
                siblings: siblings,
                direction: _TaskMoveDirection.down,
              );
              unawaited(
                widget.onMoveTask(
                  task: task,
                  previousTaskId: boundary.previousTaskId,
                  nextTaskId: boundary.nextTaskId,
                ),
              );
            }
          : null,
      child: swipeRow,
    );
  }
}

class _TaskSwipeActions extends StatelessWidget {
  const _TaskSwipeActions({
    super.key,
    required this.task,
    required this.isClosed,
    required this.onLeadingAction,
    required this.onChangeDueDate,
    required this.child,
  });

  final TaskDto task;
  final bool isClosed;
  final Future<void> Function() onLeadingAction;
  final Future<void> Function(TaskDto task, int dueAt) onChangeDueDate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Slidable(
      key: ValueKey('task-slidable-${task.id}'),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            key: ValueKey('task-swipe-leading-${task.id}'),
            onPressed: (_) => unawaited(onLeadingAction()),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            icon: isClosed
                ? Icons.radio_button_unchecked
                : Icons.check_circle_outline,
            label: isClosed
                ? l10n.reopenTaskMenuItem
                : l10n.markTaskDoneMenuItem,
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.34,
        children: [
          SlidableAction(
            key: ValueKey('task-swipe-due-${task.id}'),
            onPressed: (_) => unawaited(_showDueDateSheet(context)),
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
            icon: Icons.event_outlined,
            label: l10n.changeDueDateTooltip,
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _showDueDateSheet(BuildContext context) async {
    final selection = await showModalBottomSheet<_DueDateSelection>(
      context: context,
      showDragHandle: true,
      builder: (context) => _DueDateSheet(task: task),
    );
    if (!context.mounted || selection == null) {
      return;
    }

    final int dueAt;
    switch (selection.kind) {
      case _DueDateSelectionKind.today:
        dueAt = homeLocalRangesMs().todayStartMs;
        break;
      case _DueDateSelectionKind.tomorrow:
        dueAt = homeLocalRangesMs().tomorrowStartMs;
        break;
      case _DueDateSelectionKind.pickDate:
        final initialDate = task.dueAt == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(task.dueAt!).toLocal();
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (!context.mounted || picked == null) {
          return;
        }
        dueAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
        ).millisecondsSinceEpoch;
        break;
    }
    await onChangeDueDate(task, dueAt);
    if (!context.mounted) {
      return;
    }
    await _showLatestUndoSnackBar(context);
  }
}

class _DueDateSheet extends StatelessWidget {
  const _DueDateSheet({required this.task});

  final TaskDto task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.dueDateLabel),
              subtitle: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              key: const ValueKey('due-sheet-today'),
              leading: const Icon(Icons.today_outlined),
              title: Text(l10n.dueToday),
              onTap: () => Navigator.of(
                context,
              ).pop(const _DueDateSelection(_DueDateSelectionKind.today)),
            ),
            ListTile(
              key: const ValueKey('due-sheet-tomorrow'),
              leading: const Icon(Icons.event_available_outlined),
              title: Text(l10n.dueTomorrow),
              onTap: () => Navigator.of(
                context,
              ).pop(const _DueDateSelection(_DueDateSelectionKind.tomorrow)),
            ),
            ListTile(
              key: const ValueKey('due-sheet-pick-date'),
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(l10n.setDueDateButton),
              onTap: () => Navigator.of(
                context,
              ).pop(const _DueDateSelection(_DueDateSelectionKind.pickDate)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskEntryMotion extends StatefulWidget {
  const _TaskEntryMotion({required this.child, this.slide = true});

  final Widget child;
  final bool slide;

  @override
  State<_TaskEntryMotion> createState() => _TaskEntryMotionState();
}

class _TaskEntryMotionState extends State<_TaskEntryMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(
      begin: widget.slide ? const Offset(0, 0.04) : Offset.zero,
      end: Offset.zero,
    ).animate(curved);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

enum _DueDateSelectionKind { today, tomorrow, pickDate }

class _DueDateSelection {
  const _DueDateSelection(this.kind);

  final _DueDateSelectionKind kind;
}

class _HomeTasksHeader extends StatelessWidget {
  const _HomeTasksHeader({
    required this.sortMenu,
    required this.listActionsMenu,
  });

  final Widget sortMenu;
  final Widget? listActionsMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = DateFormat.MMMEd(locale).format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.menu),
              tooltip: l10n.homeListMenuTooltip,
              onPressed: () => context.push('/lists'),
            ),
            const Spacer(),
            ?listActionsMenu,
            sortMenu,
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          today,
          // Derive from displayMedium so the Newsreader family and Japanese
          // serif fallback from the theme stay attached to the Home heading.
          style: theme.textTheme.displayMedium?.copyWith(
            color: colorScheme.primary,
            fontSize: 30,
            fontWeight: FontWeight.w600,
            height: 0.95,
          ),
        ),
      ],
    );
  }
}

enum _HomeSectionKind { overdue, today, tomorrow, upcoming }

class _HomeSectionData {
  const _HomeSectionData({
    required this.kind,
    required this.count,
    required this.rows,
  });

  final _HomeSectionKind kind;
  final int count;
  final List<Widget> rows;
}

class _HomeSectionRowData {
  const _HomeSectionRowData({
    required this.node,
    required this.rootListId,
    required this.parentTaskName,
    this.countsInSection = false,
    this.pendingExitPhase = _PendingHomeExitPhase.none,
    this.disableInteractions = false,
    this.isPendingRoot = false,
  });

  final FlattenedTaskTreeNode node;
  final String rootListId;
  final String? parentTaskName;
  final bool countsInSection;
  final _PendingHomeExitPhase pendingExitPhase;
  final bool disableInteractions;
  final bool isPendingRoot;

  _HomeSectionRowData copyWith({
    FlattenedTaskTreeNode? node,
    String? rootListId,
    String? parentTaskName,
    bool? countsInSection,
    _PendingHomeExitPhase? pendingExitPhase,
    bool? disableInteractions,
    bool? isPendingRoot,
  }) {
    return _HomeSectionRowData(
      node: node ?? this.node,
      rootListId: rootListId ?? this.rootListId,
      parentTaskName: parentTaskName ?? this.parentTaskName,
      countsInSection: countsInSection ?? this.countsInSection,
      pendingExitPhase: pendingExitPhase ?? this.pendingExitPhase,
      disableInteractions: disableInteractions ?? this.disableInteractions,
      isPendingRoot: isPendingRoot ?? this.isPendingRoot,
    );
  }
}

enum _PendingHomeExitPhase { none, holding, exiting }

class _PendingHomeCompletion {
  const _PendingHomeCompletion({required this.rows, required this.section});

  final List<_HomeSectionRowData> rows;
  final _HomeSectionKind section;

  _PendingHomeCompletion copyWith({
    List<_HomeSectionRowData>? rows,
    _HomeSectionKind? section,
  }) {
    return _PendingHomeCompletion(
      rows: rows ?? this.rows,
      section: section ?? this.section,
    );
  }
}

class _PendingHomeCompletionExit extends StatelessWidget {
  const _PendingHomeCompletionExit({
    required this.taskId,
    required this.useGenericKey,
    required this.child,
  });

  final String taskId;
  final bool useGenericKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: useGenericKey
          ? const ValueKey('home-pending-completion-exit')
          : ValueKey('home-pending-completion-exit-$taskId'),
      tween: Tween<double>(begin: 1, end: 0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _HomeSectionsPanel extends StatelessWidget {
  const _HomeSectionsPanel({
    required this.sections,
    required this.collapsedSections,
    required this.onToggleSection,
  });

  final List<_HomeSectionData> sections;
  final Set<_HomeSectionKind> collapsedSections;
  final ValueChanged<_HomeSectionKind> onToggleSection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < sections.length; index += 1) ...[
              _HomeSection(
                data: sections[index],
                isExpanded: !collapsedSections.contains(sections[index].kind),
                onToggle: () => onToggleSection(sections[index].kind),
              ),
              if (index < sections.length - 1)
                Divider(
                  height: AppSpacing.md,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.data,
    required this.isExpanded,
    required this.onToggle,
  });

  final _HomeSectionData data;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _homeSectionTitle(l10n, data.kind);
    final tooltip = isExpanded
        ? l10n.hideHomeSectionTooltip(title)
        : l10n.showHomeSectionTooltip(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: tooltip,
          child: Semantics(
            button: true,
            label: tooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: data.kind == _HomeSectionKind.overdue
                              ? const Color(0xFFE8755A)
                              : colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _HomeCountBadge(
                      key: ValueKey('home-section-count-${data.kind.name}'),
                      count: data.count,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isExpanded && data.rows.isNotEmpty
              ? Column(
                  children: [
                    for (
                      var index = 0;
                      index < data.rows.length;
                      index += 1
                    ) ...[
                      data.rows[index],
                      if (index < data.rows.length - 1)
                        Divider(
                          height: AppSpacing.sm,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _HomeCountBadge extends StatelessWidget {
  const _HomeCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          '$count',
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

String _homeSectionTitle(AppLocalizations l10n, _HomeSectionKind section) {
  return switch (section) {
    _HomeSectionKind.overdue => l10n.homeOverdueSectionTitle,
    _HomeSectionKind.today => l10n.todayTitle,
    _HomeSectionKind.tomorrow => l10n.homeTomorrowSectionTitle,
    _HomeSectionKind.upcoming => l10n.homeUpcomingSectionTitle,
  };
}

_HomeSectionKind _homeSectionForDueAt(
  int dueAt,
  ({int todayStartMs, int tomorrowStartMs, int dayAfterTomorrowStartMs}) ranges,
) {
  if (dueAt < ranges.todayStartMs) {
    return _HomeSectionKind.overdue;
  }
  if (dueAt < ranges.tomorrowStartMs) {
    return _HomeSectionKind.today;
  }
  if (dueAt < ranges.dayAfterTomorrowStartMs) {
    return _HomeSectionKind.tomorrow;
  }
  return _HomeSectionKind.upcoming;
}

int _compareHomeEntries(HomeTaskDto a, HomeTaskDto b, TaskSortMode sortMode) {
  final aDueAt = a.task.dueAt;
  final bDueAt = b.task.dueAt;
  if (aDueAt == null && bDueAt != null) {
    return 1;
  }
  if (aDueAt != null && bDueAt == null) {
    return -1;
  }
  if (aDueAt != null && bDueAt != null) {
    final dueAt = aDueAt.compareTo(bDueAt);
    if (dueAt != 0) {
      return dueAt;
    }
  }
  return compareTasksForSortMode(a.task, b.task, sortMode);
}

TaskDto _taskSnapshotWithStatus(TaskDto task, String status) {
  final isClosed = status == 'done' || status == 'wont_do';
  return TaskDto(
    id: task.id,
    listId: task.listId,
    parentTaskId: task.parentTaskId,
    title: task.title,
    note: task.note,
    status: status,
    priority: task.priority,
    dueAt: task.dueAt,
    scheduledAt: task.scheduledAt,
    estimatedMinutes: task.estimatedMinutes,
    sortOrder: task.sortOrder,
    completedAt: isClosed
        ? task.completedAt ?? DateTime.now().millisecondsSinceEpoch
        : null,
    closedReason: status == 'wont_do' ? task.closedReason : null,
    deletedAt: task.deletedAt,
    assignee: task.assignee,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
  );
}

class _CompletedSectionHeader extends StatelessWidget {
  const _CompletedSectionHeader({
    required this.count,
    required this.isExpanded,
    required this.onTap,
  });

  final int count;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tooltip = isExpanded
        ? l10n.hideCompletedTasksTooltip
        : l10n.showCompletedTasksTooltip;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('completed-section-toggle'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.completedTasksTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _HomeCountBadge(
                    key: const ValueKey('completed-section-count'),
                    count: count,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListActionsMenu extends StatelessWidget {
  const _ListActionsMenu({
    required this.list,
    required this.isDefaultInbox,
    required this.onRename,
    required this.onArchive,
    required this.onUnarchive,
    required this.onDelete,
  });

  final ListDto list;
  final bool isDefaultInbox;
  final Future<void> Function() onRename;
  final Future<void> Function() onArchive;
  final Future<void> Function() onUnarchive;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArchived = list.archivedAt != null;
    return PopupMenuButton<_ListAction>(
      key: const ValueKey('list-actions-menu'),
      icon: const Icon(Icons.more_horiz),
      tooltip: l10n.listActionsTooltip,
      onSelected: (action) {
        switch (action) {
          case _ListAction.rename:
            unawaited(onRename());
            break;
          case _ListAction.archive:
            unawaited(onArchive());
            break;
          case _ListAction.unarchive:
            unawaited(onUnarchive());
            break;
          case _ListAction.delete:
            unawaited(onDelete());
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ListAction.rename,
          child: Text(l10n.renameListMenuItem),
        ),
        if (!isDefaultInbox && !isArchived)
          PopupMenuItem(
            value: _ListAction.archive,
            child: Text(l10n.archiveListMenuItem),
          ),
        if (!isDefaultInbox && isArchived)
          PopupMenuItem(
            value: _ListAction.unarchive,
            child: Text(l10n.unarchiveListMenuItem),
          ),
        if (!isDefaultInbox)
          PopupMenuItem(
            value: _ListAction.delete,
            child: Text(l10n.deleteListMenuItem),
          ),
      ],
    );
  }
}

enum _ListAction { rename, archive, unarchive, delete }

ListDto? _findList(String listId, List<ListDto>? lists) {
  if (lists == null) {
    return null;
  }
  for (final list in lists) {
    if (list.id == listId) {
      return list;
    }
  }
  return null;
}

ListDto? _findDefaultList(List<ListDto> lists) {
  for (final list in lists) {
    if (list.isDefault) {
      return list;
    }
  }
  return null;
}

List<ListDto> _mergeListOptions(
  List<ListDto>? activeLists,
  List<ListDto>? archivedLists,
) {
  final byId = <String, ListDto>{};
  for (final list in activeLists ?? const <ListDto>[]) {
    byId[list.id] = list;
  }
  for (final list in archivedLists ?? const <ListDto>[]) {
    byId[list.id] = list;
  }
  return List.unmodifiable(byId.values);
}

bool _hasClosedRoot(List<TaskDto> tasks) {
  return buildTaskTree(tasks).any((node) => isTaskClosed(node.task));
}

class _TaskSortMenu extends StatelessWidget {
  const _TaskSortMenu({
    required this.selectedMode,
    required this.availableModes,
    required this.onSelected,
  });

  final TaskSortMode selectedMode;
  final List<TaskSortMode> availableModes;
  final ValueChanged<TaskSortMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<TaskSortMode>(
      key: const ValueKey('task-sort-menu'),
      icon: const Icon(Icons.sort),
      tooltip: l10n.taskSortTooltip,
      initialValue: selectedMode,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          for (final mode in availableModes)
            PopupMenuItem<TaskSortMode>(
              value: mode,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 168),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selectedMode == mode
                          ? Icons.check_circle_outline
                          : Icons.sort,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(_taskSortLabel(l10n, mode), softWrap: true),
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
    );
  }
}

String _taskSortLabel(AppLocalizations l10n, TaskSortMode mode) {
  return switch (mode) {
    TaskSortMode.manual => l10n.taskSortManual,
    TaskSortMode.dueDate => l10n.taskSortDueDate,
    TaskSortMode.priority => l10n.taskSortPriority,
    TaskSortMode.createdAt => l10n.taskSortCreatedAt,
  };
}

Future<void> _showLatestUndoSnackBar(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  container.invalidate(latestTaskUndoProvider);
  final undo = await container.read(latestTaskUndoProvider.future);
  if (!context.mounted || undo == null) {
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 4),
      persist: false,
      content: Text(_undoMessage(l10n, undo.operationType)),
      margin: const EdgeInsets.all(AppSpacing.md),
      action: SnackBarAction(
        label: l10n.undoActionLabel,
        onPressed: () {
          unawaited(_applyUndo(container, messenger, l10n, undo.id));
        },
      ),
    ),
  );
}

Future<void> _applyUndo(
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String undoId,
) async {
  messenger.hideCurrentSnackBar();
  try {
    await container.read(latestTaskUndoProvider.notifier).undo(undoId);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        persist: false,
        content: Text(l10n.undoSuccessMessage),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        persist: false,
        content: Text(l10n.undoFailedMessage(error.toString())),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }
}

String _undoMessage(AppLocalizations l10n, String operationType) {
  return switch (operationType) {
    'complete' => l10n.undoCloseMessage,
    'edit' => l10n.undoEditMessage,
    _ => l10n.undoEditMessage,
  };
}

class _TaskDragReorderTarget extends StatelessWidget {
  const _TaskDragReorderTarget({
    super.key,
    required this.task,
    required this.siblings,
    required this.siblingIndex,
    required this.dropIndicator,
    required this.onHover,
    required this.onLeave,
    required this.onDrop,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.child,
  });

  final TaskDto task;
  final List<TaskDto> siblings;
  final int siblingIndex;
  final _TaskDropIndicator? dropIndicator;
  final ValueChanged<_TaskDropIndicator> onHover;
  final VoidCallback onLeave;
  final Future<void> Function({
    required TaskDto draggedTask,
    required TaskDto targetTask,
    required bool dropAfterTarget,
  })
  onDrop;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semanticsActions = <CustomSemanticsAction, VoidCallback>{};
    final moveUp = onMoveUp;
    if (moveUp != null) {
      semanticsActions[CustomSemanticsAction(label: l10n.moveTaskUpTooltip)] =
          moveUp;
    }
    final moveDown = onMoveDown;
    if (moveDown != null) {
      semanticsActions[CustomSemanticsAction(label: l10n.moveTaskDownTooltip)] =
          moveDown;
    }

    return DragTarget<_TaskDragData>(
      onWillAcceptWithDetails: (details) => _canAcceptDrop(details.data.task),
      onMove: (details) {
        if (!_canAcceptDrop(details.data.task)) {
          return;
        }
        onHover(
          _TaskDropIndicator(
            taskId: task.id,
            dropAfter: _dropAfterFor(details.data.task),
          ),
        );
      },
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) async {
        if (!_canAcceptDrop(details.data.task)) {
          onLeave();
          return;
        }
        await onDrop(
          draggedTask: details.data.task,
          targetTask: task,
          dropAfterTarget: _dropAfterFor(details.data.task),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final indicatedBefore =
            dropIndicator?.taskId == task.id &&
            dropIndicator?.dropAfter == false;
        final indicatedAfter =
            dropIndicator?.taskId == task.id &&
            dropIndicator?.dropAfter == true;
        final row = Semantics(
          key: ValueKey('task-reorder-semantics-${task.id}'),
          container: true,
          label: task.title,
          customSemanticsActions: semanticsActions,
          child: _TaskDropIndicatorFrame(
            showBefore: indicatedBefore,
            showAfter: indicatedAfter,
            child: child,
          ),
        );
        return LongPressDraggable<_TaskDragData>(
          data: _TaskDragData(task),
          maxSimultaneousDrags: siblings.length > 1 ? 1 : 0,
          axis: Axis.vertical,
          feedback: _TaskDragFeedback(child: child),
          childWhenDragging: Opacity(opacity: 0.45, child: child),
          onDragEnd: (_) => onLeave(),
          onDraggableCanceled: (_, _) => onLeave(),
          child: row,
        );
      },
    );
  }

  bool _canAcceptDrop(TaskDto draggedTask) {
    if (draggedTask.id == task.id ||
        draggedTask.listId != task.listId ||
        draggedTask.parentTaskId != task.parentTaskId ||
        isTaskClosed(draggedTask) ||
        isTaskClosed(task)) {
      return false;
    }
    return siblings.any((sibling) => sibling.id == draggedTask.id) &&
        siblings.any((sibling) => sibling.id == task.id);
  }

  bool _dropAfterFor(TaskDto draggedTask) {
    final draggedIndex = siblings.indexWhere(
      (sibling) => sibling.id == draggedTask.id,
    );
    final targetIndex = siblings.indexWhere((sibling) => sibling.id == task.id);
    if (draggedIndex < 0 || targetIndex < 0) {
      return false;
    }
    return draggedIndex < targetIndex;
  }
}

class _TaskDragFeedback extends StatelessWidget {
  const _TaskDragFeedback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - (AppSpacing.md * 2);
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      elevation: 1,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(width: width, child: child),
    );
  }
}

class _TaskDropIndicatorFrame extends StatelessWidget {
  const _TaskDropIndicatorFrame({
    required this.showBefore,
    required this.showAfter,
    required this.child,
  });

  final bool showBefore;
  final bool showAfter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.62);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (showBefore)
          PositionedDirectional(
            start: 0,
            end: 0,
            top: -1,
            child: _TaskDropIndicatorLine(color: color),
          ),
        if (showAfter)
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: -1,
            child: _TaskDropIndicatorLine(color: color),
          ),
      ],
    );
  }
}

class _TaskDropIndicatorLine extends StatelessWidget {
  const _TaskDropIndicatorLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const SizedBox(height: 1),
    );
  }
}

class _TaskDragData {
  const _TaskDragData(this.task);

  final TaskDto task;
}

class _TaskDropIndicator {
  const _TaskDropIndicator({required this.taskId, required this.dropAfter});

  final String taskId;
  final bool dropAfter;
}

enum _TaskMoveDirection { up, down }

({String? previousTaskId, String? nextTaskId}) _reorderBoundaryForAdjacentMove({
  required int siblingIndex,
  required List<TaskDto> siblings,
  required _TaskMoveDirection direction,
}) {
  return switch (direction) {
    _TaskMoveDirection.up => (
      previousTaskId: siblingIndex >= 2 ? siblings[siblingIndex - 2].id : null,
      nextTaskId: siblings[siblingIndex - 1].id,
    ),
    _TaskMoveDirection.down => (
      previousTaskId: siblings[siblingIndex + 1].id,
      nextTaskId: siblingIndex + 2 < siblings.length
          ? siblings[siblingIndex + 2].id
          : null,
    ),
  };
}

({String? previousTaskId, String? nextTaskId})? _reorderBoundaryForDrop({
  required TaskDto draggedTask,
  required TaskDto targetTask,
  required bool dropAfterTarget,
  required List<TaskDto> siblings,
}) {
  if (draggedTask.id == targetTask.id ||
      draggedTask.parentTaskId != targetTask.parentTaskId) {
    return null;
  }
  final beforeIds = siblings.map((task) => task.id).toList(growable: false);
  if (!beforeIds.contains(draggedTask.id) ||
      !beforeIds.contains(targetTask.id)) {
    return null;
  }

  final remaining = siblings
      .where((task) => task.id != draggedTask.id)
      .toList(growable: false);
  final targetIndex = remaining.indexWhere((task) => task.id == targetTask.id);
  if (targetIndex < 0) {
    return null;
  }
  final insertIndex = targetIndex + (dropAfterTarget ? 1 : 0);
  final afterIds = [
    for (var index = 0; index < remaining.length; index += 1) ...[
      if (index == insertIndex) draggedTask.id,
      remaining[index].id,
    ],
    if (insertIndex == remaining.length) draggedTask.id,
  ];
  if (_sameStringOrder(beforeIds, afterIds)) {
    return null;
  }
  return (
    previousTaskId: insertIndex > 0 ? remaining[insertIndex - 1].id : null,
    nextTaskId: insertIndex < remaining.length
        ? remaining[insertIndex].id
        : null,
  );
}

bool _sameStringOrder(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

List<TaskDto> _siblingsOf(TaskDto task, List<TaskDto> tasks) {
  final siblings = tasks
      .where((candidate) => candidate.parentTaskId == task.parentTaskId)
      .toList();
  siblings.sort((a, b) {
    final sortOrder = a.sortOrder.compareTo(b.sortOrder);
    if (sortOrder != 0) {
      return sortOrder;
    }
    return a.id.compareTo(b.id);
  });
  return siblings;
}
