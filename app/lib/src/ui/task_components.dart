import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/core/task_due.dart';
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
const _taskCompletionHaloKey = ValueKey('task-completion-halo');
const _taskStrikethroughOverlayKey = ValueKey('task-strikethrough-overlay');

typedef TaskCreateCallback =
    Future<void> Function({
      required String listId,
      required String title,
      required String note,
      required TaskDueDto? due,
    });

Future<void> showTaskCreateSheet({
  required BuildContext context,
  required List<ListDto> listOptions,
  required String initialListId,
  required TaskDueDto? initialDue,
  required String errorMessage,
  required TaskCreateCallback onCreate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.24),
    backgroundColor: Colors.transparent,
    builder: (context) => TaskCreateSheet(
      listOptions: listOptions,
      initialListId: initialListId,
      initialDue: initialDue,
      errorMessage: errorMessage,
      onCreate: onCreate,
    ),
  );
}

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
        for (final item in items) _TaskMetadataLabel(item: item),
      ],
    );
  }
}

class _TaskMetadataLabel extends StatelessWidget {
  const _TaskMetadataLabel({required this.item});

  final TaskMetadataItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(
        color: item.emphasisColor ?? theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
    return item.semanticLabel == null
        ? label
        : Semantics(label: item.semanticLabel, child: label);
  }
}

class CircularCaptureAction extends StatelessWidget {
  const CircularCaptureAction({
    super.key,
    required this.listOptions,
    required this.initialListId,
    required this.initialDue,
    required this.errorMessage,
    required this.onCreate,
    this.size = 52,
  });

  final List<ListDto> listOptions;
  final String? initialListId;
  final TaskDueDto? initialDue;
  final String errorMessage;
  final TaskCreateCallback onCreate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final enabled =
        initialListId != null &&
        listOptions.any((list) => list.id == initialListId);
    return Tooltip(
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
          shadowColor: colorScheme.shadow.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            key: const ValueKey('quick-add-open'),
            customBorder: const CircleBorder(),
            onTap: !enabled
                ? null
                : () => showTaskCreateSheet(
                    context: context,
                    listOptions: listOptions,
                    initialListId: initialListId!,
                    initialDue: initialDue,
                    errorMessage: errorMessage,
                    onCreate: onCreate,
                  ),
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                LucideIcons.plus300,
                size: 20,
                color: enabled
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickAddBar extends StatefulWidget {
  const QuickAddBar({
    super.key,
    required this.listOptions,
    required this.initialListId,
    required this.initialDue,
    required this.errorMessage,
    required this.onCreate,
  });

  final List<ListDto> listOptions;
  final String? initialListId;
  final TaskDueDto? initialDue;
  final String errorMessage;
  final Future<void> Function({
    required String listId,
    required String title,
    required String note,
    required TaskDueDto? due,
  })
  onCreate;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: CircularCaptureAction(
        listOptions: widget.listOptions,
        initialListId: widget.initialListId,
        initialDue: widget.initialDue,
        errorMessage: widget.errorMessage,
        onCreate: widget.onCreate,
      ),
    );
  }
}

class TaskCreateSheet extends StatefulWidget {
  const TaskCreateSheet({
    super.key,
    required this.listOptions,
    required this.initialListId,
    required this.initialDue,
    required this.errorMessage,
    required this.onCreate,
  });

  final List<ListDto> listOptions;
  final String initialListId;
  final TaskDueDto? initialDue;
  final String errorMessage;
  final Future<void> Function({
    required String listId,
    required String title,
    required String note,
    required TaskDueDto? due,
  })
  onCreate;

  @override
  State<TaskCreateSheet> createState() => _TaskCreateSheetState();
}

