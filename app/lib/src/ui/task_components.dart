import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/core/task_tree.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/theme.dart';

/// Design-direction priority accent tokens (`docs/design/visual-direction.md`
/// Design Tokens table): high=coral, medium=amber, low=softSage.
const _priorityHighCoral = Color(0xFFE8755A);
const _priorityMediumAmber = Color(0xFFEDB73E);
const _priorityLowSoftSage = Color(0xFFA8BEA8);
const _homeTaskRowRootLeadingStart = 11.0;
const _taskRowRootLeadingStart = 12.0;
const _taskRowDepthIndent = AppSpacing.lg;
const _taskCheckboxTapSize = 48.0;
const _taskCheckboxVisualSize = 22.0;
const _taskCheckboxVisualCenterOffset = _taskCheckboxTapSize / 2;
const _taskCheckboxVisualRadius = _taskCheckboxVisualSize / 2;
const _taskHierarchyHorizontalEndGap = 4.0;
const _taskCompletionParticlesKey = ValueKey('task-completion-particles');
const _taskStrikethroughOverlayKey = ValueKey('task-strikethrough-overlay');

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
    required this.listOptions,
    required this.initialListId,
    required this.initialDueAt,
    required this.errorMessage,
    required this.onCreate,
  });

  final List<ListDto> listOptions;
  final String? initialListId;
  final int? initialDueAt;
  final String errorMessage;
  final Future<void> Function({
    required String listId,
    required String title,
    required String note,
    required int? dueAt,
  })
  onCreate;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final enabled =
        widget.initialListId != null &&
        widget.listOptions.any((list) => list.id == widget.initialListId);
    final iconOnly = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Tooltip(
        message: l10n.quickAddOpenTooltip,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: l10n.quickAddOpenSemantics,
          child: Material(
            color: enabled
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            elevation: 2,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              key: const ValueKey('quick-add-open'),
              borderRadius: BorderRadius.circular(999),
              onTap: enabled ? _openSheet : null,
              child: Padding(
                padding: iconOnly
                    ? const EdgeInsets.all(14)
                    : const EdgeInsetsDirectional.fromSTEB(16, 12, 18, 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.plus300,
                      size: 19,
                      color: enabled
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                    if (!iconOnly) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.quickAddHint,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: enabled
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.24),
      backgroundColor: Colors.transparent,
      builder: (context) => _TaskCreateSheet(
        listOptions: widget.listOptions,
        initialListId: widget.initialListId!,
        initialDueAt: widget.initialDueAt,
        errorMessage: widget.errorMessage,
        onCreate: widget.onCreate,
      ),
    );
  }
}

class _TaskCreateSheet extends StatefulWidget {
  const _TaskCreateSheet({
    required this.listOptions,
    required this.initialListId,
    required this.initialDueAt,
    required this.errorMessage,
    required this.onCreate,
  });

  final List<ListDto> listOptions;
  final String initialListId;
  final int? initialDueAt;
  final String errorMessage;
  final Future<void> Function({
    required String listId,
    required String title,
    required String note,
    required int? dueAt,
  })
  onCreate;

  @override
  State<_TaskCreateSheet> createState() => _TaskCreateSheetState();
}

class _TaskCreateSheetState extends State<_TaskCreateSheet> {
  late String _selectedListId;
  late int? _dueAt;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  bool _submitting = false;

