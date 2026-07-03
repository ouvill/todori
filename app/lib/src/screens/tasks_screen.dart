import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';

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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(l10n.failedToLoadTasks(error.toString()))),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(child: Text(l10n.tasksEmpty));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return ListTile(
                leading: Checkbox(
                  value: task.status == 'done',
                  onChanged: (checked) {
                    if (checked == true) {
                      ref
                          .read(tasksProvider(listId).notifier)
                          .setStatus(task.id, 'done');
                    }
                  },
                ),
                title: Text(task.title),
                trailing: const Icon(Icons.chevron_right),
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
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const _NewTaskDialog(),
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }
    await ref.read(tasksProvider(listId).notifier).createTask(title.trim());
  }
}

class _NewTaskDialog extends StatefulWidget {
  const _NewTaskDialog();

  @override
  State<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<_NewTaskDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.newTaskTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.titleLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.createButton),
        ),
      ],
    );
  }
}
