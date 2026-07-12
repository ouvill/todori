import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/core/task_tree.dart';
import 'package:todori/src/core/task_due.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/dialogs.dart';
import 'package:todori/src/ui/header_actions.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/task_components.dart';
import 'package:todori/src/ui/task_completion_motion.dart';
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
                const AppHeaderSearchAction(),
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
            onChangeDue: (task, due) => _changeDue(ref, task, due),
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
    );
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

  Future<void> _changeDue(WidgetRef ref, TaskDto task, TaskDueDto? due) {
    if (isTodaySmartView) {
      return ref.read(homeTasksProvider.notifier).updateDue(task, due);
    }
    return ref.read(tasksProvider(task.listId).notifier).updateDue(task, due);
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
    required this.onChangeDue,
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
  final Future<void> Function(TaskDto task, TaskDueDto? due) onChangeDue;
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
  final Map<String, Future<bool>> _homeCompletionOperations = {};
  final Set<String> _optimisticHomeCompletionIds = {};
  late final TaskCompletionRetentionController<String>
  _completionRetentionController;
  _TaskDropIndicator? _dropIndicator;

  @override
  void initState() {
    super.initState();
    _completionRetentionController = TaskCompletionRetentionController<String>()
      ..addListener(_handleCompletionRetentionChanged);
  }

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
    _completionRetentionController
      ..removeListener(_handleCompletionRetentionChanged)
      ..dispose();
    super.dispose();
  }

  void _handleCompletionRetentionChanged() {
    if (!mounted) {
      return;
    }
    final retainedKeys = _completionRetentionController.keys.toSet();
    setState(() {
      _pendingHomeCompletions.removeWhere(
        (taskId, _) => !retainedKeys.contains(taskId),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.isHome) {
      final closedRows = _buildHomeClosedRowData();
      final homeSections = _buildHomeSections();
      final hasVisibleHomeTasks = homeSections.any(
        (section) => section.rows.isNotEmpty || section.count > 0,
      );
      final visibleHomeSections = hasVisibleHomeTasks || closedRows.isNotEmpty
          ? homeSections
          : const <_HomeSectionData>[];
      return SafeArea(
        top: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    12,
                    AppSpacing.md,
                    AppSpacing.xl * 3,
                  ),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _HomeTasksHeader(
                          sortMenu: widget.sortMenu,
                          listActionsMenu: widget.listActionsMenu,
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.md),
                      ),
                      if (visibleHomeSections.isEmpty)
                        SliverToBoxAdapter(child: _HomeClearState(l10n: l10n))
                      else
                        _HomeSectionsPanelSliver(
                          sections: visibleHomeSections,
                          collapsedSections: _collapsedHomeSections,
                          onToggleSection: (section) {
                            setState(() {
                              if (!_collapsedHomeSections.add(section)) {
                                _collapsedHomeSections.remove(section);
                              }
                            });
                          },
                          rowBuilder: (context, row, section) =>
                              _buildHomeTaskRow(
                                context,
                                row.node,
                                section,
                                rootListId: row.rootListId,
                                parentTaskName: row.parentTaskName,
                                countsInSection: row.countsInSection,
                                pendingCompletionKey: row.pendingCompletionKey,
                                disableInteractions:
                                    row.disableInteractions ||
                                    _isCompletionExiting(
                                      row.pendingCompletionKey,
                                    ),
                                isPendingRoot: row.isPendingRoot,
                              ),
                        ),
                      if (closedRows.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppSpacing.lg),
                        ),
                        SliverToBoxAdapter(
                          child: _CompletedSectionHeader(
                            count: closedRows.length,
                            isExpanded: _showCompleted,
                            onTap: () => setState(
                              () => _showCompleted = !_showCompleted,
                            ),
                          ),
                        ),
                        if (_showCompleted)
                          SliverList.builder(
                            itemCount: closedRows.length * 2,
                            itemBuilder: (context, index) {
                              if (index.isEven) {
                                return const SizedBox(height: AppSpacing.sm);
                              }
                              final row = closedRows[index ~/ 2];
                              return _buildHomeTaskRow(
                                context,
                                row.node,
                                row.node.task.due == null
                                    ? _HomeSectionKind.today
                                    : _homeSectionForDue(
                                        row.node.task.due!,
                                        homeLocalRangesMs(),
                                      ),
                                rootListId: row.rootListId,
                                parentTaskName: row.parentTaskName,
                              );
                            },
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    if (activeNodes.isEmpty && completedNodes.isEmpty) {
      return AppEmptyState(
        icon: LucideIcons.listChecks300,
        title: l10n.tasksEmptyTitle,
        body: l10n.tasksEmptyBody,
      );
    }

    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xl * 3,
            ),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (activeNodes.isNotEmpty)
                  _TaskRowsSliver(
                    nodes: activeNodes,
                    separatorHeight: AppSpacing.sm,
                    rowBuilder: (context, node) => _buildTaskRow(
                      context,
                      node,
                      activeReorderTasks,
                      isCompletedSection: false,
                    ),
                  ),
                if (completedNodes.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: activeNodes.isEmpty
                          ? AppSpacing.sm
                          : AppSpacing.lg,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _CompletedSectionHeader(
                      count: completedRoots.length,
                      isExpanded: _showCompleted,
                      onTap: () =>
                          setState(() => _showCompleted = !_showCompleted),
                    ),
                  ),
                  if (_showCompleted)
                    SliverList.builder(
                      itemCount: completedNodes.length * 2,
                      itemBuilder: (context, index) {
                        if (index.isEven) {
                          return const SizedBox(height: AppSpacing.sm);
                        }
                        return _buildTaskRow(
                          context,
                          completedNodes[index ~/ 2],
                          const <TaskDto>[],
                          isCompletedSection: true,
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_HomeSectionData> _buildHomeSections() {
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
      final section = _homeSectionForTask(entry.task, ranges);
      if (section == null) {
        continue;
      }
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
            pendingCompletionKey:
                pendingRowsByTaskId[node.task.id]?.pendingCompletionKey,
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
          rows: bySection[section]!,
        ),
    ];
  }

  List<_HomeSectionRowData> _buildHomeClosedRowData() {
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
        _HomeSectionRowData(
          node: FlattenedTaskTreeNode(
            node: TaskTreeNode(task: task, depth: 0, children: const []),
            isLastSibling: task == closedRoots.last,
            ancestorLineContinuations: const <bool>[],
          ),
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
    String? pendingCompletionKey,
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
    final dueLabel = task.due == null
        ? null
        : formatRelativeDueDate(l10n, locale, task.due);
    final taskDueSection = task.due == null
        ? section
        : _homeSectionForDue(task.due!, homeLocalRangesMs());
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
        semanticLabel: _taskRowSemanticLabel(
          l10n: l10n,
          title: task.title,
          status: taskStatusLabel(l10n, task.status),
          priority: taskPriorityLabel(l10n, task.priority),
          dueLabel: dueLabel,
          listName: node.depth > 0 && task.listId == rootListId
              ? null
              : widget.homeListNameByTaskId[task.id],
          parentTaskName: parentTaskName,
          depth: node.depth,
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
    final isExiting = _isCompletionExiting(pendingCompletionKey);
    final effectiveRow = !isExiting
        ? row
        : AppTaskCompletionExit(
            key: isPendingRoot
                ? const ValueKey('home-pending-completion-exit')
                : ValueKey('home-pending-completion-exit-${task.id}'),
            isExiting: true,
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
      onChangeDue: widget.onChangeDue,
      child: effectiveRow,
    );
    return IgnorePointer(
      key: ValueKey('task-home-row-shell-${task.id}'),
      ignoring: disableInteractions,
      child: swipeRow,
    );
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
            pendingCompletionKey: task.id,
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
    _completionRetentionController.retain(task.id);
  }

  void _cancelPendingHomeCompletion(String taskId) {
    _homeCompletionOperations.remove(taskId);
    _completionRetentionController.cancel(taskId);
    if (!mounted) {
      _pendingHomeCompletions.remove(taskId);
      return;
    }
    if (_pendingHomeCompletions.containsKey(taskId)) {
      setState(() => _pendingHomeCompletions.remove(taskId));
    }
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

  bool _isCompletionExiting(String? key) {
    return key != null &&
        _completionRetentionController.phaseOf(key) ==
            TaskCompletionRetentionPhase.exiting;
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
    bool framed = false,
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
        semanticLabel: _taskRowSemanticLabel(
          l10n: l10n,
          title: task.title,
          status: taskStatusLabel(l10n, task.status),
          priority: taskPriorityLabel(l10n, task.priority),
          dueLabel: task.due == null
              ? null
              : formatRelativeDueDate(
                  l10n,
                  Localizations.localeOf(context).toLanguageTag(),
                  task.due,
                ),
          listName: widget.isTodaySmartView
              ? widget.homeListNameByTaskId[task.id]
              : null,
          parentTaskName: null,
          depth: node.depth,
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
        ).take(2).toList(growable: false),
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
      onChangeDue: widget.onChangeDue,
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
    required this.onChangeDue,
    required this.child,
  });

  final TaskDto task;
  final bool isClosed;
  final Future<void> Function() onLeadingAction;
  final Future<void> Function(TaskDto task, TaskDueDto? due) onChangeDue;
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
            icon: isClosed ? LucideIcons.circle300 : LucideIcons.circleCheck300,
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
            icon: LucideIcons.calendarDays300,
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
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DueDateSheet(task: task),
    );
    if (!context.mounted || selection == null) {
      return;
    }

    TaskDueDto due;
    switch (selection.kind) {
      case _DueDateSelectionKind.today:
        due = dateOnlyDue(DateTime.now());
        break;
      case _DueDateSelectionKind.tomorrow:
        due = dateOnlyDue(DateTime.now().add(const Duration(days: 1)));
        break;
      case _DueDateSelectionKind.pickDate:
        final initialDate = task.due == null
            ? DateTime.now()
            : taskDueDisplayDate(task.due!);
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (!context.mounted || picked == null) {
          return;
        }
        due = dateOnlyDue(picked);
        break;
      case _DueDateSelectionKind.pickDateTime:
        final initial = task.due == null
            ? DateTime.now()
            : taskDueDisplayDate(task.due!);
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (!context.mounted || pickedDate == null) {
          return;
        }
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initial),
        );
        if (!context.mounted || pickedTime == null) {
          return;
        }
        final localDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        final savedTimeZone = taskDueSavedTimeZone(task.due);
        final timeZone =
            savedTimeZone ??
            await ProviderScope.containerOf(
              context,
              listen: false,
            ).read(bridgeServiceProvider).getLocalTimeZone();
        try {
          due = dateTimeDue(localDateTime: localDateTime, timeZone: timeZone);
        } on FormatException {
          return;
        }
        break;
    }
    await onChangeDue(task, due);
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
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
            leading: const Icon(LucideIcons.calendarCheck300),
            title: Text(l10n.dueToday),
            onTap: () => Navigator.of(
              context,
            ).pop(const _DueDateSelection(_DueDateSelectionKind.today)),
          ),
          ListTile(
            key: const ValueKey('due-sheet-tomorrow'),
            leading: const Icon(LucideIcons.calendarPlus300),
            title: Text(l10n.dueTomorrow),
            onTap: () => Navigator.of(
              context,
            ).pop(const _DueDateSelection(_DueDateSelectionKind.tomorrow)),
          ),
          ListTile(
            key: const ValueKey('due-sheet-pick-date'),
            leading: const Icon(LucideIcons.calendarDays300),
            title: Text(l10n.setDueDateButton),
            onTap: () => Navigator.of(
              context,
            ).pop(const _DueDateSelection(_DueDateSelectionKind.pickDate)),
          ),
          ListTile(
            key: const ValueKey('due-sheet-pick-date-time'),
            leading: const Icon(LucideIcons.calendarClock300),
            title: Text(l10n.setDueDateTimeButton),
            onTap: () => Navigator.of(
              context,
            ).pop(const _DueDateSelection(_DueDateSelectionKind.pickDateTime)),
          ),
        ],
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

