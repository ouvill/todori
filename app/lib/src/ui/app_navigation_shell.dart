import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';

class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final path = GoRouterState.of(context).uri.path;
    final selectedIndex = switch (path) {
      final value when value.startsWith('/lists') => 1,
      final value when value.startsWith('/account') => 2,
      _ => 0,
    };
    final segments = Uri.parse(path).pathSegments;
    final isTaskDetail = segments.length >= 4 && segments.first == 'lists';

    if (isTaskDetail) {
      return child;
    }

    void selectDestination(int index) {
      switch (index) {
        case 0:
          context.go('/');
        case 1:
          context.go('/lists');
        case 2:
          context.go('/account');
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: selectDestination,
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -0.72,
                    leading: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Icon(
                        LucideIcons.sprout300,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    destinations: [
                      NavigationRailDestination(
                        icon: Tooltip(
                          message: l10n.homeSmartListTooltip,
                          child: const Icon(LucideIcons.house300),
                        ),
                        label: Text(l10n.homeTitle),
                      ),
                      NavigationRailDestination(
                        icon: Tooltip(
                          message: l10n.homeListMenuTooltip,
                          child: const Icon(LucideIcons.listTodo300),
                        ),
                        label: Text(l10n.listsTitle),
                      ),
                      NavigationRailDestination(
                        icon: Tooltip(
                          message: l10n.accountTitle,
                          child: const Icon(LucideIcons.userRound300),
                        ),
                        label: Text(l10n.accountTitle),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: selectDestination,
              destinations: [
                NavigationDestination(
                  tooltip: l10n.homeSmartListTooltip,
                  icon: const Icon(LucideIcons.house300),
                  selectedIcon: const Icon(LucideIcons.house300),
                  label: l10n.homeTitle,
                ),
                NavigationDestination(
                  tooltip: l10n.homeListMenuTooltip,
                  icon: const Icon(LucideIcons.listTodo300),
                  selectedIcon: const Icon(LucideIcons.listTodo300),
                  label: l10n.listsTitle,
                ),
                NavigationDestination(
                  tooltip: l10n.accountTitle,
                  icon: const Icon(LucideIcons.userRound300),
                  selectedIcon: const Icon(LucideIcons.userRound300),
                  label: l10n.accountTitle,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
