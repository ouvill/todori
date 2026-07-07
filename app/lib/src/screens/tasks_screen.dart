import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final String listId;
  final String? listName;
  final bool isHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tasksAsync = ref.watch(tasksProvider(listId));
    final listsAsync = ref.watch(listsProvider);
    final archivedListsAsync = ref.watch(archivedListsProvider);
    final sortMode = ref.watch(taskSortModeProvider(listId));
    final activeLists = listsAsync.value;
    final archivedLists = archivedListsAsync.value;
    final currentList =
        _findList(listId, activeLists) ?? _findList(listId, archivedLists);
    final defaultInboxId = activeLists == null || activeLists.isEmpty
        ? null
        : activeLists.first.id;
    final isDefaultInbox =
        currentList?.archivedAt == null && defaultInboxId == listId;

    final sortMenu = _TaskSortMenu(
      selectedMode: sortMode,
      onSelected: (mode) {
        ref.read(taskSortModeProvider(listId).notifier).setMode(mode);
      },
    );
    final listActionsMenu = currentList == null
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
            tasks: tasks,
            sortMode: sortMode,
            sortMenu: sortMenu,
            listActionsMenu: listActionsMenu,
            onCompleteTask: (task) => _completeTask(context, ref, task, tasks),
            onReopenTask: (task) => _reopenTask(ref, task),
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
      floatingActionButton: isHome
          ? null
          : FloatingActionButton(
              onPressed: () => _createTask(context, ref),
              tooltip: l10n.newTaskTooltip,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: isHome
          ? SafeArea(
              top: false,
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Align(
                    heightFactor: 1,
                    child: FloatingActionButton.extended(
                      onPressed: () => _createTask(context, ref),
                      tooltip: l10n.newTaskTooltip,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addTaskButton),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _createTask(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final title = await showAppTextInputDialog(
      context: context,
      title: l10n.newTaskTitle,
      label: l10n.titleLabel,
      cancelLabel: l10n.cancelButton,
      submitLabel: l10n.createButton,
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }
    await ref.read(tasksProvider(listId).notifier).createTask(title.trim());
  }

  Future<void> _completeTask(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
    List<TaskDto> tasks,
  ) async {
    if (hasIncompleteDescendants(task.id, tasks)) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: l10n.completeTaskDialogTitle,
        message: l10n.completeTaskDialogMessage,
        cancelLabel: l10n.cancelButton,
        confirmLabel: l10n.continueButton,
      );
      if (!confirmed) {
        return;
      }
    }

    await ref.read(tasksProvider(listId).notifier).setStatus(task.id, 'done');
    if (!context.mounted) {
      return;
    }
    await _showLatestUndoSnackBar(context);
  }

  Future<void> _reopenTask(WidgetRef ref, TaskDto task) {
    return ref.read(tasksProvider(listId).notifier).setStatus(task.id, 'todo');
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
    required this.tasks,
    required this.sortMode,
    required this.sortMenu,
    required this.listActionsMenu,
    required this.onCompleteTask,
    required this.onReopenTask,
    required this.onMoveTask,
  });

  final String listId;
  final String? listName;
  final bool isHome;
  final List<TaskDto> tasks;
  final TaskSortMode sortMode;
  final Widget sortMenu;
  final Widget? listActionsMenu;
  final Future<void> Function(TaskDto task) onCompleteTask;
  final Future<void> Function(TaskDto task) onReopenTask;
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

  @override
  void didUpdateWidget(covariant _TasksBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_showCompleted && !_hasClosedRoot(widget.tasks)) {
      _showCompleted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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

    if (widget.isHome) {
      children.add(
        _HomeTasksHeader(
          listName: widget.listName ?? l10n.tasksTitle,
          sortMenu: widget.sortMenu,
          listActionsMenu: widget.listActionsMenu,
        ),
      );
      addGap(AppSpacing.xl);
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
    if (widget.isHome) {
      children.add(
        _TasksPanel(
          pendingCount: _pendingCount(widget.tasks),
          rows: activeRows,
        ),
      );
    } else {
      for (final row in activeRows) {
        addGap(AppSpacing.sm);
        children.add(row);
      }
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
      if (_showCompleted) {
        for (final node in completedNodes) {
          addGap(AppSpacing.sm);
          children.add(
            _buildTaskRow(
              context,
              node,
              const <TaskDto>[],
              isCompletedSection: true,
            ),
          );
        }
      }
    }

    return SafeArea(
      top: widget.isHome,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          widget.isHome ? AppSpacing.md : AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl * 3,
        ),
        children: children,
      ),
    );
  }

  Widget _buildTaskRow(
    BuildContext context,
    TaskTreeNode node,
    List<TaskDto> reorderScope, {
    required bool isCompletedSection,
    bool framed = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final task = node.task;
    final stats = descendantStatsOf(task.id, widget.tasks);
    final showManualControls =
        !widget.isHome &&
        !isCompletedSection &&
        !isTaskClosed(task) &&
        widget.sortMode == TaskSortMode.manual;
    final siblings = showManualControls
        ? _siblingsOf(task, reorderScope)
        : const <TaskDto>[];
    final siblingIndex = siblings.indexWhere(
      (sibling) => sibling.id == task.id,
    );
    return AppTaskRow(
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
      toggleDoneTooltip: isTaskClosed(task)
          ? l10n.reopenTaskTooltip
          : l10n.completeTaskTooltip,
      metadata: taskMetadataItemsFor(
        l10n: l10n,
        locale: Localizations.localeOf(context).toLanguageTag(),
        task: task,
        stats: stats,
        includeSubtaskProgress: false,
      ),
      framed: framed,
      trailing: showManualControls
          ? _TaskReorderControls(
              task: task,
              siblings: siblings,
              siblingIndex: siblingIndex,
              onMove: ({required previousTaskId, required nextTaskId}) {
                return widget.onMoveTask(
                  task: task,
                  previousTaskId: previousTaskId,
                  nextTaskId: nextTaskId,
                );
              },
            )
          : null,
      onToggleDone: isTaskClosed(task)
          ? () => widget.onReopenTask(task)
          : () => widget.onCompleteTask(task),
      onTap: () => context.push('/lists/${widget.listId}/tasks/${task.id}'),
    );
  }
}

