import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';

/// The task detail screen (route `/lists/:listId/tasks/:taskId`).
///
/// F-02 "シンプルUI" skeleton: shows the task's main fields read-only and
/// offers a single destructive action ("Move to trash"). Editing fields,
/// subtask display, and restore/trash-list UI are out of scope for M2-03
/// (they land in M3).
class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({
    super.key,
    required this.listId,
    required this.taskId,
  });

  final String listId;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final detailAsync = ref.watch(
      taskDetailProvider((listId: listId, taskId: taskId)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskDetailTitle)),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(l10n.failedToLoadTask(error.toString()))),
        data: (task) {
          if (task == null) {
            return Center(child: Text(l10n.taskNotFound));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                task.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (task.note.isNotEmpty) Text(task.note),
              const SizedBox(height: 16),
              Text(l10n.taskStatus(task.status)),
              Text(l10n.taskPriority(task.priority)),
              Text(l10n.taskCreatedAt(task.createdAt)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.moveToTrashButton),
                onPressed: () async {
                  await ref
                      .read(tasksProvider(listId).notifier)
                      .trashTask(task.id);
                  if (context.mounted) {
                    context.pop();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
