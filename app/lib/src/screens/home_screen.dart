import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/screens/tasks_screen.dart';
import 'package:todori/src/ui/dialogs.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/theme.dart';

/// Task-first root surface.
///
/// Phase 1 still stores tasks inside lists, but the product entry should feel
/// like opening Todori to today's work rather than choosing a container first.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final listsAsync = ref.watch(listsProvider);

    return listsAsync.when(
      loading: () => const Scaffold(body: AppLoadingState()),
      error: (error, stackTrace) => Scaffold(
        body: AppErrorState(message: l10n.failedToLoadLists(error.toString())),
      ),
      data: (lists) {
        if (lists.isEmpty) {
          return _HomeEmptyScreen(
            onCreateList: () => _createList(context, ref),
          );
        }
        final list = lists.first;
        return TasksScreen(listId: list.id, listName: list.name, isHome: true);
      },
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

class _HomeEmptyScreen extends StatelessWidget {
  const _HomeEmptyScreen({required this.onCreateList});

  final VoidCallback onCreateList;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (AppSpacing.lg * 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.todayTitle,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppEmptyState(
                      icon: Icons.list_alt_outlined,
                      title: l10n.homeEmptyTitle,
                      body: l10n.homeEmptyBody,
                      action: FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(l10n.homeNewListButton),
                        onPressed: onCreateList,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.list_alt_outlined),
                        tooltip: l10n.homeListMenuTooltip,
                        onPressed: () => context.push('/lists'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