  bool get _hasComposingRange {
    final range = _titleController.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  bool get _canSubmit =>
      !_submitting &&
      !_hasComposingRange &&
      _titleController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedListId = widget.initialListId;
    _dueAt = widget.initialDueAt;
    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onTitleChanged)
      ..dispose();
    _noteController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onCreate(
        listId: _selectedListId,
        title: _titleController.text.trim(),
        note: _noteController.text.trim(),
        dueAt: _dueAt,
      );
      if (!mounted) {
        return;
      }
      _titleController.clear();
      _noteController.clear();
      _titleFocusNode.requestFocus();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(widget.errorMessage)));
      _titleFocusNode.requestFocus();
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
    final l10n = AppLocalizations.of(context)!;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final selectedList = widget.listOptions.firstWhere(
      (list) => list.id == _selectedListId,
    );
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, -12),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const SizedBox(width: 38, height: 4),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const ValueKey('task-create-title-field'),
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    autofocus: true,
                    readOnly: _submitting,
                    textInputAction: TextInputAction.done,
                    minLines: 1,
                    maxLines: 2,
                    onEditingComplete: () {},
                    onSubmitted: (_) => unawaited(_submit()),
                    decoration: InputDecoration(
                      hintText: l10n.taskCreateTitleHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w400,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const ValueKey('task-create-note-field'),
                    controller: _noteController,
                    readOnly: _submitting,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: l10n.noteLabel,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _TaskCreateListChip(
                          selectedList: selectedList,
                          listOptions: widget.listOptions,
                          onSelected: _submitting
                              ? null
                              : (listId) =>
                                    setState(() => _selectedListId = listId),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _TaskCreateDueChip(
                          dueAt: _dueAt,
                          onTap: _submitting ? null : _showDueOptions,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const ValueKey('task-create-submit'),
                    onPressed: _canSubmit ? () => unawaited(_submit()) : null,
                    icon: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(LucideIcons.plus300),
                    label: Text(l10n.addTaskButton),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDueOptions() async {
    final selection = await showModalBottomSheet<_TaskCreateDueSelection>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => const _TaskCreateDueSheet(),
    );
    if (!mounted || selection == null) {
      return;
    }
    switch (selection) {
      case _TaskCreateDueSelection.today:
        setState(() => _dueAt = homeLocalRangesMs().todayStartMs);
        break;
      case _TaskCreateDueSelection.tomorrow:
        setState(() => _dueAt = homeLocalRangesMs().tomorrowStartMs);
        break;
      case _TaskCreateDueSelection.pickDate:
        final initialDate = _dueAt == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(_dueAt!).toLocal();
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (!mounted || picked == null) {
          return;
        }
        setState(
          () => _dueAt = DateTime(
            picked.year,
            picked.month,
            picked.day,
          ).millisecondsSinceEpoch,
        );
        break;
      case _TaskCreateDueSelection.clear:
        setState(() => _dueAt = null);
        break;
    }
    _titleFocusNode.requestFocus();
  }
}

class _TaskCreateListChip extends StatelessWidget {
  const _TaskCreateListChip({
    required this.selectedList,
    required this.listOptions,
    required this.onSelected,
  });

  final ListDto selectedList;
  final List<ListDto> listOptions;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      key: const ValueKey('task-create-list-chip'),
      tooltip: l10n.taskCreateListTooltip,
      enabled: onSelected != null,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final list in listOptions)
          PopupMenuItem<String>(
            key: ValueKey('task-create-list-option-${list.id}'),
            value: list.id,
            child: Text(list.name),
          ),
      ],
      child: _TaskCreateChip(
        icon: LucideIcons.inbox300,
        label: l10n.taskCreateListChip,
        value: selectedList.name,
        selected: true,
      ),
    );
  }
}

class _TaskCreateDueChip extends StatelessWidget {
  const _TaskCreateDueChip({required this.dueAt, required this.onTap});

  final int? dueAt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final value = formatRelativeDueDate(l10n, locale, dueAt);
    return Tooltip(
      message: l10n.taskCreateDueTooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: l10n.taskCreateDueChipSemantics(value),
        child: InkWell(
          key: const ValueKey('task-create-due-chip'),
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: _TaskCreateChip(
            icon: LucideIcons.calendarDays300,
            label: l10n.taskCreateDueChip,
            value: value,
            selected: dueAt != null,
          ),
        ),
      ),
    );
  }
}

class _TaskCreateChip extends StatelessWidget {
  const _TaskCreateChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainer.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.48)
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 2),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    96,
                    MediaQuery.sizeOf(context).width * 0.48,
                  ),
                ),
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                LucideIcons.chevronDown300,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCreateDueSheet extends StatelessWidget {
  const _TaskCreateDueSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.dueDateLabel)),
            ListTile(
              key: const ValueKey('task-create-due-today'),
              leading: const Icon(LucideIcons.calendarCheck300),
              title: Text(l10n.dueToday),
              onTap: () =>
                  Navigator.of(context).pop(_TaskCreateDueSelection.today),
            ),
            ListTile(
              key: const ValueKey('task-create-due-tomorrow'),
              leading: const Icon(LucideIcons.calendarPlus300),
              title: Text(l10n.dueTomorrow),
              onTap: () =>
                  Navigator.of(context).pop(_TaskCreateDueSelection.tomorrow),
            ),
            ListTile(
              key: const ValueKey('task-create-due-pick-date'),
              leading: const Icon(LucideIcons.calendarDays300),
              title: Text(l10n.setDueDateButton),
              onTap: () =>
                  Navigator.of(context).pop(_TaskCreateDueSelection.pickDate),
            ),
            ListTile(
              key: const ValueKey('task-create-due-clear'),
              leading: const Icon(LucideIcons.calendarX300),
              title: Text(l10n.clearDueDateButton),
              onTap: () =>
                  Navigator.of(context).pop(_TaskCreateDueSelection.clear),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TaskCreateDueSelection { today, tomorrow, pickDate, clear }

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
        icon: LucideIcons.calendarDays300,
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
        icon: LucideIcons.gitBranch300,
        label: l10n.subtaskProgress(stats.doneCount, stats.totalCount),
      ),
    if (listName != null)
      TaskMetadataItem(icon: LucideIcons.listTodo300, label: listName),
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
  return DateFormat.yMMMd(l10n.localeName).format(date);
}