class _TaskRowsSliver extends StatelessWidget {
  const _TaskRowsSliver({
    required this.nodes,
    required this.separatorHeight,
    required this.rowBuilder,
  });

  final List<FlattenedTaskTreeNode> nodes;
  final double separatorHeight;
  final Widget Function(BuildContext context, FlattenedTaskTreeNode node)
  rowBuilder;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverList.builder(
      itemCount: nodes.length * 2 - 1,
      itemBuilder: (context, index) {
        if (index.isOdd) {
          return SizedBox(height: separatorHeight / 2);
        }
        return rowBuilder(context, nodes[index ~/ 2]);
      },
    );
  }
}

enum _DueDateSelectionKind { today, tomorrow, pickDate, pickDateTime }

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
    final today = formatHomeHeaderDate(locale, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    today,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.homeTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            if (listActionsMenu != null) ...[
              listActionsMenu!,
              const SizedBox(width: AppSpacing.xs),
            ],
            const AppHeaderSearchAction(),
            Padding(padding: const EdgeInsets.only(bottom: 1), child: sortMenu),
          ],
        ),
      ],
    );
  }
}

class _HomeClearState extends StatelessWidget {
  const _HomeClearState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                LucideIcons.sprout300,
                size: 24,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.homeClearTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.homeClearBody,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
  final List<_HomeSectionRowData> rows;
}

