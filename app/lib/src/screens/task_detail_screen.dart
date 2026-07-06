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
              return PopupMenuButton<_TaskDetailAction>(
                tooltip: l10n.taskActionsTooltip,
                onSelected: (action) {
                  switch (action) {
                    case _TaskDetailAction.markDone:
                      unawaited(_setTaskStatus(context, ref, task, 'done'));
                    case _TaskDetailAction.markWontDo:
                      unawaited(_setTaskStatus(context, ref, task, 'wont_do'));
                    case _TaskDetailAction.reopen:
                      unawaited(_setTaskStatus(context, ref, task, 'todo'));
                    case _TaskDetailAction.delete:
                      unawaited(_deleteTask(context, ref, task));
                  }
                },
                itemBuilder: (context) =>
                    _taskDetailMenuItems(l10n: l10n, task: task),
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
                  _InlineTitleEditor(
                    key: ValueKey('task-title-editor-${task.id}'),
                    title: task.title,
                    semanticLabel: l10n.editTaskTitleSemantics,
                    onSave: (title) =>
                        _updateTaskFields(context, ref, task, title: title),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _InlineNoteEditor(
                    key: ValueKey('task-note-editor-${task.id}'),
                    note: task.note,
                    placeholder: l10n.addNotePlaceholder,
                    semanticLabel: l10n.editTaskNoteSemantics,
                    onSave: (note) =>
                        _updateTaskFields(context, ref, task, note: note),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _EditableTaskMetadata(
                    task: task,
                    stats: stats,
                    locale: locale,
                    onSelectDueDate: () => _selectDueDate(context, ref, task),
                    onClearDueDate: task.dueAt == null
                        ? null
                        : () => _updateTaskFields(
                            context,
                            ref,
                            task,
                            dueAt: null,
                          ),
                    onPrioritySelected: (priority) => _updateTaskFields(
                      context,
                      ref,
                      task,
                      priority: priority,
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
                        isDone: isTaskClosed(subtask),
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

  Future<bool> _updateTaskFields(
    BuildContext context,
    WidgetRef ref,
    TaskDto task, {
    String? title,
    String? note,
    int? priority,
    Object? dueAt = _unchangedDueAt,
  }) async {
    final nextTitle = title ?? task.title;
    final nextNote = note ?? task.note;
    final nextPriority = priority ?? task.priority;
    final nextDueAt = identical(dueAt, _unchangedDueAt)
        ? task.dueAt
        : dueAt as int?;

    if (nextTitle == task.title &&
        nextNote == task.note &&
        nextPriority == task.priority &&
        nextDueAt == task.dueAt) {
      return true;
    }

    try {
      await ref
          .read(tasksProvider(listId).notifier)
          .updateTask(
            taskId: task.id,
            title: nextTitle,
            note: nextNote,
            priority: nextPriority,
            dueAt: nextDueAt,
          );
      if (context.mounted) {
        await _showLatestUndoSnackBar(context);
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToSaveTask(error.toString())),
            margin: const EdgeInsets.all(AppSpacing.md),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _selectDueDate(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
  ) async {
    final initialDate = task.dueAt == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(task.dueAt!).toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    await _updateTaskFields(
      context,
      ref,
      task,
      dueAt: DateTime(
        picked.year,
        picked.month,
        picked.day,
      ).millisecondsSinceEpoch,
    );
  }

  Future<void> _deleteTask(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final descendantCount = await ref
        .read(tasksProvider(listId).notifier)
        .countDescendants(task.id);
    if (!context.mounted) {
      return;
    }
    final message = descendantCount == 0
        ? l10n.deleteTaskDialogMessage
        : l10n.deleteTaskDialogMessageWithDescendants(descendantCount);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l10n.deleteTaskDialogTitle,
      message: message,
      cancelLabel: l10n.cancelButton,
      confirmLabel: l10n.deleteButton,
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(tasksProvider(listId).notifier).deleteTask(task.id);
    if (context.mounted) {
      context.pop();
    }
  }

  Future<void> _setTaskStatus(
    BuildContext context,
    WidgetRef ref,
    TaskDto task,
    String status,
  ) async {
    if (status == 'done' || status == 'wont_do') {
      final tasks = await ref.read(tasksProvider(listId).future);
      if (!context.mounted) {
        return;
      }
      if (hasIncompleteDescendants(task.id, tasks)) {
        final l10n = AppLocalizations.of(context)!;
        final confirmed = await showAppConfirmDialog(
          context: context,
          title: status == 'wont_do'
              ? l10n.wontDoTaskDialogTitle
              : l10n.completeTaskDialogTitle,
          message: status == 'wont_do'
              ? l10n.wontDoTaskDialogMessage
              : l10n.completeTaskDialogMessage,
          cancelLabel: l10n.cancelButton,
          confirmLabel: l10n.continueButton,
        );
        if (!confirmed) {
          return;
        }
      }
    }

    await ref.read(tasksProvider(listId).notifier).setStatus(task.id, status);
    if (context.mounted && (status == 'done' || status == 'wont_do')) {
      await _showLatestUndoSnackBar(context);
    }
  }
}

enum _TaskDetailAction { markDone, markWontDo, reopen, delete }

List<PopupMenuEntry<_TaskDetailAction>> _taskDetailMenuItems({
  required AppLocalizations l10n,
  required TaskDto task,
}) {
  final items = <PopupMenuEntry<_TaskDetailAction>>[];
  if (task.status == 'todo' || task.status == 'in_progress') {
    items.addAll([
      PopupMenuItem(
        value: _TaskDetailAction.markDone,
        child: Text(l10n.markTaskDoneMenuItem),
      ),
      PopupMenuItem(
        value: _TaskDetailAction.markWontDo,
        child: Text(l10n.markTaskWontDoMenuItem),
      ),
    ]);
  } else if (isTaskClosed(task)) {
    items.add(
      PopupMenuItem(
        value: _TaskDetailAction.reopen,
        child: Text(l10n.reopenTaskMenuItem),
      ),
    );
  }
  if (items.isNotEmpty) {
    items.add(const PopupMenuDivider());
  }
  items.add(
    PopupMenuItem(
      value: _TaskDetailAction.delete,
      child: Text(l10n.deleteTaskMenuItem),
    ),
  );
  return items;
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

TaskDto? _findTaskById(List<TaskDto> tasks, String taskId) {
  for (final task in tasks) {
    if (task.id == taskId) {
      return task;
    }
  }
  return null;
}

const Object _unchangedDueAt = Object();

class _InlineTitleEditor extends StatefulWidget {
  const _InlineTitleEditor({
    super.key,
    required this.title,
    required this.semanticLabel,
    required this.onSave,
  });

  final String title;
  final String semanticLabel;
  final Future<bool> Function(String title) onSave;

  @override
  State<_InlineTitleEditor> createState() => _InlineTitleEditorState();
}

class _InlineTitleEditorState extends State<_InlineTitleEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.title);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _InlineTitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.title != widget.title) {
      _controller.text = widget.title;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_editing && !_focusNode.hasFocus) {
      unawaited(_commit());
    }
  }

  void _startEditing() {
    if (_editing) {
      return;
    }
    setState(() {
      _editing = true;
      _controller.text = widget.title;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  bool get _hasComposingRange {
    final range = _controller.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  Future<void> _commit({bool fromSubmitted = false}) async {
    if (_saving) {
      return;
    }
    if (fromSubmitted && _hasComposingRange) {
      return;
    }
    final nextTitle = _controller.text.trim();
    if (nextTitle.isEmpty) {
      _controller.text = widget.title;
      if (mounted) {
        setState(() => _editing = false);
      }
      return;
    }
    if (nextTitle == widget.title) {
      if (mounted) {
        setState(() => _editing = false);
      }
      return;
    }
    setState(() => _saving = true);
    final saved = await widget.onSave(nextTitle);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _editing = !saved;
    });
    if (!saved) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_editing) {
      return TextField(
        key: const ValueKey('task-title-inline-field'),
        controller: _controller,
        focusNode: _focusNode,
        enabled: !_saving,
        autofocus: true,
        minLines: 1,
        maxLines: null,
        style: theme.textTheme.headlineSmall,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.all(AppSpacing.sm),
        ),
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => unawaited(_commit(fromSubmitted: true)),
        onTapOutside: (_) => _focusNode.unfocus(),
      );
    }

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _startEditing,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(widget.title, style: theme.textTheme.headlineSmall),
        ),
      ),
    );
  }
}