String formatHomeHeaderDate(String locale, DateTime date) {
  return DateFormat.MMMEd(locale).format(date);
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
    'done' => LucideIcons.circleCheck300,
    'wont_do' => LucideIcons.ban300,
    'in_progress' => LucideIcons.clock300,
    _ => LucideIcons.circle300,
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
    required this.parentTaskName,
    required this.parentTaskSemanticLabel,
    required this.dueLabel,
    required this.dueTone,
    required this.onTap,
    this.depth = 0,
    this.semanticLabel,
    this.checkboxKey,
    this.priority = 0,
    this.priorityDotKey,
    this.prioritySemanticLabel,
    this.dueSemanticLabel,
    this.hierarchyGuideKey,
    this.hierarchyGuideHorizontalKey,
    this.isLastSibling = true,
    this.ancestorLineContinuations = const <bool>[],
    this.toggleDoneTooltip,
    this.onToggleDone,
  });

  final String title;
  final bool isDone;
  final int depth;
  final String listName;
  final String? parentTaskName;
  final String? parentTaskSemanticLabel;
  final String? dueLabel;
  final HomeDueDateTone dueTone;
  final String? semanticLabel;
  final Key? checkboxKey;
  final int priority;
  final Key? priorityDotKey;
  final String? prioritySemanticLabel;
  final String? dueSemanticLabel;
  final Key? hierarchyGuideKey;
  final Key? hierarchyGuideHorizontalKey;
  final bool isLastSibling;
  final List<bool> ancestorLineContinuations;
  final String? toggleDoneTooltip;
  final VoidCallback? onToggleDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveDepth = math.min(depth, 4);
    return Material(
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: Stack(
        children: [
          if (effectiveDepth > 0)
            _TaskHierarchyGuide(
              depth: effectiveDepth,
              isLastSibling: isLastSibling,
              ancestorLineContinuations: ancestorLineContinuations,
              rootLeadingStart: _homeTaskRowRootLeadingStart,
              currentVerticalKey: hierarchyGuideKey,
              horizontalKey: hierarchyGuideHorizontalKey,
            ),
          Semantics(
            container: true,
            explicitChildNodes: true,
            button: true,
            label: semanticLabel,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start:
                      _homeTaskRowRootLeadingStart +
                      (effectiveDepth * _taskRowDepthIndent),
                  top: AppSpacing.xs,
                  end: 12,
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
                          AppAnimatedTaskTitle(
                            title,
                            isDone: isDone,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isDone
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.onSurface,
                            ),
                          ),
                          if (parentTaskName != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _HomeParentLabel(
                              parentTaskName: parentTaskName!,
                              semanticLabel: parentTaskSemanticLabel,
                              isMuted: isDone,
                            ),
                          ] else if (listName.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _HomeListLabel(listName: listName, isMuted: isDone),
                          ],
                        ],
                      ),
                    ),
                    if (priority > 0 || dueLabel != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _HomeTaskTrailingMetadata(
                        priority: priority,
                        priorityDotKey: priorityDotKey,
                        prioritySemanticLabel: prioritySemanticLabel,
                        isPriorityMuted: isDone,
                        dueLabel: dueLabel,
                        dueSemanticLabel: dueSemanticLabel,
                        dueTone: dueTone,
                        isDueMuted: isDone,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeParentLabel extends StatelessWidget {
  const _HomeParentLabel({
    required this.parentTaskName,
    required this.semanticLabel,
    required this.isMuted,
  });

  final String parentTaskName;
  final String? semanticLabel;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: isMuted ? 0.72 : 1,
    );
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.gitBranch300, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            parentTaskName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
    if (semanticLabel == null) {
      return label;
    }
    return Semantics(container: true, label: semanticLabel, child: label);
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
        Icon(LucideIcons.listTodo300, size: 14, color: color),
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
    required this.isDueMuted,
    this.priorityDotKey,
    this.prioritySemanticLabel,
    this.dueSemanticLabel,
  });

  final int priority;
  final bool isPriorityMuted;
  final String? dueLabel;
  final HomeDueDateTone dueTone;
  final bool isDueMuted;
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
          if (dueLabel != null)
            Flexible(
              child: _HomeDueDatePill(
                label: dueLabel!,
                semanticLabel: dueSemanticLabel,
                tone: dueTone,
                isMuted: isDueMuted,
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
    required this.isMuted,
    this.semanticLabel,
  });

  final String label;
  final HomeDueDateTone tone;
  final bool isMuted;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (background, foreground) = isMuted
        ? (
            colorScheme.onSurfaceVariant.withValues(alpha: 0.10),
            colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
          )
        : switch (tone) {
            HomeDueDateTone.overdue => (
              _priorityHighCoral.withValues(alpha: 0.14),
              _priorityHighCoral,
            ),
            HomeDueDateTone.today => (
              _priorityLowSoftSage.withValues(alpha: 0.26),
              colorScheme.primary,
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
        padding: const EdgeInsetsDirectional.fromSTEB(7, 2, 7, 2),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
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

class AppTaskRow extends StatelessWidget {
  const AppTaskRow({
    super.key,
    required this.title,
    required this.isDone,
    required this.metadata,
    required this.onTap,
    this.depth = 0,
    this.semanticLabel,
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
  final String? semanticLabel;
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
              rootLeadingStart: _taskRowRootLeadingStart,
              currentVerticalKey: hierarchyGuideKey,
              horizontalKey: hierarchyGuideHorizontalKey,
            ),
          // Density-compressed row (task-30/task-43): a metadata-less task is
          // just the leading control and title; priority lives in the
          // metadata row so wrapped titles keep a stable left edge.
          Semantics(
            container: true,
            explicitChildNodes: true,
            button: true,
            label: semanticLabel,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start:
                      _taskRowRootLeadingStart +
                      (effectiveDepth * _taskRowDepthIndent),
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
                                child: AppAnimatedTaskTitle(
                                  title,
                                  isDone: isDone,
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
    required this.rootLeadingStart,
    this.currentVerticalKey,
    this.horizontalKey,
  });

  static const double _lineWidth = 1.5;
  static const double _leadingCenterY =
      AppSpacing.xs + (_taskCheckboxTapSize / 2);

  final int depth;
  final bool isLastSibling;
  final List<bool> ancestorLineContinuations;
  final double rootLeadingStart;
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
          start: _guideXForLevel(level) - (_lineWidth / 2),
          top: 0,
          bottom: 0,
          child: _GuideLine(color: color, width: _lineWidth),
        ),
      );
    }

    final currentLevel = depth - 1;
    final currentX = _guideXForLevel(currentLevel);
    final childCenterX = _checkboxCenterXForDepth(depth);
    final horizontalEndX =
        childCenterX -
        _taskCheckboxVisualRadius -
        _taskHierarchyHorizontalEndGap;
    children.addAll([
      PositionedDirectional(
        start: currentX - (_lineWidth / 2),
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
          start: currentX - (_lineWidth / 2),
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
          width: math.max(0, horizontalEndX - currentX),
          height: _lineWidth,
        ),
      ),
    ]);

    return Positioned.fill(
      child: IgnorePointer(child: Stack(children: children)),
    );
  }

  double _guideXForLevel(int level) {
    return _checkboxCenterXForDepth(level);
  }

  double _checkboxCenterXForDepth(int targetDepth) {
    if (targetDepth == 0) {
      return rootLeadingStart + _taskCheckboxVisualCenterOffset;
    }
    return rootLeadingStart +
        (targetDepth * _taskRowDepthIndent) +
        _taskCheckboxVisualCenterOffset;
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

class AppTaskCheckbox extends StatefulWidget {
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
  State<AppTaskCheckbox> createState() => _AppTaskCheckboxState();
}

class _AppTaskCheckboxState extends State<AppTaskCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _particlesController;

  @override
  void initState() {
    super.initState();
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didUpdateWidget(covariant AppTaskCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!oldWidget.isDone && widget.isDone && !reduceMotion) {
      _particlesController.forward(from: 0);
    } else if (oldWidget.isDone && !widget.isDone) {
      _particlesController.stop();
      _particlesController.value = 0;
    }
  }

  @override
  void dispose() {
    _particlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final mark = TweenAnimationBuilder<double>(
      key: ValueKey('task-checkbox-animation-${widget.checkboxKey}'),
      tween: Tween<double>(end: widget.isDone ? 1 : 0),
      duration: reduceMotion
          ? Duration.zero
          : widget.isDone
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 150),
      curve: widget.isDone ? Curves.easeOutBack : Curves.easeOutCubic,
      builder: (context, progress, child) {
        return CustomPaint(
          size: const Size.square(_taskCheckboxVisualSize),
          painter: _TaskCheckboxPainter(
            progress: progress,
            checkedColor: colorScheme.primary,
            ringColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.68),
          ),
        );
      },
    );
    final control = SizedBox(
      key: widget.checkboxKey,
      width: _taskCheckboxTapSize,
      height: _taskCheckboxTapSize,
      child: widget.onToggleDone == null
          ? _TaskCheckboxVisual(
              mark: mark,
              particles: reduceMotion
                  ? null
                  : _CompletionParticles(animation: _particlesController),
            )
          : InkResponse(
              onTap: widget.onToggleDone,
              radius: _taskCheckboxTapSize / 2,
              containedInkWell: true,
              customBorder: const CircleBorder(),
              child: _TaskCheckboxVisual(
                mark: mark,
                particles: reduceMotion
                    ? null
                    : _CompletionParticles(animation: _particlesController),
              ),
            ),
    );
    final label = widget.tooltip;
    final semanticControl = Semantics(
      label: label,
      button: true,
      checked: widget.isDone,
      enabled: widget.onToggleDone != null,
      child: control,
    );
    if (label == null) {
      return semanticControl;
    }
    return Tooltip(message: label, child: semanticControl);
  }
}

