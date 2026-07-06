import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:todori/src/core/task_tree.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/theme.dart';

/// Design-direction priority accent tokens (`docs/design/visual-direction.md`
/// Design Tokens table): high=coral, medium=amber, low=softSage.
const _priorityHighCoral = Color(0xFFE8755A);
const _priorityMediumAmber = Color(0xFFEDB73E);
const _priorityLowSoftSage = Color(0xFFA8BEA8);

class TaskMetadataItem {
  const TaskMetadataItem({
    required this.icon,
    required this.label,
    this.semanticLabel,
    this.emphasisColor,
  });

  final IconData icon;
  final String label;

  /// Overrides the accessible label for this pill (e.g. to add "overdue"
  /// context that isn't carried by color alone). Defaults to the visible
  /// [label] when null.
  final String? semanticLabel;

  /// Optional accent color (e.g. coral for an overdue due date) applied to
  /// the icon and text instead of the default primary tint.
  final Color? emphasisColor;
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
          _MetadataPill(
            icon: item.icon,
            label: item.label,
            semanticLabel: item.semanticLabel,
            emphasisColor: item.emphasisColor,
          ),
      ],
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({
    required this.icon,
    required this.label,
    this.semanticLabel,
    this.emphasisColor,
  });

  final IconData icon;
  final String label;
  final String? semanticLabel;
  final Color? emphasisColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tint = emphasisColor ?? colorScheme.primary;
    final maxWidth = math.max(96.0, MediaQuery.sizeOf(context).width - 96);
    final pill = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
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
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
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
            ],
          ),
        ),
      ),
    );
    if (semanticLabel == null) {
      return pill;
    }
    return Semantics(label: semanticLabel, child: pill);
  }
}

/// Builds the metadata pills shown below a task title.
///
/// Row/subtask-row usage (the default) intentionally omits status and
/// priority pills: status is conveyed by the checkbox/strikethrough, and
/// priority by the dot next to the title. Pass [includeStatus] for the task
/// detail header, which keeps a short (unprefixed) status pill.
List<TaskMetadataItem> taskMetadataItemsFor({
  required AppLocalizations l10n,
  required String locale,
  required TaskDto task,
  required SubtaskStats stats,
  bool includeNoDueDate = false,
  bool includeStatus = false,
  bool includeSubtaskProgress = true,
}) {
  final overdue = isTaskOverdue(task);
  return [
    if (includeStatus || task.status == 'wont_do')
      TaskMetadataItem(
        icon: taskStatusIcon(task.status),
        label: taskStatusLabel(l10n, task.status),
      ),
    if (task.dueAt != null || includeNoDueDate)
      TaskMetadataItem(
        icon: Icons.event_outlined,
        label: formatRelativeDueDate(l10n, locale, task.dueAt),
        emphasisColor: overdue ? _priorityHighCoral : null,
        semanticLabel: overdue
            ? l10n.taskDueOverdue(
                formatRelativeDueDate(l10n, locale, task.dueAt),
              )
            : null,
      ),
    if (includeSubtaskProgress && stats.hasDescendants)
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

/// Formats a due date as "Today"/"Tomorrow"/a short localized date (e.g.
/// "Jul 5"), per the row Due pill convention in
/// `docs/design/visual-direction.md`. Falls back to [AppLocalizations.noDueDate]
/// when [dueAt] is null (used for the task detail header, which always shows
/// a due pill).
String formatRelativeDueDate(AppLocalizations l10n, String locale, int? dueAt) {
  if (dueAt == null) {
    return l10n.noDueDate;
  }
  final due = DateTime.fromMillisecondsSinceEpoch(dueAt).toLocal();
  final dueDate = DateTime(due.year, due.month, due.day);
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final dayDiff = dueDate.difference(todayDate).inDays;
  if (dayDiff == 0) {
    return l10n.dueToday;
  }
  if (dayDiff == 1) {
    return l10n.dueTomorrow;
  }
  return DateFormat.MMMd(locale).format(dueDate);
}

/// Whether [task] has a due date in the past and is not yet done. Used to
/// tint the Due pill coral without relying on color alone (see
/// [TaskMetadataItem.semanticLabel]).
bool isTaskOverdue(TaskDto task) {
  final dueAt = task.dueAt;
  if (dueAt == null || isTaskClosed(task)) {
    return false;
  }
  final due = DateTime.fromMillisecondsSinceEpoch(dueAt).toLocal();
  final dueDate = DateTime(due.year, due.month, due.day);
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  return dueDate.isBefore(todayDate);
}

bool isTaskClosed(TaskDto task) =>
    task.status == 'done' || task.status == 'wont_do';

IconData taskStatusIcon(String status) {
  return switch (status) {
    'done' => Icons.check_circle_outline,
    'wont_do' => Icons.do_not_disturb_on_outlined,
    'in_progress' => Icons.timelapse_outlined,
    _ => Icons.radio_button_unchecked,
  };
}

/// Formats an absolute epoch-millisecond timestamp (e.g. `Task.createdAt`)
/// as a localized calendar date, replacing the raw-epoch display bug.
String formatAbsoluteDate(String locale, int epochMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  return DateFormat.yMMMd(locale).format(date);
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
      color: isDone
          ? colorScheme.surface.withValues(alpha: 0.72)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDone
              ? colorScheme.outlineVariant.withValues(alpha: 0.7)
              : colorScheme.outlineVariant,
        ),
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
          // Density-compressed row (task-30): a metadata-less task is just
          // the leading control, priority dot, and title on one line, with
          // the trailing chevron/reorder control vertically centered at the
          // row's end rather than pushed to its own stacked row.
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.md + (effectiveDepth * AppSpacing.lg),
                top: AppSpacing.xs,
                end: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _TaskRowLeading(
                    checkboxKey: checkboxKey,
                    isDone: isDone,
                    onToggleDone: onToggleDone,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            PriorityDot(
                              key: priorityDotKey,
                              priority: priority,
                              semanticLabel: prioritySemanticLabel,
                              isMuted: isDone,
                            ),
                            Expanded(
                              child: Text(
                                title,
                                softWrap: true,
                                style: theme.textTheme.titleMedium?.copyWith(
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
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: trailing ?? const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
              ),
            ),
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
                shape: const CircleBorder(),
                onChanged: isDone ? null : (_) => onToggleDone?.call(),
              ),
      ),
    );
  }
}

/// A small priority indicator dot shown next to a task title (row context)
/// or a task detail heading. Uses the design-direction accent tokens
/// (coral/amber/softSage) and always carries a [semanticLabel] + tooltip so
/// priority meaning does not rely on color alone. Renders nothing for
/// priority "none" (0), per the design direction's dot-only convention.
class PriorityDot extends StatelessWidget {
  const PriorityDot({
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

    final color = priorityDotColor(priority);
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

/// Design-direction priority dot color for `priority` (1=low, 2=medium,
/// 3=high). Priority "none" (0 or below) is not represented by a dot at all.
Color priorityDotColor(int priority) {
  return switch (priority) {
    1 => _priorityLowSoftSage,
    2 => _priorityMediumAmber,
    3 => _priorityHighCoral,
    _ => Colors.transparent,
  };
}
