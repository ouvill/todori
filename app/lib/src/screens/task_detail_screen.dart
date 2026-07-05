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
    final tasksAsync = ref.watch(tasksProvider(listId));

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
      body: tasksAsync.when(
        loading: () => const AppLoadingState(),
        error: (error, stackTrace) =>
            AppErrorState(message: l10n.failedToLoadTask(error.toString())),
        data: (tasks) {
          final task = _findTaskById(tasks, taskId);
          if (task == null) {
            return AppEmptyState(
              icon: Icons.search_off_outlined,
              title: l10n.taskNotFound,
            );
          }
          final stats = descendantStatsOf(task.id, tasks);
          final subtasks = directSubtasksOf(task.id, tasks);
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final locale = Localizations.localeOf(context).toLanguageTag();
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // Plain title block directly on the screen background
              // (task-30): no bordered card, and no persistent
              // Local-protection/lock chip (see `docs/design/
              // visual-direction.md` Security Signal section).
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      PriorityDot(
                        key: ValueKey('task-priority-dot-${task.id}'),
                        priority: task.priority,
                        semanticLabel: l10n.taskPriority(
                          taskPriorityLabel(l10n, task.priority),
                        ),
                        isMuted: task.status == 'done',
                      ),
                      Expanded(
                        child: Text(
                          task.title,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  if (task.note.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      task.note,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TaskMetadata(
                    items: taskMetadataItemsFor(
                      l10n: l10n,
                      locale: locale,
                      task: task,
                      stats: stats,
                      includeNoDueDate: true,
                      includeStatus: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.taskCreatedAt(
                      formatAbsoluteDate(locale, task.createdAt),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.subtasksTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (subtasks.isEmpty)
                AppEmptyState(
                  icon: Icons.account_tree_outlined,
                  title: l10n.subtasksEmpty,
                )
              else
                for (final subtask in subtasks)
                  Builder(
                    key: ValueKey('subtask-row-${subtask.id}'),
                    builder: (context) {
                      final subtaskStats = descendantStatsOf(subtask.id, tasks);
                      return AppTaskRow(
                        title: subtask.title,
                        isDone: subtask.status == 'done',
                        depth: 1,
                        priority: subtask.priority,
                        priorityDotKey: ValueKey(
                          'task-priority-dot-${subtask.id}',
                        ),
                        prioritySemanticLabel: l10n.taskPriority(
                          taskPriorityLabel(l10n, subtask.priority),
                        ),
                        hierarchyGuideKey: ValueKey(
                          'task-hierarchy-guide-${subtask.id}',
                        ),
                        metadata: taskMetadataItemsFor(
                          l10n: l10n,
                          locale: locale,
                          task: subtask,
                          stats: subtaskStats,
                          includeSubtaskProgress: false,
                        ),
                        onTap: () =>
                            context.push('/lists/$listId/tasks/${subtask.id}'),
                      );
                    },
                  ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addSubtaskButton),
                  onPressed: () => _createSubtask(context, ref, task),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.moveToTrashButton),
                  onPressed: () async {
                    await ref
                        .read(tasksProvider(listId).notifier)
                        .trashTask(task.id);
                    if (context.mounted) {
                      await _showLatestUndoSnackBar(context);
                    }
                    if (context.mounted) {
                      context.pop();
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createSubtask(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final title = await showAppTextInputDialog(
      context: context,
      title: l10n.newSubtaskTitle,
      label: l10n.titleLabel,
      cancelLabel: l10n.cancelButton,
      submitLabel: l10n.createButton,
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }
    await ref
        .read(tasksProvider(listId).notifier)
        .createTask(title.trim(), parentTaskId: task.id);
  }

  Future<void> _editTask(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
  ) async {
    final saved = await showDialog<bool>(
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
    if (saved == true && context.mounted) {
      await _showLatestUndoSnackBar(context);
    }
  }
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

TaskDto? _findTaskById(List<TaskDto> tasks, String taskId) {
  for (final task in tasks) {
    if (task.id == taskId) {
      return task;
    }
  }
  return null;
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
      scrollable: true,
      title: Text(l10n.editTaskTitle),
      content: Form(
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
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _noteController,
              decoration: InputDecoration(labelText: l10n.noteLabel),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.sm),
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
            const SizedBox(height: AppSpacing.md),
            Text(l10n.dueDateLabel),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.taskDueAt(formatDueDate(l10n, _dueAt))),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
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
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.failedToSaveTask(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.saveButton),
            ),
          ],
        ),
      ],
      actionsPadding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
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
        Navigator.of(context).pop(true);
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
