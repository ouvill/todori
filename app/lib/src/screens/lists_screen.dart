import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/dialogs.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/theme.dart';

/// List management and switching surface.
///
/// The app now opens to a task-first home surface. This screen remains the
/// quiet place to switch lists and create additional containers.
class ListsScreen extends ConsumerWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final listsAsync = ref.watch(listsProvider);

    return Scaffold(
      body: SafeArea(
        child: listsAsync.when(
          loading: () => const AppLoadingState(),
          error: (error, stackTrace) =>
              AppErrorState(message: l10n.failedToLoadLists(error.toString())),
          data: (lists) {
            return _ListsManagementView(
              lists: lists,
              onCreateList: () => _createList(context, ref),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showAppTextInputDialog(
      context: context,
      title: l10n.newListTitle,
      label: l10n.nameLabel,
      cancelLabel: l10n.cancelButton,
      submitLabel: l10n.createButton,
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await ref.read(listsProvider.notifier).createList(name.trim());
  }
}

class _ListsManagementView extends StatelessWidget {
  const _ListsManagementView({required this.lists, required this.onCreateList});

  final List<ListDto> lists;
  final VoidCallback onCreateList;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.appTitle,
          style: theme.textTheme.displaySmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: _SectionLabel(label: l10n.listsSectionTitle),
              ),
              if (lists.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppEmptyState(
                    icon: Icons.list_alt_outlined,
                    title: l10n.listsEmptyTitle,
                    body: l10n.listsEmptyBody,
                  ),
                )
              else
                for (var index = 0; index < lists.length; index += 1) ...[
                  _ListManagementRow(
                    icon: index == 0
                        ? Icons.wb_sunny_outlined
                        : Icons.circle_outlined,
                    color: _listAccent(colorScheme, index),
                    title: lists[index].name,
                    onTap: () =>
                        context.push('/lists/${lists[index].id}/tasks'),
                  ),
                ],
              Divider(color: colorScheme.outlineVariant),
              _ListManagementRow(
                icon: Icons.add,
                color: colorScheme.primary,
                title: l10n.homeNewListButton,
                onTap: onCreateList,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}

class _ListManagementRow extends StatelessWidget {
  const _ListManagementRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                title,
                softWrap: true,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

Color _listAccent(ColorScheme colorScheme, int index) {
  final accents = [
    colorScheme.primary,
    const Color(0xFF6FA17B),
    const Color(0xFFEDB73E),
    const Color(0xFF6F65B5),
    const Color(0xFFE8755A),
  ];
  return accents[index % accents.length];
}