class _HomeSectionRowData {
  const _HomeSectionRowData({
    required this.node,
    required this.rootListId,
    required this.parentTaskName,
    this.countsInSection = false,
    this.pendingCompletionKey,
    this.disableInteractions = false,
    this.isPendingRoot = false,
  });

  final FlattenedTaskTreeNode node;
  final String rootListId;
  final String? parentTaskName;
  final bool countsInSection;
  final String? pendingCompletionKey;
  final bool disableInteractions;
  final bool isPendingRoot;
}

class _PendingHomeCompletion {
  const _PendingHomeCompletion({required this.rows, required this.section});

  final List<_HomeSectionRowData> rows;
  final _HomeSectionKind section;
}

class _HomeSectionsPanelSliver extends StatelessWidget {
  const _HomeSectionsPanelSliver({
    required this.sections,
    required this.collapsedSections,
    required this.onToggleSection,
    required this.rowBuilder,
  });

  final List<_HomeSectionData> sections;
  final Set<_HomeSectionKind> collapsedSections;
  final ValueChanged<_HomeSectionKind> onToggleSection;
  final Widget Function(
    BuildContext context,
    _HomeSectionRowData row,
    _HomeSectionKind section,
  )
  rowBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        for (var index = 0; index < sections.length; index += 1) ...[
          _HomeSectionSliver(
            data: sections[index],
            isExpanded: !collapsedSections.contains(sections[index].kind),
            onToggle: () => onToggleSection(sections[index].kind),
            rowBuilder: rowBuilder,
          ),
          if (index < sections.length - 1)
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
      ],
    );
  }
}

