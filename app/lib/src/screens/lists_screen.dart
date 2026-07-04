import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/ui/dialogs.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/theme.dart';

/// The lists screen (initial route `/lists`).
///
/// F-02 "シンプルUI" skeleton: shows a flat list of lists with a FAB to
/// create a new one. Tapping a list navigates to its task list.
class ListsScreen extends ConsumerWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final listsAsync = ref.watch(listsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.listsTitle)),
      body: listsAsync.when(
        loading: () => const AppLoadingState(),
        error: (error, stackTrace) =>
            AppErrorState(message: l10n.failedToLoadLists(error.toString())),
        data: (lists) {
          if (lists.isEmpty) {
            return AppEmptyState(
              icon: Icons.list_alt_outlined,
              title: l10n.listsEmptyTitle,
              body: l10n.listsEmptyBody,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: lists.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final list = lists[index];
              final theme = Theme.of(context);
              final colorScheme = theme.colorScheme;
              return Material(
                color: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/lists/${list.id}/tasks'),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.list_alt_outlined,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              list.name,
                              softWrap: true,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createList(context, ref),
        tooltip: l10n.newListTooltip,
        child: const Icon(Icons.add),
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
