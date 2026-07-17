import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/ui/header_actions.dart';
import 'package:todori/src/ui/theme.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final account = ref.watch(accountProvider).value;
    final accountDetail = account?.loggedIn == true
        ? account?.email ?? l10n.menuAccountBody
        : l10n.menuAccountBody;
    final calendarWeekStart =
        ref.watch(calendarWeekStartProvider).value ?? defaultCalendarWeekStart;
    final calendarDetail = switch (calendarWeekStart) {
      mondayCalendarWeekStart => l10n.calendarWeekStartMonday,
      sundayCalendarWeekStart => l10n.calendarWeekStartSunday,
      _ => l10n.calendarWeekStartSystem,
    };

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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.menuTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const AppHeaderSearchAction(),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.menuSubtitle,
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
                  l10n.menuSectionTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _MenuRow(
                  key: const ValueKey('menu-account'),
                  icon: LucideIcons.userRound300,
                  title: l10n.accountTitle,
                  detail: accountDetail,
                  onTap: () => context.push('/menu/account'),
                ),
                Divider(color: colorScheme.outlineVariant),
                _MenuRow(
                  key: const ValueKey('menu-calendar-settings'),
                  icon: LucideIcons.calendarDays300,
                  title: l10n.calendarSettingsTitle,
                  detail: calendarDetail,
                  onTap: () => context.push('/menu/calendar'),
                ),
                Divider(color: colorScheme.outlineVariant),
                _MenuRow(
                  key: const ValueKey('menu-templates'),
                  icon: LucideIcons.layoutTemplate300,
                  title: l10n.templatesTitle,
                  detail: l10n.menuTemplatesBody,
                  onTap: () => context.go('/templates'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
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
                  Icon(icon, size: 22, color: colorScheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          detail,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    LucideIcons.chevronRight300,
                    size: 19,
                    color: colorScheme.onSurfaceVariant,
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