class _TaskCheckboxVisual extends StatelessWidget {
  const _TaskCheckboxVisual({required this.mark, required this.particles});

  final Widget mark;
  final Widget? particles;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (particles != null) Positioned.fill(child: particles!),
        Center(child: mark),
      ],
    );
  }
}

class _TaskCheckboxPainter extends CustomPainter {
  const _TaskCheckboxPainter({
    required this.progress,
    required this.checkedColor,
    required this.ringColor,
  });

  final double progress;
  final Color checkedColor;
  final Color ringColor;

  static const double _strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - _strokeWidth) / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = ringColor.withValues(alpha: 1 - (clampedProgress * 0.42));
    canvas.drawCircle(center, radius, ringPaint);

    if (progress <= 0) {
      return;
    }

    final fillScale = (0.78 + (progress * 0.22)).clamp(0.0, 1.08);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = checkedColor.withValues(alpha: clampedProgress);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(fillScale);
    canvas.drawCircle(Offset.zero, radius, fillPaint);
    canvas.restore();

    final checkProgress = ((progress - 0.16) / 0.84).clamp(0.0, 1.0);
    if (checkProgress <= 0) {
      return;
    }
    final checkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: checkProgress);
    final path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.35);
    final metric = path.computeMetrics().single;
    canvas.drawPath(
      metric.extractPath(0, metric.length * checkProgress),
      checkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TaskCheckboxPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.checkedColor != checkedColor ||
        oldDelegate.ringColor != ringColor;
  }
}