class _TaskCreateSheetState extends State<TaskCreateSheet> {
  late String _selectedListId;
  late TaskDueDto? _due;
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
    _due = widget.initialDue;
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
        due: _due,
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
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
                          due: _due,
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
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _TaskCreateDueSheet(),
    );
    if (!mounted || selection == null) {
      return;
    }
    switch (selection) {
      case _TaskCreateDueSelection.today:
        setState(() => _due = dateOnlyDue(DateTime.now()));
        break;
      case _TaskCreateDueSelection.tomorrow:
        setState(
          () => _due = dateOnlyDue(DateTime.now().add(const Duration(days: 1))),
        );
        break;
      case _TaskCreateDueSelection.pickDate:
        final initialDate = _due == null
            ? DateTime.now()
            : taskDueDisplayDate(_due!);
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (!mounted || picked == null) {
          return;
        }
        setState(() => _due = dateOnlyDue(picked));
        break;
      case _TaskCreateDueSelection.pickDateTime:
        final initial = _due == null
            ? DateTime.now()
            : taskDueDisplayDate(_due!);
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (!mounted || pickedDate == null) {
          return;
        }
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initial),
        );
        if (!mounted || pickedTime == null) {
          return;
        }
        final localDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        if (localDateTime.year != pickedDate.year ||
            localDateTime.month != pickedDate.month ||
            localDateTime.day != pickedDate.day ||
            localDateTime.hour != pickedTime.hour ||
            localDateTime.minute != pickedTime.minute) {
          return;
        }
        final savedTimeZone = taskDueSavedTimeZone(_due);
        final timeZone =
            savedTimeZone ??
            await ProviderScope.containerOf(
              context,
              listen: false,
            ).read(bridgeServiceProvider).getLocalTimeZone();
        if (!mounted) {
          return;
        }
        TaskDueDto exactDue;
        try {
          exactDue = dateTimeDue(
            localDateTime: localDateTime,
            timeZone: timeZone,
          );
        } on FormatException {
          return;
        }
        setState(() => _due = exactDue);
        break;
      case _TaskCreateDueSelection.clear:
        setState(() => _due = null);
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
  const _TaskCreateDueChip({required this.due, required this.onTap});

  final TaskDueDto? due;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final value = formatRelativeDueDate(l10n, locale, due);
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
            selected: due != null,
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
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
            key: const ValueKey('task-create-due-pick-date-time'),
            leading: const Icon(LucideIcons.calendarClock300),
            title: Text(l10n.setDueDateTimeButton),
            onTap: () =>
                Navigator.of(context).pop(_TaskCreateDueSelection.pickDateTime),
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
    );
  }
}

enum _TaskCreateDueSelection { today, tomorrow, pickDate, pickDateTime, clear }

