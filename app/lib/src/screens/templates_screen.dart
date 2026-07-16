import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/theme.dart';

class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  bool _loading = true;
  Object? _error;
  List<TemplateDto> _templates = const [];
  List<ListDto> _lists = const [];
  final Map<String, List<ScheduleDto>> _schedules = {};
  final Map<String, StreakDto> _streaks = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bridge = ref.read(bridgeServiceProvider);
      final templates = await bridge.getTemplates();
      final lists = await bridge.getLists();
      final schedules = <String, List<ScheduleDto>>{};
      final streaks = <String, StreakDto>{};
      for (final template in templates) {
        final values = await bridge.getTemplateSchedules(
          templateId: template.id,
        );
        schedules[template.id] = values;
        for (final schedule in values) {
          streaks[schedule.id] = await bridge.getScheduleStreak(
            scheduleId: schedule.id,
            atMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _lists = lists;
        _schedules
          ..clear()
          ..addAll(schedules);
        _streaks
          ..clear()
          ..addAll(streaks);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.backButtonTooltip,
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft300),
        ),
        title: Text(l10n.templatesTitle),
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoadingState()
            : _error != null
            ? AppErrorState(
                message: l10n.templatesLoadFailed(_error.toString()),
              )
            : RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  children: [
                    if (_templates.isEmpty)
                      AppEmptyState(
                        icon: LucideIcons.copyPlus300,
                        title: l10n.templatesEmptyTitle,
                        body: l10n.templatesEmptyBody,
                      )
                    else
                      for (final template in _templates)
                        _TemplateCard(
                          template: template,
                          schedules: _schedules[template.id] ?? const [],
                          streaks: _streaks,
                          lists: _lists,
                          onChanged: _reload,
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({
    required this.template,
    required this.schedules,
    required this.streaks,
    required this.lists,
    required this.onChanged,
  });

  final TemplateDto template;
  final List<ScheduleDto> schedules;
  final Map<String, StreakDto> streaks;
  final List<ListDto> lists;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.templateActionsTooltip,
                  onSelected: (value) =>
                      _handleTemplateAction(context, ref, value),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'edit', child: Text(l10n.editButton)),
                    PopupMenuItem(
                      value: 'replace',
                      child: Text(l10n.replaceTemplateSnapshotMenuItem),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(l10n.deleteButton),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              l10n.templateTaskCount(template.nodes.length),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _instantiate(context, ref),
                    icon: const Icon(LucideIcons.play300),
                    label: Text(l10n.createFromTemplateButton),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filledTonal(
                  tooltip: l10n.addScheduleTooltip,
                  onPressed: () => _editSchedule(context, ref),
                  icon: const Icon(LucideIcons.calendarPlus300),
                ),
              ],
            ),
            if (schedules.isNotEmpty) ...[
              const Divider(height: AppSpacing.xl),
              for (final schedule in schedules)
                _ScheduleRow(
                  schedule: schedule,
                  streak: streaks[schedule.id],
                  onEdit: () => _editSchedule(context, ref, schedule),
                  onToggle: () => _toggleSchedule(context, ref, schedule),
                  onDelete: () => _deleteSchedule(context, ref, schedule),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _instantiate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    await ref
        .read(bridgeServiceProvider)
        .instantiateTemplate(templateId: template.id);
    ref.invalidate(listsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.templateCreatedMessage)));
    }
  }

  Future<void> _handleTemplateAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    if (action == 'edit') {
      final value = await _showTemplateEditDialog(context, template, lists);
      if (value == null) return;
      await ref
          .read(bridgeServiceProvider)
          .updateTemplate(
            templateId: template.id,
            name: value.name,
            defaultListId: value.defaultListId,
          );
    } else if (action == 'replace') {
      final taskId = await _showTaskIdDialog(context);
      if (taskId == null) return;
      await ref
          .read(bridgeServiceProvider)
          .replaceTemplateSnapshot(templateId: template.id, taskId: taskId);
    } else if (action == 'delete') {
      final confirmed = await _confirmTemplateDelete(context, template.name);
      if (!confirmed) return;
      await ref
          .read(bridgeServiceProvider)
          .deleteTemplate(templateId: template.id);
    }
    await onChanged();
  }

  Future<void> _editSchedule(
    BuildContext context,
    WidgetRef ref, [
    ScheduleDto? schedule,
  ]) async {
    final bridge = ref.read(bridgeServiceProvider);
    final defaultTimeZone =
        schedule?.timeZone ?? await bridge.getLocalTimeZone();
    if (!context.mounted) return;
    final input = await _showScheduleDialog(context, schedule, defaultTimeZone);
    if (input == null) return;
    try {
      await bridge.validateRecurrenceRule(
        rrule: input.rrule,
        startsAt: input.startsAt,
        timeZone: input.timeZone,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.scheduleValidationFailed,
            ),
          ),
        );
      }
      return;
    }
    if (schedule == null) {
      await bridge.createSchedule(
        templateId: template.id,
        rrule: input.rrule,
        startsAt: input.startsAt,
        timeZone: input.timeZone,
      );
    } else {
      await bridge.updateSchedule(
        scheduleId: schedule.id,
        rrule: input.rrule,
        startsAt: input.startsAt,
        timeZone: input.timeZone,
        enabled: input.enabled,
      );
    }
    await onChanged();
  }

  Future<void> _toggleSchedule(
    BuildContext context,
    WidgetRef ref,
    ScheduleDto schedule,
  ) async {
    await ref
        .read(bridgeServiceProvider)
        .updateSchedule(
          scheduleId: schedule.id,
          rrule: schedule.rrule,
          startsAt: schedule.startsAt,
          timeZone: schedule.timeZone,
          enabled: !schedule.enabled,
        );
    await onChanged();
  }

  Future<void> _deleteSchedule(
    BuildContext context,
    WidgetRef ref,
    ScheduleDto schedule,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteScheduleDialogTitle),
        content: Text(l10n.deleteScheduleDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(bridgeServiceProvider)
        .deleteSchedule(scheduleId: schedule.id);
    await onChanged();
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.schedule,
    required this.streak,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final ScheduleDto schedule;
  final StreakDto? streak;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final next = schedule.nextRunAt == null
        ? l10n.scheduleEndedLabel
        : DateFormat.yMMMd(locale).add_jm().format(
            DateTime.fromMillisecondsSinceEpoch(schedule.nextRunAt!),
          );
    return Semantics(
      label: l10n.scheduleSemantics(schedule.rrule, next),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          schedule.enabled ? LucideIcons.repeat2300 : LucideIcons.pause300,
        ),
        title: Text(schedule.rrule),
        subtitle: Text(
          streak == null || streak!.current == 0
              ? next
              : '$next · ${l10n.scheduleStreak(streak!.current)}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: l10n.scheduleActionsTooltip,
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'toggle') onToggle();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'edit', child: Text(l10n.editButton)),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                schedule.enabled
                    ? l10n.pauseScheduleMenuItem
                    : l10n.resumeScheduleMenuItem,
              ),
            ),
            PopupMenuItem(value: 'delete', child: Text(l10n.deleteButton)),
          ],
        ),
      ),
    );
  }
}

