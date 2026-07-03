import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';

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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(l10n.failedToLoadLists(error.toString()))),
        data: (lists) {
          if (lists.isEmpty) {
            return Center(child: Text(l10n.listsEmpty));
          }
          return ListView.builder(
            itemCount: lists.length,
            itemBuilder: (context, index) {
              final list = lists[index];
              return ListTile(
                title: Text(list.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/lists/${list.id}/tasks'),
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
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewListDialog(),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await ref.read(listsProvider.notifier).createList(name.trim());
  }
}

class _NewListDialog extends StatefulWidget {
  const _NewListDialog();

  @override
  State<_NewListDialog> createState() => _NewListDialogState();
}

class _NewListDialogState extends State<_NewListDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.newListTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.nameLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.createButton),
        ),
      ],
    );
  }
}
