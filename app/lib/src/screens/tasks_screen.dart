import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  const TasksScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tasksAsync = ref.watch(tasksProvider(listId));
    final sortMode = ref.watch(taskSortModeProvider(listId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasksTitle),
        actions: [
          _TaskSortMenu(
            selectedMode: sortMode,
            onSelected: (mode) {
              ref.read(taskSortModeProvider(listId).notifier).setMode(mode);
            },
          ),
          IconButton(
            icon: const Icon(Icons.restore_from_trash_outlined),
            tooltip: l10n.openTrashTooltip,
            onPressed: () => context.push('/trash'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const AppLoadingState(),
        error: (error, stackTrace) =>
            AppErrorState(message: l10n.failedToLoadTasks(error.toString())),
        data: (tasks) {
          if (tasks.isEmpty) {
            return AppEmptyState(
              icon: Icons.checklist_outlined,
              title: l10n.tasksEmptyTitle,
              body: l10n.tasksEmptyBody,
            );
          }
          final nodes = flattenTaskTree(
            buildTaskTree(tasks, sortMode: sortMode),
          );
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: nodes.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final node = nodes[index];
              final task = node.task;
              final stats = descendantStatsOf(task.id, tasks);
              final isManualSort = sortMode == TaskSortMode.manual;
              final siblings = isManualSort
                  ? _siblingsOf(task, tasks)
                  : const <TaskDto>[];
              final siblingIndex = siblings.indexWhere(
                (sibling) => sibling.id == task.id,
              );
              return AppTaskRow(
                key: ValueKey('task-row-${task.id}'),
                checkboxKey: ValueKey('task-done-${task.id}'),
                title: task.title,
                isDone: task.status == 'done',
                depth: node.depth,
                priority: task.priority,
                priorityDotKey: ValueKey('task-priority-dot-${task.id}'),
                prioritySemanticLabel: l10n.taskPriority(
                  taskPriorityLabel(l10n, task.priority),
                ),
                hierarchyGuideKey: ValueKey('task-hierarchy-guide-${task.id}'),
                metadata: taskMetadataItemsFor(
                  l10n: l10n,
                  task: task,
                  stats: stats,
                ),
                trailing: isManualSort
                    ? _TaskReorderControls(
                        task: task,
                        siblings: siblings,
                        siblingIndex: siblingIndex,
                        onMove:
                            ({required previousTaskId, required nextTaskId}) {
                              return ref
                                  .read(tasksProvider(listId).notifier)
                                  .reorderTask(
                                    taskId: task.id,
                                    previousTaskId: previousTaskId,
                                    nextTaskId: nextTaskId,
                                  );
                            },
                      )
                    : null,
                onToggleDone: () => _completeTask(context, ref, task, tasks),
                onTap: () => context.push('/lists/$listId/tasks/${task.id}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
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
    'delete' => l10n.undoDeleteMessage,
    'complete' => l10n.undoCompleteMessage,
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