typedef _TemplateEditValue = ({String name, String? defaultListId});

Future<_TemplateEditValue?> _showTemplateEditDialog(
  BuildContext context,
  TemplateDto template,
  List<ListDto> lists,
) {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: template.name);
  var listId = template.defaultListId;
  return showDialog<_TemplateEditValue>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.editTemplateTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: l10n.nameLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              initialValue: listId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.defaultListLabel),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l10n.inboxFallbackLabel),
                ),
                for (final list in lists)
                  DropdownMenuItem(value: list.id, child: Text(list.name)),
              ],
              onChanged: (value) => setState(() => listId = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              name: controller.text.trim(),
              defaultListId: listId,
            )),
            child: Text(l10n.saveButton),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _showTaskIdDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.replaceTemplateSnapshotTitle),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: l10n.sourceTaskIdLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(l10n.replaceButton),
        ),
      ],
    ),
  );
}

Future<bool> _confirmTemplateDelete(BuildContext context, String name) async {
  final l10n = AppLocalizations.of(context)!;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deleteTemplateDialogTitle(name)),
          content: Text(l10n.deleteTemplateDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.deleteButton),
            ),
          ],
        ),
      ) ??
      false;
}

typedef _ScheduleInput = ({
  String rrule,
  int startsAt,
  String timeZone,
  bool enabled,
});

