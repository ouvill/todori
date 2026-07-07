import 'dart:async';
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
  const TaskMetadata({
    super.key,
    required this.items,
    this.priority = 0,
    this.priorityDotKey,
    this.prioritySemanticLabel,
    this.isPriorityMuted = false,
  });

  final List<TaskMetadataItem> items;
  final int priority;
  final Key? priorityDotKey;
  final String? prioritySemanticLabel;
  final bool isPriorityMuted;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && priority <= 0) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (priority > 0)
          PriorityDot(
            key: priorityDotKey,
            priority: priority,
            semanticLabel: prioritySemanticLabel,
            isMuted: isPriorityMuted,
          ),
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

class QuickAddBar extends StatefulWidget {
  const QuickAddBar({
    super.key,
    required this.hintText,
    required this.submitTooltip,
    required this.textFieldSemanticLabel,
    required this.errorMessage,
    required this.onSubmit,
  });

  final String hintText;
  final String submitTooltip;
  final String textFieldSemanticLabel;
  final String errorMessage;
  final Future<void> Function(String title) onSubmit;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _submitting = false;

  bool get _hasComposingRange {
    final range = _controller.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit({bool fromSubmitted = false}) async {
    if (_submitting) {
      return;
    }
    if (fromSubmitted && _hasComposingRange) {
      return;
    }
    final title = _controller.text.trim();
    if (title.isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(title);
      if (!mounted) {
        return;
      }
      _controller.clear();
      _focusNode.requestFocus();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(widget.errorMessage)));
      _focusNode.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ColoredBox(
          color: colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Semantics(
                        textField: true,
                        label: widget.textFieldSemanticLabel,
                        child: TextField(
                          key: const ValueKey('quick-add-field'),
                          controller: _controller,
                          focusNode: _focusNode,
                          readOnly: _submitting,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.done,
                          onEditingComplete: () {},
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) =>
                              unawaited(_submit(fromSubmitted: true)),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Tooltip(
                      message: widget.submitTooltip,
                      child: IconButton(
                        key: const ValueKey('quick-add-submit'),
                        onPressed: _submitting
                            ? null
                            : () => unawaited(_submit()),
                        icon: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
  bool includeWontDoStatus = true,
  String? listName,
}) {
  final overdue = isTaskOverdue(task);
  return [
    if (includeStatus || (includeWontDoStatus && task.status == 'wont_do'))
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
    if (listName != null)
      TaskMetadataItem(icon: Icons.list_alt_outlined, label: listName),
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

enum HomeDueDateTone { overdue, today, future }

class AppHomeTaskRow extends StatelessWidget {
  const AppHomeTaskRow({
    super.key,
    required this.title,
    required this.isDone,
    required this.listName,
    required this.dueLabel,
    required this.dueTone,
    required this.onTap,
    this.checkboxKey,
    this.priority = 0,
    this.priorityDotKey,
    this.prioritySemanticLabel,
    this.dueSemanticLabel,
    this.toggleDoneTooltip,
    this.onToggleDone,
  });

  final String title;
  final bool isDone;
  final String listName;
  final String dueLabel;
  final HomeDueDateTone dueTone;
  final Key? checkboxKey;
  final int priority;
  final Key? priorityDotKey;
  final String? prioritySemanticLabel;
  final String? dueSemanticLabel;
  final String? toggleDoneTooltip;
  final VoidCallback? onToggleDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            12,
            AppSpacing.xs,
            12,
            AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppTaskCheckbox(
                checkboxKey: checkboxKey,
                isDone: isDone,
                tooltip: toggleDoneTooltip,
                onToggleDone: onToggleDone,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _HomeListLabel(listName: listName, isMuted: isDone),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _HomeTaskTrailingMetadata(
                priority: priority,
                priorityDotKey: priorityDotKey,
                prioritySemanticLabel: prioritySemanticLabel,
                isPriorityMuted: isDone,
                dueLabel: dueLabel,
                dueSemanticLabel: dueSemanticLabel,
                dueTone: dueTone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeListLabel extends StatelessWidget {
  const _HomeListLabel({required this.listName, required this.isMuted});

  final String listName;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: isMuted ? 0.72 : 1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.list_alt_outlined, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            listName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _HomeTaskTrailingMetadata extends StatelessWidget {
  const _HomeTaskTrailingMetadata({
    required this.priority,
    required this.isPriorityMuted,
    required this.dueLabel,
    required this.dueTone,
    this.priorityDotKey,
    this.prioritySemanticLabel,
    this.dueSemanticLabel,
  });

  final int priority;
  final bool isPriorityMuted;
  final String dueLabel;
  final HomeDueDateTone dueTone;
  final Key? priorityDotKey;
  final String? prioritySemanticLabel;
  final String? dueSemanticLabel;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (priority > 0) ...[
            PriorityDot(
              key: priorityDotKey,
              priority: priority,
              semanticLabel: prioritySemanticLabel,
              isMuted: isPriorityMuted,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: _HomeDueDatePill(
              label: dueLabel,
              semanticLabel: dueSemanticLabel,
              tone: dueTone,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeDueDatePill extends StatelessWidget {
  const _HomeDueDatePill({
    required this.label,
    required this.tone,
    this.semanticLabel,
  });

  final String label;
  final HomeDueDateTone tone;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (tone) {
      HomeDueDateTone.overdue => (
        _priorityHighCoral.withValues(alpha: 0.14),
        _priorityHighCoral,
      ),
      HomeDueDateTone.today => (
        _priorityLowSoftSage.withValues(alpha: 0.26),
        theme.colorScheme.primary,
      ),
      HomeDueDateTone.future => (
        _priorityMediumAmber.withValues(alpha: 0.18),
        _priorityMediumAmber,
      ),
    };
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(color: foreground),
        ),
      ),
    );
    if (semanticLabel == null) {
      return pill;
    }
    return Semantics(label: semanticLabel, child: pill);
  }
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
    this.hierarchyGuideHorizontalKey,
    this.isLastSibling = true,
    this.ancestorLineContinuations = const <bool>[],
    this.toggleDoneTooltip,
    this.framed = true,
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
  final Key? hierarchyGuideHorizontalKey;
  final bool isLastSibling;
  final List<bool> ancestorLineContinuations;
  final String? toggleDoneTooltip;
  final List<TaskMetadataItem> metadata;
  final bool framed;
  final VoidCallback? onToggleDone;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveDepth = math.min(depth, 4);

    return Material(
      color: !framed
          ? Colors.transparent
          : isDone
          ? colorScheme.surface.withValues(alpha: 0.72)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: framed
            ? BorderSide(
                color: isDone
                    ? colorScheme.outlineVariant.withValues(alpha: 0.7)
                    : colorScheme.outlineVariant,
              )
            : BorderSide.none,
      ),
      child: Stack(
        children: [
          if (effectiveDepth > 0)
            _TaskHierarchyGuide(
              depth: effectiveDepth,
              isLastSibling: isLastSibling,
              ancestorLineContinuations: ancestorLineContinuations,
              currentVerticalKey: hierarchyGuideKey,
              horizontalKey: hierarchyGuideHorizontalKey,
            ),
          // Density-compressed row (task-30/task-43): a metadata-less task is
          // just the leading control and title; priority lives in the
          // metadata row so wrapped titles keep a stable left edge.
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
                  AppTaskCheckbox(
                    checkboxKey: checkboxKey,
                    isDone: isDone,
                    tooltip: toggleDoneTooltip,
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
                          TaskMetadata(
                            items: metadata,
                            priority: priority,
                            priorityDotKey: priorityDotKey,
                            prioritySemanticLabel: prioritySemanticLabel,
                            isPriorityMuted: isDone,
                          ),
                        ] else if (priority > 0) ...[
                          const SizedBox(height: AppSpacing.xs),
                          TaskMetadata(
                            items: const [],
                            priority: priority,
                            priorityDotKey: priorityDotKey,
                            prioritySemanticLabel: prioritySemanticLabel,
                            isPriorityMuted: isDone,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    SizedBox(height: 48, child: Center(child: trailing)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskHierarchyGuide extends StatelessWidget {
  const _TaskHierarchyGuide({
    required this.depth,
    required this.isLastSibling,
    required this.ancestorLineContinuations,
    this.currentVerticalKey,
    this.horizontalKey,
  });

  static const double _lineWidth = 1.5;
  static const double _leadingCenterY = AppSpacing.xs + 24;

  final int depth;
  final bool isLastSibling;
  final List<bool> ancestorLineContinuations;
  final Key? currentVerticalKey;
  final Key? horizontalKey;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    final children = <Widget>[];
    final ancestorCount = math.max(0, depth - 1);

    for (var level = 0; level < ancestorCount; level += 1) {
      if (level >= ancestorLineContinuations.length ||
          !ancestorLineContinuations[level]) {
        continue;
      }
      children.add(
        PositionedDirectional(
          start: _guideXForLevel(level),
          top: 0,
          bottom: 0,
          child: _GuideLine(color: color, width: _lineWidth),
        ),
      );
    }

    final currentLevel = depth - 1;
    final currentX = _guideXForLevel(currentLevel);
    children.addAll([
      PositionedDirectional(
        start: currentX,
        top: 0,
        height: _leadingCenterY,
        child: _GuideLine(
          key: currentVerticalKey,
          color: color,
          width: _lineWidth,
        ),
      ),
      if (!isLastSibling)
        PositionedDirectional(
          start: currentX,
          top: _leadingCenterY,
          bottom: 0,
          child: _GuideLine(color: color, width: _lineWidth),
        ),
      PositionedDirectional(
        start: currentX,
        top: _leadingCenterY - (_lineWidth / 2),
        child: _GuideLine(
          key: horizontalKey,
          color: color,
          width: AppSpacing.md,
          height: _lineWidth,
        ),
      ),
    ]);

    return Positioned.fill(
      child: IgnorePointer(child: Stack(children: children)),
    );
  }

  static double _guideXForLevel(int level) {
    return AppSpacing.md + (level * AppSpacing.lg) + AppSpacing.sm;
  }
}

class _GuideLine extends StatelessWidget {
  const _GuideLine({
    super.key,
    required this.color,
    required this.width,
    this.height,
  });

  final Color color;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

class AppTaskCheckbox extends StatelessWidget {
  const AppTaskCheckbox({
    super.key,
    required this.isDone,
    required this.onToggleDone,
    this.checkboxKey,
    this.tooltip,
  });

  final bool isDone;
  final VoidCallback? onToggleDone;
  final Key? checkboxKey;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final control = SizedBox(
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
                onChanged: (_) => onToggleDone?.call(),
              ),
      ),
    );
    final label = tooltip;
    if (label == null) {
      return control;
    }
    return Tooltip(
      message: label,
      child: Semantics(label: label, button: true, child: control),
    );
  }
}

/// A small priority indicator dot shown in a task metadata row. Uses the
/// design-direction accent tokens
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
