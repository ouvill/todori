import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:taskveil/src/core/providers.dart';
import 'package:taskveil/src/generated/l10n/app_localizations.dart';
import 'package:taskveil/src/ui/states.dart';
import 'package:taskveil/src/ui/theme.dart';

class CalendarSettingsScreen extends ConsumerStatefulWidget {
  const CalendarSettingsScreen({super.key});

  @override
  ConsumerState<CalendarSettingsScreen> createState() =>
      _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState
    extends ConsumerState<CalendarSettingsScreen> {
  bool _saving = false;

  Future<void> _setWeekStart(String weekStart) async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(calendarWeekStartProvider.notifier)
          .setWeekStart(weekStart);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.calendarSettingsSaveFailed,
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final weekStart = ref.watch(calendarWeekStartProvider);

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    tooltip: l10n.backButtonTooltip,
                    alignment: AlignmentDirectional.centerStart,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/menu');
                      }
                    },
                    icon: const Icon(LucideIcons.arrowLeft300),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.calendarSettingsTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.calendarSettingsSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: 36,
                    height: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  l10n.calendarWeekStartSectionTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                weekStart.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: AppLoadingState(),
                  ),
                  error: (error, stackTrace) =>
                      AppErrorState(message: l10n.calendarSettingsLoadFailed),
                  data: (selected) => Column(
                    children: [
                      _WeekStartOption(
                        key: const ValueKey('calendar-week-start-system'),
                        title: l10n.calendarWeekStartSystem,
                        detail: l10n.calendarWeekStartSystemBody,
                        selected: selected == systemCalendarWeekStart,
                        onTap: _saving
                            ? null
                            : () => _setWeekStart(systemCalendarWeekStart),
                      ),
                      Divider(color: colorScheme.outlineVariant),
                      _WeekStartOption(
                        key: const ValueKey('calendar-week-start-monday'),
                        title: l10n.calendarWeekStartMonday,
                        detail: l10n.calendarWeekStartMondayBody,
                        selected: selected == mondayCalendarWeekStart,
                        onTap: _saving
                            ? null
                            : () => _setWeekStart(mondayCalendarWeekStart),
                      ),
                      Divider(color: colorScheme.outlineVariant),
                      _WeekStartOption(
                        key: const ValueKey('calendar-week-start-sunday'),
                        title: l10n.calendarWeekStartSunday,
                        detail: l10n.calendarWeekStartSundayBody,
                        selected: selected == sundayCalendarWeekStart,
                        onTap: _saving
                            ? null
                            : () => _setWeekStart(sundayCalendarWeekStart),
                      ),
                    ],
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

class _WeekStartOption extends StatelessWidget {
  const _WeekStartOption({
    super.key,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      hint: detail,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(
                    selected
                        ? LucideIcons.circleCheck300
                        : LucideIcons.circle300,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