Future<_ScheduleInput?> _showScheduleDialog(
  BuildContext context,
  ScheduleDto? schedule,
  String defaultTimeZone,
) async {
  final l10n = AppLocalizations.of(context)!;
  var startsAt =
      schedule?.startsAt ??
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
  final initialStart = DateTime.fromMillisecondsSinceEpoch(startsAt);
  var selectedWeekdays = <int>{initialStart.weekday};
  var selectedMonthDay = initialStart.day;
  var weeklyCustomized = false;
  var monthlyCustomized = false;
  final zoneController = TextEditingController(
    text: schedule?.timeZone ?? defaultTimeZone,
  );
  final controller = TextEditingController(
    text: schedule?.rrule ?? 'FREQ=DAILY',
  );
  var preset = schedule == null ? 'daily' : 'advanced';
  var enabled = schedule?.enabled ?? true;
  return showDialog<_ScheduleInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          schedule == null ? l10n.newScheduleTitle : l10n.editScheduleTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('schedule-preset'),
                initialValue: preset,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.schedulePresetLabel,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'daily',
                    child: Text(
                      l10n.dailyPreset,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'weekly',
                    child: Text(
                      l10n.weeklyPreset,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'monthly',
                    child: Text(
                      l10n.monthlyPreset,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'advanced',
                    child: Text(
                      l10n.advancedPreset,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    preset = value;
                    controller.text = _presetRule(
                      value,
                      selectedWeekdays,
                      selectedMonthDay,
                      controller.text,
                    );
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (preset == 'weekly') ...[
                Wrap(
                  key: const Key('schedule-weekdays'),
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (
                      var weekday = DateTime.monday;
                      weekday <= DateTime.sunday;
                      weekday++
                    )
                      FilterChip(
                        key: Key('schedule-weekday-$weekday'),
                        label: Text(
                          DateFormat.E(
                            Localizations.localeOf(context).toLanguageTag(),
                          ).format(DateTime(2024, 1, weekday)),
                        ),
                        selected: selectedWeekdays.contains(weekday),
                        onSelected: (selected) {
                          if (!selected && selectedWeekdays.length == 1) {
                            return;
                          }
                          setState(() {
                            weeklyCustomized = true;
                            if (selected) {
                              selectedWeekdays.add(weekday);
                            } else {
                              selectedWeekdays.remove(weekday);
                            }
                            controller.text = _presetRule(
                              preset,
                              selectedWeekdays,
                              selectedMonthDay,
                              controller.text,
                            );
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (preset == 'monthly') ...[
                DropdownButtonFormField<int>(
                  key: const Key('schedule-month-day'),
                  initialValue: selectedMonthDay,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.monthlyPreset),
                  items: [
                    for (var day = 1; day <= 31; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text(
                          NumberFormat.decimalPattern(
                            Localizations.localeOf(context).toLanguageTag(),
                          ).format(day),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      monthlyCustomized = true;
                      selectedMonthDay = value;
                      controller.text = _presetRule(
                        preset,
                        selectedWeekdays,
                        selectedMonthDay,
                        controller.text,
                      );
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                controller: controller,
                enabled: preset == 'advanced',
                decoration: InputDecoration(labelText: l10n.rruleLabel),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.scheduleStartsAtLabel),
                subtitle: Text(
                  DateFormat.yMMMd().add_jm().format(
                    DateTime.fromMillisecondsSinceEpoch(startsAt),
                  ),
                ),
                trailing: const Icon(LucideIcons.calendarClock300),
                onTap: () async {
                  final current = DateTime.fromMillisecondsSinceEpoch(startsAt);
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2200),
                    initialDate: current,
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(current),
                  );
                  if (time == null) return;
                  setState(() {
                    final selectedStart = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    startsAt = selectedStart.millisecondsSinceEpoch;
                    if (!weeklyCustomized) {
                      selectedWeekdays = {selectedStart.weekday};
                    }
                    if (!monthlyCustomized) {
                      selectedMonthDay = selectedStart.day;
                    }
                    controller.text = _presetRule(
                      preset,
                      selectedWeekdays,
                      selectedMonthDay,
                      controller.text,
                    );
                  });
                },
              ),
              TextField(
                controller: zoneController,
                decoration: InputDecoration(labelText: l10n.timeZoneLabel),
              ),
              if (schedule != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.scheduleEnabledLabel),
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              rrule: controller.text.trim(),
              startsAt: startsAt,
              timeZone: zoneController.text.trim(),
              enabled: enabled,
            )),
            child: Text(l10n.saveButton),
          ),
        ],
      ),
    ),
  );
}

String _presetRule(
  String preset,
  Set<int> selectedWeekdays,
  int selectedMonthDay,
  String advancedRule,
) => switch (preset) {
  'daily' => 'FREQ=DAILY',
  'weekly' =>
    'FREQ=WEEKLY;BYDAY=${(selectedWeekdays.toList()..sort()).map(_weekdayCode).join(',')}',
  'monthly' => 'FREQ=MONTHLY;BYMONTHDAY=$selectedMonthDay',
  _ => advancedRule,
};

String _weekdayCode(int weekday) => const {
  DateTime.monday: 'MO',
  DateTime.tuesday: 'TU',
  DateTime.wednesday: 'WE',
  DateTime.thursday: 'TH',
  DateTime.friday: 'FR',
  DateTime.saturday: 'SA',
  DateTime.sunday: 'SU',
}[weekday]!;
