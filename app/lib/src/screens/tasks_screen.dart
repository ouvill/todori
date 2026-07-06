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
    final sortMode = ref.watch(taskSortModeProvider(listId));

    final sortMenu = _TaskSortMenu(
      selectedMode: sortMode,
      onSelected: (mode) {
        ref.read(taskSortModeProvider(listId).notifier).setMode(mode);
      },
    );

    return Scaffold(
      appBar: isHome
          ? null
          : AppBar(
              title: Text(l10n.tasksTitle),
              actions: [
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
            onCreateTask: () => _createTask(context, ref),
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
          ? FloatingActionButton.extended(
              onPressed: () => _createTask(context, ref),
              tooltip: l10n.newTaskTooltip,
              icon: const Icon(Icons.add),
              label: Text(l10n.addTaskButton),
            )
          : FloatingActionButton(
              onPressed: () => _createTask(context, ref),
              tooltip: l10n.newTaskTooltip,
              child: const Icon(Icons.add),
            ),
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
}

class _TasksBody extends StatefulWidget {
  const _TasksBody({
    required this.listId,
    required this.listName,
    required this.isHome,
    required this.tasks,
    required this.sortMode,
    required this.sortMenu,
    required this.onCreateTask,
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
  final VoidCallback onCreateTask;
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
        ),
      );
      addGap(AppSpacing.lg);
      children.add(
        _TaskSectionHeader(
          pendingCount: _pendingCount(widget.tasks),
          onCreateTask: widget.onCreateTask,
        ),
      );
    }

    for (final node in activeNodes) {
      addGap(AppSpacing.sm);
      children.add(
        _buildTaskRow(
          context,
          node,
          activeReorderTasks,
          isCompletedSection: false,
        ),
      );
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
          : Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      onToggleDone: isTaskClosed(task)
          ? () => widget.onReopenTask(task)
          : isCompletedSection
          ? null
          : () => widget.onCompleteTask(task),
      onTap: () => context.push('/lists/${widget.listId}/tasks/${task.id}'),
    );
  }
}

class _HomeTasksHeader extends StatelessWidget {
  const _HomeTasksHeader({required this.listName, required this.sortMenu});

  final String listName;
  final Widget sortMenu;

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

class _TaskSectionHeader extends StatelessWidget {
  const _TaskSectionHeader({
    required this.pendingCount,
    required this.onCreateTask,
  });

  final int pendingCount;
  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Plain heading row (task-30): no card-in-card. The single pending pill
    // here is the only place pending count is shown (the hero header above
    // no longer repeats it).
    return Row(
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
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          icon: const Icon(Icons.add),
          tooltip: l10n.newTaskTooltip,
          onPressed: onCreateTask,
        ),
      ],
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
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.completedTasksTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  DecoratedBox(
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
                        l10n.completedTasksCount(count),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
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
  messenger.showSnackBar(
    SnackBar(
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
  try {
    await container.read(latestTaskUndoProvider.notifier).undo(undoId);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.undoSuccessMessage),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
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
        Icon(Icons.chevron_right, color: actionColor),
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