class _InlineNoteEditor extends StatefulWidget {
  const _InlineNoteEditor({
    super.key,
    required this.note,
    required this.placeholder,
    required this.semanticLabel,
    required this.onSave,
  });

  final String note;
  final String placeholder;
  final String semanticLabel;
  final Future<bool> Function(String note) onSave;

  @override
  State<_InlineNoteEditor> createState() => _InlineNoteEditorState();
}

class _InlineNoteEditorState extends State<_InlineNoteEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _InlineNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.note != widget.note) {
      _controller.text = widget.note;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_editing && !_focusNode.hasFocus) {
      unawaited(_commit());
    }
  }

  void _startEditing() {
    if (_editing) {
      return;
    }
    setState(() {
      _editing = true;
      _controller.text = widget.note;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _commit() async {
    if (_saving) {
      return;
    }
    final nextNote = _controller.text;
    if (nextNote == widget.note) {
      if (mounted) {
        setState(() => _editing = false);
      }
      return;
    }
    setState(() => _saving = true);
    final saved = await widget.onSave(nextNote);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _editing = !saved;
    });
    if (!saved) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final noteStyle = theme.textTheme.bodyLarge?.copyWith(
      color: colorScheme.onSurfaceVariant,
      height: 1.35,
    );
    if (_editing) {
      return TextField(
        key: const ValueKey('task-note-inline-field'),
        controller: _controller,
        focusNode: _focusNode,
        enabled: !_saving,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        style: noteStyle,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context)!.noteLabel,
          isDense: true,
          contentPadding: const EdgeInsets.all(AppSpacing.sm),
        ),
        keyboardType: TextInputType.multiline,
        onTapOutside: (_) => _focusNode.unfocus(),
      );
    }

    final text = widget.note.isEmpty ? widget.placeholder : widget.note;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _startEditing,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(text, style: noteStyle),
        ),
      ),
    );
  }
}

