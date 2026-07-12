import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/core/task_due.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/task_components.dart';
import 'package:todori/src/ui/theme.dart';

class AppNavigationShell extends ConsumerWidget {
  const AppNavigationShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final path = GoRouterState.of(context).uri.path;
    final selectedDestination = switch (path) {
      final value when value.startsWith('/calendar') =>
        _AppDestination.calendar,
      final value when value.startsWith('/lists') => _AppDestination.lists,
      final value when value.startsWith('/account') => _AppDestination.you,
      _ => _AppDestination.home,
    };
    final segments = Uri.parse(path).pathSegments;
    final isTaskDetail =
        segments.length >= 4 &&
        (segments.first == 'lists' || segments.first == 'calendar');

    if (isTaskDetail) {
      return child;
    }

    final activeLists = ref.watch(listsProvider).value ?? const <ListDto>[];
    final routeListId = segments.length >= 2 && segments.first == 'lists'
        ? segments[1]
        : null;
    final routeList = routeListId == null
        ? null
        : _findList(activeLists, routeListId);
    final defaultList = _findDefaultList(activeLists);
    final captureListId = routeList?.id ?? defaultList?.id;
    final capture = CircularCaptureAction(
      listOptions: activeLists,
      initialListId: captureListId,
      initialDue: path == '/' ? dateOnlyDue(DateTime.now()) : null,
      errorMessage: l10n.quickAddCreateError,
      onCreate:
          ({
            required listId,
            required title,
            required note,
            required due,
            required priority,
            required scheduledAt,
            required estimatedMinutes,
          }) => ref
              .read(homeTasksProvider.notifier)
              .createTask(
                listId: listId,
                title: title,
                note: note,
                due: due,
                priority: priority,
                scheduledAt: scheduledAt,
                estimatedMinutes: estimatedMinutes,
              ),
    );

    void selectDestination(_AppDestination destination) {
      switch (destination) {
        case _AppDestination.home:
          context.go('/');
        case _AppDestination.calendar:
          context.go('/calendar');
        case _AppDestination.lists:
          context.go('/lists');
        case _AppDestination.you:
          context.go('/account');
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Scaffold(
            body: Row(
              children: [
                _AppNavigationRail(
                  selectedDestination: selectedDestination,
                  capture: capture,
                  onSelected: selectDestination,
                ),
                const VerticalDivider(width: 1, color: AppColors.hairline),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: _AppBottomNavigation(
            selectedDestination: selectedDestination,
            capture: capture,
            onSelected: selectDestination,
          ),
        );
      },
    );
  }
}

enum _AppDestination { home, calendar, lists, you }

class _AppBottomNavigation extends StatelessWidget {
  const _AppBottomNavigation({
    required this.selectedDestination,
    required this.capture,
    required this.onSelected,
  });

  final _AppDestination selectedDestination;
  final Widget capture;
  final ValueChanged<_AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.hairline, width: 0.7)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              Expanded(
                child: _AppNavigationItem(
                  icon: LucideIcons.house300,
                  label: l10n.homeTitle,
                  selected: selectedDestination == _AppDestination.home,
                  onTap: () => onSelected(_AppDestination.home),
                ),
              ),
              Expanded(
                child: _AppNavigationItem(
                  icon: LucideIcons.calendarDays300,
                  label: l10n.calendarTitle,
                  selected: selectedDestination == _AppDestination.calendar,
                  onTap: () => onSelected(_AppDestination.calendar),
                ),
              ),
              Expanded(child: Center(child: capture)),
              Expanded(
                child: _AppNavigationItem(
                  icon: LucideIcons.listTodo300,
                  label: l10n.listsTitle,
                  selected: selectedDestination == _AppDestination.lists,
                  onTap: () => onSelected(_AppDestination.lists),
                ),
              ),
              Expanded(
                child: _AppNavigationItem(
                  icon: LucideIcons.userRound300,
                  label: l10n.navigationYouLabel,
                  selected: selectedDestination == _AppDestination.you,
                  onTap: () => onSelected(_AppDestination.you),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppNavigationRail extends StatelessWidget {
  const _AppNavigationRail({
    required this.selectedDestination,
    required this.capture,
    required this.onSelected,
  });

  final _AppDestination selectedDestination;
  final Widget capture;
  final ValueChanged<_AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            _AppNavigationItem(
              icon: LucideIcons.house300,
              label: l10n.homeTitle,
              selected: selectedDestination == _AppDestination.home,
              onTap: () => onSelected(_AppDestination.home),
              vertical: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            _AppNavigationItem(
              icon: LucideIcons.calendarDays300,
              label: l10n.calendarTitle,
              selected: selectedDestination == _AppDestination.calendar,
              onTap: () => onSelected(_AppDestination.calendar),
              vertical: true,
            ),
            const SizedBox(height: AppSpacing.md),
            capture,
            const SizedBox(height: AppSpacing.md),
            _AppNavigationItem(
              icon: LucideIcons.listTodo300,
              label: l10n.listsTitle,
              selected: selectedDestination == _AppDestination.lists,
              onTap: () => onSelected(_AppDestination.lists),
              vertical: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            _AppNavigationItem(
              icon: LucideIcons.userRound300,
              label: l10n.navigationYouLabel,
              selected: selectedDestination == _AppDestination.you,
              onTap: () => onSelected(_AppDestination.you),
              vertical: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppNavigationItem extends StatelessWidget {
  const _AppNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.vertical = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.forest : AppColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: vertical ? AppSpacing.xs : 2,
                vertical: AppSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: selected ? 24 : 0,
                    height: 2,
                    color: AppColors.forest,
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

ListDto? _findDefaultList(List<ListDto> lists) {
  for (final list in lists) {
    if (list.isDefault && list.archivedAt == null) {
      return list;
    }
  }
  for (final list in lists) {
    if (list.archivedAt == null) {
      return list;
    }
  }
  return null;
}

ListDto? _findList(List<ListDto> lists, String id) {
  for (final list in lists) {
    if (list.id == id && list.archivedAt == null) {
      return list;
    }
  }
  return null;
}