class _CompletionParticles extends StatelessWidget {
  const _CompletionParticles({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (animation.value == 0) {
          return const SizedBox.shrink();
        }
        return CustomPaint(
          key: _taskCompletionParticlesKey,
          painter: _CompletionParticlesPainter(
            progress: animation.value,
            colors: const [
              _priorityHighCoral,
              _priorityMediumAmber,
              _priorityLowSoftSage,
              _priorityHighCoral,
              _priorityLowSoftSage,
              _priorityMediumAmber,
              _priorityHighCoral,
              _priorityLowSoftSage,
            ],
          ),
        );
      },
    );
  }
}

class _CompletionParticlesPainter extends CustomPainter {
  const _CompletionParticlesPainter({
    required this.progress,
    required this.colors,
  });

  final double progress;
  final List<Color> colors;

  static const List<double> _angles = [
    -2.55,
    -1.95,
    -1.18,
    -0.48,
    0.16,
    0.78,
    1.46,
    2.28,
  ];
  static const List<double> _radii = [18, 21, 24, 22, 20, 24, 19, 17];

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) {
      return;
    }
    final travel = Curves.easeOutCubic.transform(t);
    final opacity = 1 - Curves.easeInCubic.transform(t);
    final origin = size.center(Offset.zero);
    for (var i = 0; i < _angles.length; i += 1) {
      final angle = _angles[i];
      final radius = _radii[i] * travel;
      final offset = Offset(math.cos(angle), math.sin(angle)) * radius;
      final particleRadius = 1.45 + (1.1 * (1 - t));
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = colors[i % colors.length].withValues(alpha: opacity);
      canvas.drawCircle(origin + offset, particleRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CompletionParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.colors != colors;
  }
}