class _HomeTasksHeader extends StatelessWidget {
  const _HomeTasksHeader({
    required this.listName,
    required this.sortMenu,
    required this.listActionsMenu,
  });

  final String listName;
  final Widget sortMenu;
  final Widget? listActionsMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = DateFormat('EEE, MMM d', locale).format(DateTime.now());

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
        const SizedBox(height: AppSpacing.xl),
        Text(
          l10n.todayTitle,
          // Newsreader display serif, kept to a moderate w600 weight per
          // the design direction (avoid a too-heavy serif+bold combination).
          style: theme.textTheme.displayMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
            height: 0.95,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          today,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.list_alt_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    listName,
                    softWrap: true,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TasksPanel extends StatelessWidget {
  const _TasksPanel({required this.pendingCount, required this.rows});

  final int pendingCount;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeTasksSectionTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                _PendingBadge(count: pendingCount),
              ],
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (var index = 0; index < rows.length; index += 1) ...[
                rows[index],
                if (index < rows.length - 1)
                  Divider(
                    height: AppSpacing.md,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          l10n.homePendingCount(count),
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
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
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l10n.completedTasksTitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l10n.completedTasksCount(count),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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

int _pendingCount(List<TaskDto> tasks) {
  final activeRoots = buildTaskTree(
    tasks,
  ).where((node) => !isTaskClosed(node.task));
  return flattenTaskTree(
    activeRoots.toList(growable: false),
  ).where((node) => !isTaskClosed(node.task)).length;
}

bool _hasClosedRoot(List<TaskDto> tasks) {
  return buildTaskTree(tasks).any((node) => isTaskClosed(node.task));
}

class _TaskSortMenu extends StatelessWidget {
  const _TaskSortMenu({required this.selectedMode, required this.onSelected});

  final TaskSortMode selectedMode;
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
          for (final mode in TaskSortMode.values)
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

class _TaskReorderControls extends StatelessWidget {
  const _TaskReorderControls({
    required this.task,
    required this.siblings,
    required this.siblingIndex,
    required this.onMove,
  });

  final TaskDto task;
  final List<TaskDto> siblings;
  final int siblingIndex;
  final Future<void> Function({
    required String? previousTaskId,
    required String? nextTaskId,
  })
  onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final canMoveUp = siblingIndex > 0;
    final canMoveDown = siblingIndex >= 0 && siblingIndex < siblings.length - 1;
    final actionColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    final disabledActionColor = colorScheme.onSurfaceVariant.withValues(
      alpha: 0.28,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('task-move-up-${task.id}'),
          icon: const Icon(Icons.keyboard_arrow_up, size: 21),
          tooltip: l10n.moveTaskUpTooltip,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            foregroundColor: actionColor,
            disabledForegroundColor: disabledActionColor,
            minimumSize: const Size(40, 40),
          ),
          onPressed: canMoveUp
              ? () async {
                  final nextTaskId = siblings[siblingIndex - 1].id;
                  final previousTaskId = siblingIndex >= 2
                      ? siblings[siblingIndex - 2].id
                      : null;
                  await onMove(
                    previousTaskId: previousTaskId,
                    nextTaskId: nextTaskId,
                  );
                }
              : null,
        ),
        IconButton(
          key: ValueKey('task-move-down-${task.id}'),
          icon: const Icon(Icons.keyboard_arrow_down, size: 21),
          tooltip: l10n.moveTaskDownTooltip,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            foregroundColor: actionColor,
            disabledForegroundColor: disabledActionColor,
            minimumSize: const Size(40, 40),
          ),
          onPressed: canMoveDown
              ? () async {
                  final previousTaskId = siblings[siblingIndex + 1].id;
                  final nextTaskId = siblingIndex + 2 < siblings.length
                      ? siblings[siblingIndex + 2].id
                      : null;
                  await onMove(
                    previousTaskId: previousTaskId,
                    nextTaskId: nextTaskId,
                  );
                }
              : null,
        ),
      ],
    );
  }
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
