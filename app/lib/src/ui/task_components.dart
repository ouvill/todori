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
          _MetadataPill(icon: item.icon, label: item.label),
      ],
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxWidth = math.max(96.0, MediaQuery.sizeOf(context).width - 96);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
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
    this.priority = 0,
    this.priorityDotKey,
    this.prioritySemanticLabel,
    this.hierarchyGuideKey,
    this.onToggleDone,
    this.trailing,
  });

  final String title;
  final bool isDone;
  final int depth;
  final Key? checkboxKey;
  final int priority;
  final Key? priorityDotKey;
  final String? prioritySemanticLabel;
  final Key? hierarchyGuideKey;
  final List<TaskMetadataItem> metadata;
  final VoidCallback? onToggleDone;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveDepth = math.min(depth, 4);
    final hierarchyLineStart =
        AppSpacing.md + ((effectiveDepth - 1) * AppSpacing.lg) + AppSpacing.sm;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Stack(
        children: [
          if (effectiveDepth > 0) ...[
            PositionedDirectional(
              start: hierarchyLineStart,
              top: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: DecoratedBox(
                key: hierarchyGuideKey,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const SizedBox(width: 1.5),
              ),
            ),
            PositionedDirectional(
              start: hierarchyLineStart,
              top: 35,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const SizedBox(width: AppSpacing.md, height: 1.5),
              ),
            ),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final effectiveTrailing =
                  trailing ?? const Icon(Icons.chevron_right);
              final stackTrailing =
                  trailing != null &&
                  (constraints.maxWidth < 360 || textScale > 1.25);
              final rowTrailing = stackTrailing ? null : effectiveTrailing;
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TaskRowLeading(
                        checkboxKey: checkboxKey,
                        isDone: isDone,
                        onToggleDone: onToggleDone,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _PriorityDot(
                                  key: priorityDotKey,
                                  priority: priority,
                                  semanticLabel: prioritySemanticLabel,
                                  isMuted: isDone,
                                ),
                                Expanded(
                                  child: Text(
                                    title,
                                    softWrap: true,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          decoration: isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: isDone
                                              ? colorScheme.onSurfaceVariant
                                              : colorScheme.onSurface,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            if (metadata.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              TaskMetadata(items: metadata),
                            ],
                          ],
                        ),
                      ),
                      if (rowTrailing != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: rowTrailing,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (stackTrailing) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: effectiveTrailing,
                    ),
                  ],
                ],
              );

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: AppSpacing.md + (effectiveDepth * AppSpacing.lg),
                    top: AppSpacing.sm,
                    end: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  child: content,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TaskRowLeading extends StatelessWidget {
  const _TaskRowLeading({
    required this.isDone,
    required this.onToggleDone,
    this.checkboxKey,
  });

  final bool isDone;
  final VoidCallback? onToggleDone;
  final Key? checkboxKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: onToggleDone == null
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
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({
    super.key,
    required this.priority,
    this.semanticLabel,
    required this.isMuted,
  });

  final int priority;
  final String? semanticLabel;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    if (priority <= 0) {
      return const SizedBox.shrink();
    }

    final color = _priorityDotColor(context, priority);
    final dot = Container(
      width: 11,
      height: 11,
      margin: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isMuted ? color.withValues(alpha: 0.45) : color,
        shape: BoxShape.circle,
      ),
    );

    final label = semanticLabel;
    if (label == null) {
      return dot;
    }

    return Tooltip(
      message: label,
      child: Semantics(label: label, child: dot),
    );
  }
}

Color _priorityDotColor(BuildContext context, int priority) {
  final brightness = Theme.of(context).colorScheme.brightness;
  return switch (priority) {
    1 =>
      brightness == Brightness.light
          ? const Color(0xFF60C894)
          : const Color(0xFF7ED9AA),
    2 =>
      brightness == Brightness.light
          ? const Color(0xFFB7C900)
          : const Color(0xFFD5E84B),
    3 =>
      brightness == Brightness.light
          ? const Color(0xFFFF6B5F)
          : const Color(0xFFFF9B91),
    _ => Theme.of(context).colorScheme.outline,
  };
}

class AppProtectionSignal extends StatelessWidget {
  const AppProtectionSignal({
    super.key,
    required this.label,
    required this.tooltip,
  });

  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 16, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
