import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';

/// The task detail screen (route `/lists/:listId/tasks/:taskId`).
///
/// F-02 "シンプルUI" skeleton plus M3 task field editing.
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
      appBar: AppBar(
        title: Text(l10n.taskDetailTitle),
        actions: [
          detailAsync.maybeWhen(
            data: (task) {
              if (task == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l10n.editTaskTooltip,
                onPressed: () => _editTask(context, ref, task),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
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
              Text(l10n.taskDueAt(_formatDueAt(task.dueAt))),
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

  Future<void> _editTask(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _EditTaskDialog(
        task: task,
        onSave: ({required title, required note, required priority, dueAt}) {
          return ref
              .read(tasksProvider(listId).notifier)
              .updateTask(
                taskId: task.id,
                title: title,
                note: note,
                priority: priority,
                dueAt: dueAt,
              );
        },
      ),
    );
  }
}

String _formatDueAt(int? dueAt) {
  if (dueAt == null) {
    return '-';
  }
  final date = DateTime.fromMillisecondsSinceEpoch(dueAt).toLocal();
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class _EditTaskDialog extends StatefulWidget {
  const _EditTaskDialog({required this.task, required this.onSave});

  final TaskDto task;
  final Future<void> Function({
    required String title,
    required String note,
    required int priority,
    required int? dueAt,
  })
  onSave;

  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late int _priority;
  late int? _dueAt;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _noteController = TextEditingController(text: widget.task.note);
    _priority = widget.task.priority;
    _dueAt = widget.task.dueAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.editTaskTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.titleLabel),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.titleRequiredError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(labelText: l10n.noteLabel),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _priority,
                decoration: InputDecoration(labelText: l10n.priorityLabel),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l10n.priorityNone)),
                  DropdownMenuItem(value: 1, child: Text(l10n.priorityLow)),
                  DropdownMenuItem(value: 2, child: Text(l10n.priorityMedium)),
                  DropdownMenuItem(value: 3, child: Text(l10n.priorityHigh)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _priority = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(l10n.dueDateLabel),
              const SizedBox(height: 4),
              Text(l10n.taskDueAt(_formatDueAt(_dueAt))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(l10n.setDueDateButton),
                    onPressed: _saving ? null : () => _selectDueDate(context),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear),
                    label: Text(l10n.clearDueDateButton),
                    onPressed: _saving
                        ? null
                        : () => setState(() => _dueAt = null),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.failedToSaveTask(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final initialDate = _dueAt == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(_dueAt!).toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _dueAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
        ).millisecondsSinceEpoch;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        title: _titleController.text.trim(),
        note: _noteController.text,
        priority: _priority,
        dueAt: _dueAt,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }
}
