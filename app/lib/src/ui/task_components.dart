import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:todori/src/core/task_tree.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/theme.dart';

class TaskMetadataItem {
  const TaskMetadataItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class TaskMetadata extends StatelessWidget {
  const TaskMetadata({super.key, required this.items});

  final List<TaskMetadataItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final item in items)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(item.icon, size: 16),
            label: Text(item.label),
          ),
      ],
    );
  }
}

List<TaskMetadataItem> taskMetadataItemsFor({
  required AppLocalizations l10n,
  required TaskDto task,
  required SubtaskStats stats,
  bool includeNoDueDate = false,
  bool includePriorityNone = false,
}) {
  return [
    TaskMetadataItem(
      icon: task.status == 'done'
          ? Icons.check_circle_outline
          : Icons.radio_button_unchecked,
      label: l10n.taskStatus(taskStatusLabel(l10n, task.status)),
    ),
    if (task.priority > 0 || includePriorityNone)
      TaskMetadataItem(
        icon: Icons.flag_outlined,
        label: l10n.taskPriority(taskPriorityLabel(l10n, task.priority)),
      ),
    if (task.dueAt != null || includeNoDueDate)
      TaskMetadataItem(
        icon: Icons.event_outlined,
        label: l10n.taskDueAt(formatDueDate(l10n, task.dueAt)),
      ),
    if (stats.hasDescendants)
      TaskMetadataItem(
        icon: Icons.account_tree_outlined,
        label: l10n.subtaskProgress(stats.doneCount, stats.totalCount),
      ),
  ];
}

String taskStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'todo' => l10n.statusTodo,
    'in_progress' => l10n.statusInProgress,
    'done' => l10n.statusDone,
    'wont_do' => l10n.statusWontDo,
    _ => status,
  };
}

String taskPriorityLabel(AppLocalizations l10n, int priority) {
  return switch (priority) {
    1 => l10n.priorityLow,
    2 => l10n.priorityMedium,
    3 => l10n.priorityHigh,
    _ => l10n.priorityNone,
  };
}

String formatDueDate(AppLocalizations l10n, int? dueAt) {
  if (dueAt == null) {
    return l10n.noDueDate;
  }
  final date = DateTime.fromMillisecondsSinceEpoch(dueAt).toLocal();
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class AppTaskRow extends StatelessWidget {
  const AppTaskRow({
    super.key,
    required this.title,
    required this.isDone,
    required this.metadata,
    required this.onTap,
    this.depth = 0,
    this.checkboxKey,
    this.onToggleDone,
  });

  final String title;
  final bool isDone;
  final int depth;
  final Key? checkboxKey;
  final List<TaskMetadataItem> metadata;
  final VoidCallback? onToggleDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveDepth = math.min(depth, 4);

    return ListTile(
      contentPadding: EdgeInsetsDirectional.only(
        start: AppSpacing.md + (effectiveDepth * AppSpacing.lg),
        end: AppSpacing.md,
      ),
      leading: onToggleDone == null
          ? Icon(
              isDone
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
              color: isDone
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            )
          : Checkbox(
              key: checkboxKey,
              value: isDone,
              onChanged: isDone ? null : (_) => onToggleDone?.call(),
            ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          decoration: isDone ? TextDecoration.lineThrough : null,
          color: isDone ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
        ),
      ),
      subtitle: metadata.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: TaskMetadata(items: metadata),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