class AppAnimatedTaskTitle extends StatefulWidget {
  const AppAnimatedTaskTitle(
    this.data, {
    super.key,
    required this.isDone,
    this.style,
    this.strutStyle,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textKey,
  });

  final String data;
  final bool isDone;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final Key? textKey;

  @override
  State<AppAnimatedTaskTitle> createState() => _AppAnimatedTaskTitleState();
}

class _AppAnimatedTaskTitleState extends State<AppAnimatedTaskTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _drawingAnimatedStrike = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _drawingAnimatedStrike = false);
          }
        });
  }

  @override
  void didUpdateWidget(covariant AppAnimatedTaskTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!oldWidget.isDone && widget.isDone && !reduceMotion) {
      setState(() => _drawingAnimatedStrike = true);
      _controller.forward(from: 0);
    } else if (oldWidget.isDone && !widget.isDone) {
      _controller.stop();
      _controller.value = 0;
      _drawingAnimatedStrike = false;
    } else if (reduceMotion && _drawingAnimatedStrike) {
      _controller.stop();
      _controller.value = 1;
      _drawingAnimatedStrike = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final drawAnimatedStrike =
        widget.isDone && _drawingAnimatedStrike && !reduceMotion;
    final drawStrike = widget.isDone;
    final effectiveStyle = drawStrike
        ? widget.style?.copyWith(decoration: TextDecoration.none)
        : widget.style;
    final text = Text(
      widget.data,
      key: widget.textKey,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
      strutStyle: widget.strutStyle,
      style: effectiveStyle,
    );
    if (!drawStrike) {
      return text;
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        text,
        Positioned.fill(
          key: _taskStrikethroughOverlayKey,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final strikeProgress = drawAnimatedStrike
                    ? Curves.easeOutCubic.transform(_controller.value)
                    : 1.0;
                return CustomPaint(
                  painter: _AnimatedStrikethroughPainter(
                    text: widget.data,
                    style: widget.style,
                    strutStyle: widget.strutStyle,
                    maxLines: widget.maxLines,
                    overflow: widget.overflow,
                    textDirection: Directionality.of(context),
                    locale: Localizations.maybeLocaleOf(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    progress: strikeProgress,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedStrikethroughPainter extends CustomPainter {
  const _AnimatedStrikethroughPainter({
    required this.text,
    required this.style,
    required this.strutStyle,
    required this.maxLines,
    required this.overflow,
    required this.textDirection,
    required this.locale,
    required this.textScaler,
    required this.progress,
  });

  final String text;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextDirection textDirection;
  final Locale? locale;
  final TextScaler textScaler;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = (style ?? const TextStyle()).copyWith(
      decoration: TextDecoration.none,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: textDirection,
      maxLines: maxLines,
      ellipsis: overflow == TextOverflow.ellipsis ? '\u2026' : null,
      locale: locale,
      strutStyle: strutStyle,
      textScaler: textScaler,
    )..layout(maxWidth: size.width);
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) {
      return;
    }

    final strikeColor =
        style?.decorationColor ?? style?.color ?? const Color(0xFF000000);
    final fontSize = textStyle.fontSize ?? 14;
    final strokeWidth = math.max(
      1.0,
      (style?.decorationThickness ?? 1.0) * (fontSize / 14),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = strikeColor;
    final scaledProgress = (progress.clamp(0.0, 1.0)) * lines.length;
    for (var i = 0; i < lines.length; i += 1) {
      final lineProgress = (scaledProgress - i).clamp(0.0, 1.0);
      if (lineProgress <= 0) {
        continue;
      }
      final line = lines[i];
      final startX = line.left;
      final endX = startX + (line.width * lineProgress);
      final y = line.baseline - (line.ascent * 0.34);
      canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedStrikethroughPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.strutStyle != strutStyle ||
        oldDelegate.maxLines != maxLines ||
        oldDelegate.overflow != overflow ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.locale != locale ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.progress != progress;
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
