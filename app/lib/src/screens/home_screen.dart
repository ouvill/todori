import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart' show ListDto;
import 'package:todori/src/screens/tasks_screen.dart';
import 'package:todori/src/ui/states.dart';

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
        final defaultList = _defaultList(lists);
        if (defaultList == null) {
          return Scaffold(
            body: AppErrorState(message: l10n.defaultListMissing),
          );
        }
        return TasksScreen(
          listId: defaultList.id,
          listName: defaultList.name,
          isHome: true,
        );
      },
    );
  }
}

ListDto? _defaultList(List<ListDto> lists) {
  for (final list in lists) {
    if (list.isDefault) {
      return list;
    }
  }
  return null;
}