class _EditableTaskMetadata extends StatelessWidget {
  const _EditableTaskMetadata({
    required this.task,
    required this.stats,
    required this.locale,
    required this.onSelectDueDate,
    required this.onClearDueDate,
    required this.onPrioritySelected,
  });

  final TaskDto task;
  final SubtaskStats stats;
  final String locale;
  final VoidCallback onSelectDueDate;
  final VoidCallback? onClearDueDate;
  final ValueChanged<int> onPrioritySelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final overdue = isTaskOverdue(task);
    final dueLabel = formatRelativeDueDate(l10n, locale, task.dueAt);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _DetailPill(
          icon: taskStatusIcon(task.status),
          label: taskStatusLabel(l10n, task.status),
        ),
        if (task.priority > 0)
          PriorityDot(
            key: ValueKey('task-priority-dot-${task.id}'),
            priority: task.priority,
            semanticLabel: l10n.taskPriority(
              taskPriorityLabel(l10n, task.priority),
            ),
            isMuted: isTaskClosed(task),
          ),
        _DetailPill(
          key: ValueKey('task-due-chip-${task.id}'),
          icon: Icons.event_outlined,
          label: dueLabel,
          tooltip: task.dueAt == null
              ? l10n.setDueDateButton
              : l10n.changeDueDateTooltip,
          semanticLabel: overdue ? l10n.taskDueOverdue(dueLabel) : null,
          emphasisColor: overdue ? priorityDotColor(3) : null,
          onTap: onSelectDueDate,
          trailing: onClearDueDate == null
              ? null
              : SizedBox.square(
                  dimension: 32,
                  child: IconButton(
                    key: ValueKey('task-clear-due-${task.id}'),
                    tooltip: l10n.clearDueDateButton,
                    icon: const Icon(Icons.clear, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: onClearDueDate,
                  ),
                ),
        ),
        PopupMenuButton<int>(
          key: ValueKey('task-priority-chip-${task.id}'),
          tooltip: l10n.changePriorityTooltip,
          onSelected: onPrioritySelected,
          itemBuilder: (context) => [
            PopupMenuItem(value: 0, child: Text(l10n.priorityNone)),
            PopupMenuItem(value: 1, child: Text(l10n.priorityLow)),
            PopupMenuItem(value: 2, child: Text(l10n.priorityMedium)),
            PopupMenuItem(value: 3, child: Text(l10n.priorityHigh)),
          ],
          child: _DetailPill(
            icon: Icons.flag_outlined,
            label: taskPriorityLabel(l10n, task.priority),
            semanticLabel: l10n.taskPriority(
              taskPriorityLabel(l10n, task.priority),
            ),
          ),
        ),
        if (stats.hasDescendants)
          _DetailPill(
            icon: Icons.account_tree_outlined,
            label: l10n.subtaskProgress(stats.doneCount, stats.totalCount),
          ),
      ],
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({
    super.key,
    required this.icon,
    required this.label,
    this.tooltip,
    this.semanticLabel,
    this.emphasisColor,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final String? semanticLabel;
  final Color? emphasisColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tint = emphasisColor ?? colorScheme.primary;
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 32,
        maxWidth: MediaQuery.sizeOf(context).width - 64,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: emphasisColor != null
                ? emphasisColor!.withValues(alpha: 0.6)
                : colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: AppSpacing.sm,
            top: AppSpacing.xs,
            end: trailing == null ? AppSpacing.sm : 0,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: theme.textTheme.labelMedium?.copyWith(color: tint),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
    final wrapped = onTap == null
        ? content
        : Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: content,
            ),
          );
    final semantics = semanticLabel == null
        ? wrapped
        : Semantics(label: semanticLabel, child: wrapped);
    if (tooltip == null) {
      return semantics;
    }
    return Tooltip(message: tooltip!, child: semantics);
  }
}
