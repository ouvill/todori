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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tasksTitle)),
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
          final nodes = flattenTaskTree(buildTaskTree(tasks));
          return ListView.builder(
            itemCount: nodes.length,
            itemBuilder: (context, index) {
              final node = nodes[index];
              final task = node.task;
              final stats = descendantStatsOf(task.id, tasks);
              return AppTaskRow(
                key: ValueKey('task-row-${task.id}'),
                checkboxKey: ValueKey('task-done-${task.id}'),
                title: task.title,
                isDone: task.status == 'done',
                depth: node.depth,
                metadata: taskMetadataItemsFor(
                  l10n: l10n,
                  task: task,
                  stats: stats,
                ),
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
  }
}