class _HomeSectionSliver extends StatelessWidget {
  const _HomeSectionSliver({
    required this.data,
    required this.isExpanded,
    required this.onToggle,
    required this.rowBuilder,
  });

  final _HomeSectionData data;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget Function(
    BuildContext context,
    _HomeSectionRowData row,
    _HomeSectionKind section,
  )
  rowBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _HomeSectionHeader(
            data: data,
            isExpanded: isExpanded,
            onToggle: onToggle,
          ),
        ),
        if (isExpanded && data.rows.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            sliver: SliverList.builder(
              itemCount: data.rows.length * 2 - 1,
              itemBuilder: (context, index) {
                if (index.isOdd) {
                  return const SizedBox(height: 2);
                }
                return rowBuilder(context, data.rows[index ~/ 2], data.kind);
              },
            ),
          ),
      ],
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
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
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: data.kind == _HomeSectionKind.overdue
                        ? const Color(0xFFE8755A)
                        : colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: data.kind == _HomeSectionKind.overdue
                          ? const Color(0xFFE8755A)
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                _HomeCountLabel(
                  key: ValueKey('home-section-count-${data.kind.name}'),
                  count: data.count,
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(
                      isExpanded
                          ? LucideIcons.chevronUp300
                          : LucideIcons.chevronDown300,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCountLabel extends StatelessWidget {
  const _HomeCountLabel({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        '$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
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

_HomeSectionKind _homeSectionForDue(
  TaskDueDto due,
  ({int todayStartMs, int tomorrowStartMs, int dayAfterTomorrowStartMs}) ranges,
) {
  if (taskDueIsOverdue(due)) {
    return _HomeSectionKind.overdue;
  }
  final localDate = taskDueLocalDate(due);
  final localMs = DateTime(
    localDate.year,
    localDate.month,
    localDate.day,
  ).millisecondsSinceEpoch;
  if (localMs < ranges.tomorrowStartMs) {
    return _HomeSectionKind.today;
  }
  if (localMs < ranges.dayAfterTomorrowStartMs) {
    return _HomeSectionKind.tomorrow;
  }
  return _HomeSectionKind.upcoming;
}

_HomeSectionKind? _homeSectionForTask(
  TaskDto task,
  ({int todayStartMs, int tomorrowStartMs, int dayAfterTomorrowStartMs}) ranges,
) {
  final due = task.due;
  if (due != null && taskDueIsOverdue(due)) {
    return _HomeSectionKind.overdue;
  }
  final scheduledAt = task.scheduledAt;
  if (scheduledAt != null &&
      scheduledAt >= ranges.todayStartMs &&
      scheduledAt < ranges.tomorrowStartMs) {
    return _HomeSectionKind.today;
  }
  return due == null ? null : _homeSectionForDue(due, ranges);
}

int _compareHomeEntries(HomeTaskDto a, HomeTaskDto b, TaskSortMode sortMode) {
  final dueComparison = compareTaskDue(a.task.due, b.task.due);
  if (dueComparison != 0) {
    return dueComparison;
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
    due: task.due,
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
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.35,
                      ),
                    ),
                  ),
                  _HomeCountLabel(
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
                            ? LucideIcons.chevronUp300
                            : LucideIcons.chevronDown300,
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
      icon: const Icon(LucideIcons.moreHorizontal300),
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
      icon: const Icon(LucideIcons.arrowDownUp300),
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
                          ? LucideIcons.circleCheck300
                          : LucideIcons.arrowDownUp300,
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

String _taskRowSemanticLabel({
  required AppLocalizations l10n,
  required String title,
  required String status,
  required String priority,
  required String? dueLabel,
  required String? listName,
  required String? parentTaskName,
  required int depth,
}) {
  final parts = <String>[
    title,
    l10n.taskRowStatusSemantics(status),
    l10n.taskPriority(priority),
    if (dueLabel != null) l10n.taskRowDueSemantics(dueLabel),
    if (parentTaskName != null) l10n.parentTaskLinkSemantics(parentTaskName),
    if (listName != null && listName.isNotEmpty)
      l10n.taskRowListSemantics(listName),
    if (depth > 0) l10n.taskRowSubtaskLevelSemantics(depth + 1),
    l10n.taskRowOpenHint,
  ];
  return parts.join('. ');
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