/// Builds the compact metadata labels shown below a task title.
///
/// Row/subtask-row usage (the default) intentionally omits status and
/// priority labels: status is conveyed by the checkbox/strikethrough, and
/// priority by the metadata dot. Pass [includeStatus] where status text is
/// explicitly required.
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
    if (task.due != null || includeNoDueDate)
      TaskMetadataItem(
        icon: LucideIcons.calendarDays300,
        label: formatRelativeDueDate(l10n, locale, task.due),
        emphasisColor: overdue ? _priorityHighCoral : null,
        semanticLabel: overdue
            ? l10n.taskDueOverdue(formatRelativeDueDate(l10n, locale, task.due))
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

String formatDueDate(AppLocalizations l10n, TaskDueDto? due) {
  if (due == null) {
    return l10n.noDueDate;
  }
  final date = taskDueDisplayDate(due);
  final dateLabel = DateFormat.yMMMd(l10n.localeName).format(date);
  if (taskDueIsDateOnly(due)) {
    return dateLabel;
  }
  final timeZone = taskDueSavedTimeZone(due)!;
  return '$dateLabel · ${DateFormat.jm(l10n.localeName).format(date)} '
      '$timeZone (${taskDueUtcOffsetLabel(date)})';
}

String formatHomeHeaderDate(String locale, DateTime date) {
  return DateFormat.MMMEd(locale).format(date);
}

/// Formats a due date as "Today"/"Tomorrow"/a short localized date (e.g.
/// "Jul 5"), per the row Due pill convention in
/// `docs/design/visual-direction.md`. Falls back to [AppLocalizations.noDueDate]
/// when [due] is null (used for the task detail header, which always shows
/// a due pill).
String formatRelativeDueDate(
  AppLocalizations l10n,
  String locale,
  TaskDueDto? due,
) {
  if (due == null) {
    return l10n.noDueDate;
  }
  final dueDateTime = taskDueDisplayDate(due);
  final dueDate = DateTime(
    dueDateTime.year,
    dueDateTime.month,
    dueDateTime.day,
  );
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final dayDiff = DateTime.utc(dueDate.year, dueDate.month, dueDate.day)
      .difference(DateTime.utc(todayDate.year, todayDate.month, todayDate.day))
      .inDays;
  final dateLabel = switch (dayDiff) {
    0 => l10n.dueToday,
    1 => l10n.dueTomorrow,
    _ => DateFormat.MMMd(locale).format(dueDate),
  };
  if (taskDueIsDateOnly(due)) {
    return dateLabel;
  }
  final timeZone = taskDueSavedTimeZone(due)!;
  return '$dateLabel · ${DateFormat.jm(locale).format(dueDateTime)} '
      '$timeZone (${taskDueUtcOffsetLabel(dueDateTime)})';
}

/// Whether [task] has a due date in the past and is not yet done. Used to
/// tint the Due pill coral without relying on color alone (see
/// [TaskMetadataItem.semanticLabel]).
bool isTaskOverdue(TaskDto task) {
  if (task.due == null || isTaskClosed(task)) {
    return false;
  }
  return taskDueIsOverdue(task.due);
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTaskCheckbox(
                      checkboxKey: checkboxKey,
                      isDone: isDone,
                      tooltip: toggleDoneTooltip,
                      onToggleDone: onToggleDone,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 13, bottom: 3),
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
                            if (parentTaskName != null ||
                                listName.isNotEmpty ||
                                priority > 0 ||
                                dueLabel != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              _HomeTaskMetadata(
                                priority: priority,
                                priorityDotKey: priorityDotKey,
                                prioritySemanticLabel: prioritySemanticLabel,
                                parentTaskName: parentTaskName,
                                parentTaskSemanticLabel:
                                    parentTaskSemanticLabel,
                                listName: listName,
                                dueLabel: dueLabel,
                                dueSemanticLabel: dueSemanticLabel,
                                dueTone: dueTone,
                                isMuted: isDone,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
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

class _HomeTaskMetadata extends StatelessWidget {
  const _HomeTaskMetadata({
    required this.priority,
    required this.parentTaskName,
    required this.parentTaskSemanticLabel,
    required this.listName,
    required this.dueLabel,
    required this.dueTone,
    required this.isMuted,
    this.priorityDotKey,
    this.prioritySemanticLabel,
    this.dueSemanticLabel,
  });

  final int priority;
  final String? parentTaskName;
  final String? parentTaskSemanticLabel;
  final String listName;
  final String? dueLabel;
  final HomeDueDateTone dueTone;
  final bool isMuted;
  final Key? priorityDotKey;
  final String? prioritySemanticLabel;
  final String? dueSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultColor = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: isMuted ? 0.78 : 1,
    );
    final contextLabel = parentTaskName ?? (listName.isEmpty ? null : listName);
    final contextSemantics = parentTaskName == null
        ? null
        : parentTaskSemanticLabel;
    final dueColor = isMuted
        ? defaultColor
        : switch (dueTone) {
            HomeDueDateTone.overdue => _priorityHighCoral,
            _ => defaultColor,
          };
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (priority > 0)
          PriorityDot(
            key: priorityDotKey,
            priority: priority,
            semanticLabel: prioritySemanticLabel,
            isMuted: isMuted,
          ),
        if (contextLabel != null)
          Semantics(
            label: contextSemantics,
            child: Text(
              contextLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: defaultColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (contextLabel != null && dueLabel != null)
          Text(
            '·',
            style: theme.textTheme.labelMedium?.copyWith(color: defaultColor),
          ),
        if (dueLabel != null)
          Semantics(
            label: dueSemanticLabel,
            child: Text(
              dueLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: dueColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
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
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTaskCheckbox(
                      checkboxKey: checkboxKey,
                      isDone: isDone,
                      tooltip: toggleDoneTooltip,
                      onToggleDone: onToggleDone,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 13, bottom: 3),
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
    with TickerProviderStateMixin {
  late final AnimationController _completionController;
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: widget.isDone ? 1 : 0,
    );
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
  }

  @override
  void didUpdateWidget(covariant AppTaskCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!oldWidget.isDone && widget.isDone && !reduceMotion) {
      _completionController.forward(from: 0);
    } else if (oldWidget.isDone && !widget.isDone) {
      _completionController
        ..stop()
        ..value = 0;
    } else if (reduceMotion) {
      _completionController.value = widget.isDone ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _completionController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final mark = AnimatedBuilder(
      key: ValueKey('task-checkbox-animation-${widget.checkboxKey}'),
      animation: Listenable.merge([_completionController, _pressController]),
      builder: (context, child) {
        final timeline = widget.isDone
            ? (reduceMotion ? 1.0 : _completionController.value)
            : 0.0;
        final fillProgress = Curves.easeOutCubic.transform(
          (timeline / (200 / 520)).clamp(0.0, 1.0),
        );
        final checkProgress = Curves.easeOutCubic.transform(
          ((timeline - (130 / 520)) / (330 / 520)).clamp(0.0, 1.0),
        );
        return CustomPaint(
          size: const Size.square(_taskCheckboxVisualSize),
          painter: _TaskCheckboxPainter(
            fillProgress: fillProgress,
            checkProgress: checkProgress,
            pressProgress: _pressController.value,
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
              halo: reduceMotion
                  ? null
                  : _CompletionHalo(animation: _completionController),
            )
          : InkResponse(
              onTap: _handleTap,
              radius: _taskCheckboxTapSize / 2,
              containedInkWell: true,
              customBorder: const CircleBorder(),
              child: _TaskCheckboxVisual(
                mark: mark,
                halo: reduceMotion
                    ? null
                    : _CompletionHalo(animation: _completionController),
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

  void _handleTap() {
    if (widget.onToggleDone == null) {
      return;
    }
    _pressController.forward(from: 0).then((_) {
      if (mounted) {
        _pressController.reverse();
      }
    });
    if (!widget.isDone && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(HapticFeedback.lightImpact());
    }
    widget.onToggleDone!();
  }
}

class _TaskCheckboxVisual extends StatelessWidget {
  const _TaskCheckboxVisual({required this.mark, required this.halo});

  final Widget mark;
  final Widget? halo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (halo != null) Positioned.fill(child: halo!),
        Center(child: mark),
      ],
    );
  }
}

class _TaskCheckboxPainter extends CustomPainter {
  const _TaskCheckboxPainter({
    required this.fillProgress,
    required this.checkProgress,
    required this.pressProgress,
    required this.checkedColor,
    required this.ringColor,
  });

  final double fillProgress;
  final double checkProgress;
  final double pressProgress;
  final Color checkedColor;
  final Color ringColor;

  static const double _ringStrokeWidth = 1;
  static const double _checkStrokeWidth = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final clampedFill = fillProgress.clamp(0.0, 1.0);
    final clampedCheck = checkProgress.clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - _ringStrokeWidth) / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStrokeWidth + (pressProgress * 0.35)
      ..strokeCap = StrokeCap.round
      ..color = ringColor.withValues(alpha: 1 - (clampedFill * 0.42));
    canvas.drawCircle(center, radius, ringPaint);

    if (clampedFill <= 0) {
      return;
    }

    final fillScale = (0.82 + (clampedFill * 0.18)).clamp(0.0, 1.0);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = checkedColor.withValues(alpha: clampedFill);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(fillScale);
    canvas.drawCircle(Offset.zero, radius, fillPaint);
    canvas.restore();

    if (clampedCheck <= 0) {
      return;
    }
    final checkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _checkStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: clampedCheck);
    final path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.35);
    final metric = path.computeMetrics().single;
    canvas.drawPath(
      metric.extractPath(0, metric.length * clampedCheck),
      checkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TaskCheckboxPainter oldDelegate) {
    return oldDelegate.fillProgress != fillProgress ||
        oldDelegate.checkProgress != checkProgress ||
        oldDelegate.pressProgress != pressProgress ||
        oldDelegate.checkedColor != checkedColor ||
        oldDelegate.ringColor != ringColor;
  }
}

class _CompletionHalo extends StatelessWidget {
  const _CompletionHalo({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (animation.value == 0 || animation.value == 1) {
          return const SizedBox.shrink();
        }
        return CustomPaint(
          key: _taskCompletionHaloKey,
          painter: _CompletionHaloPainter(
            progress: animation.value,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

class _CompletionHaloPainter extends CustomPainter {
  const _CompletionHaloPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = ((progress - 0.22) / 0.78).clamp(0.0, 1.0);
    if (raw <= 0) {
      return;
    }
    final travel = Curves.easeOutCubic.transform(raw);
    final opacity = (1 - Curves.easeInCubic.transform(raw)) * 0.42;
    final origin = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: opacity);
    canvas.drawCircle(origin, 11 + (10 * travel), paint);
  }

  @override
  bool shouldRepaint(covariant _CompletionHaloPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
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
          duration: const Duration(milliseconds: 460),
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
                    ? Curves.easeOutCubic.transform(
                        ((_controller.value - (130 / 460)) / (330 / 460)).clamp(
                          0.0,
                          1.0,
                        ),
                      )
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
