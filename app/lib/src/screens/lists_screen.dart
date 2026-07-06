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
    final archivedListsAsync = ref.watch(archivedListsProvider);

    return Scaffold(
      body: SafeArea(
        child: listsAsync.when(
          loading: () => const AppLoadingState(),
          error: (error, stackTrace) =>
              AppErrorState(message: l10n.failedToLoadLists(error.toString())),
          data: (lists) {
            return archivedListsAsync.when(
              loading: () => _ListsManagementView(
                lists: lists,
                archivedLists: const [],
                onCreateList: () => _createList(context, ref),
                onRenameList: (list) => _renameList(context, ref, list),
                onArchiveList: (list) => _archiveList(ref, list),
                onDeleteList: (list) => _deleteList(context, ref, list),
                onUnarchiveList: (list) => _unarchiveList(ref, list),
              ),
              error: (error, stackTrace) => AppErrorState(
                message: l10n.failedToLoadLists(error.toString()),
              ),
              data: (archivedLists) => _ListsManagementView(
                lists: lists,
                archivedLists: archivedLists,
                onCreateList: () => _createList(context, ref),
                onRenameList: (list) => _renameList(context, ref, list),
                onArchiveList: (list) => _archiveList(ref, list),
                onDeleteList: (list) => _deleteList(context, ref, list),
                onUnarchiveList: (list) => _unarchiveList(ref, list),
              ),
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

  Future<void> _renameList(
    BuildContext context,
    WidgetRef ref,
    ListDto list,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showAppTextInputDialog(
      context: context,
      title: l10n.renameListTitle,
      label: l10n.nameLabel,
      cancelLabel: l10n.cancelButton,
      submitLabel: l10n.saveButton,
      initialValue: list.name,
    );
    final trimmedName = name?.trim();
    if (trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName == list.name) {
      return;
    }
    await ref.read(listsProvider.notifier).renameList(list.id, trimmedName);
  }

  Future<void> _archiveList(WidgetRef ref, ListDto list) async {
    await ref.read(listsProvider.notifier).archiveList(list.id);
  }

  Future<void> _deleteList(
    BuildContext context,
    WidgetRef ref,
    ListDto list,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final taskCount = await ref
        .read(listsProvider.notifier)
        .countTasks(list.id);
    if (!context.mounted) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l10n.deleteListDialogTitle(list.name),
      message: l10n.deleteListDialogMessage(taskCount),
      cancelLabel: l10n.cancelButton,
      confirmLabel: l10n.deleteButton,
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(listsProvider.notifier).deleteList(list.id);
  }

  Future<void> _unarchiveList(WidgetRef ref, ListDto list) async {
    await ref.read(archivedListsProvider.notifier).unarchiveList(list.id);
  }
}

class _ListsManagementView extends StatefulWidget {
  const _ListsManagementView({
    required this.lists,
    required this.archivedLists,
    required this.onCreateList,
    required this.onRenameList,
    required this.onArchiveList,
    required this.onDeleteList,
    required this.onUnarchiveList,
  });

  final List<ListDto> lists;
  final List<ListDto> archivedLists;
  final VoidCallback onCreateList;
  final ValueChanged<ListDto> onRenameList;
  final ValueChanged<ListDto> onArchiveList;
  final ValueChanged<ListDto> onDeleteList;
  final ValueChanged<ListDto> onUnarchiveList;

  @override
  State<_ListsManagementView> createState() => _ListsManagementViewState();
}

class _ListsManagementViewState extends State<_ListsManagementView> {
  bool _archivedExpanded = false;

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
              if (widget.lists.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppEmptyState(
                    icon: Icons.list_alt_outlined,
                    title: l10n.listsEmptyTitle,
                    body: l10n.listsEmptyBody,
                  ),
                )
              else
                for (var index = 0; index < widget.lists.length; index += 1)
                  _ListManagementRow(
                    icon: index == 0
                        ? Icons.wb_sunny_outlined
                        : Icons.circle_outlined,
                    color: _listAccent(colorScheme, index),
                    title: widget.lists[index].name,
                    onTap: () =>
                        context.push('/lists/${widget.lists[index].id}/tasks'),
                    onRename: () => widget.onRenameList(widget.lists[index]),
                    onArchive: index == 0
                        ? null
                        : () => widget.onArchiveList(widget.lists[index]),
                    onDelete: index == 0
                        ? null
                        : () => widget.onDeleteList(widget.lists[index]),
                  ),
              Divider(color: colorScheme.outlineVariant),
              _ListManagementRow(
                icon: Icons.add,
                color: colorScheme.primary,
                title: l10n.homeNewListButton,
                onTap: widget.onCreateList,
              ),
              if (widget.archivedLists.isNotEmpty) ...[
                Divider(color: colorScheme.outlineVariant),
                _ArchivedListsHeader(
                  count: widget.archivedLists.length,
                  expanded: _archivedExpanded,
                  onTap: () =>
                      setState(() => _archivedExpanded = !_archivedExpanded),
                ),
                if (_archivedExpanded)
                  for (
                    var index = 0;
                    index < widget.archivedLists.length;
                    index += 1
                  )
                    _ListManagementRow(
                      icon: Icons.archive_outlined,
                      color: colorScheme.onSurfaceVariant,
                      title: widget.archivedLists[index].name,
                      onTap: () => context.push(
                        '/lists/${widget.archivedLists[index].id}/tasks',
                      ),
                      onUnarchive: () =>
                          widget.onUnarchiveList(widget.archivedLists[index]),
                    ),
              ],
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

class _ArchivedListsHeader extends StatelessWidget {
  const _ArchivedListsHeader({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              child: Center(
                child: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                l10n.archivedListsSectionTitle(count),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: expanded
                  ? l10n.hideArchivedListsTooltip
                  : l10n.showArchivedListsTooltip,
              onPressed: onTap,
              icon: Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
    this.onRename,
    this.onArchive,
    this.onDelete,
    this.onUnarchive,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onUnarchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_hasActions)
              SizedBox(
                width: 48,
                height: 48,
                child: PopupMenuButton<_ListRowAction>(
                  tooltip: l10n.listActionsTooltip,
                  icon: Icon(
                    Icons.more_horiz,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ListRowAction.rename:
                        onRename!();
                        break;
                      case _ListRowAction.archive:
                        onArchive!();
                        break;
                      case _ListRowAction.delete:
                        onDelete!();
                        break;
                      case _ListRowAction.unarchive:
                        onUnarchive!();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (onRename != null)
                      PopupMenuItem(
                        value: _ListRowAction.rename,
                        child: Text(l10n.renameListMenuItem),
                      ),
                    if (onArchive != null)
                      PopupMenuItem(
                        value: _ListRowAction.archive,
                        child: Text(l10n.archiveListMenuItem),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: _ListRowAction.delete,
                        child: Text(l10n.deleteListMenuItem),
                      ),
                    if (onUnarchive != null)
                      PopupMenuItem(
                        value: _ListRowAction.unarchive,
                        child: Text(l10n.unarchiveListMenuItem),
                      ),
                  ],
                ),
              ),
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  bool get _hasActions =>
      onRename != null ||
      onArchive != null ||
      onDelete != null ||
      onUnarchive != null;
}

enum _ListRowAction { rename, archive, delete, unarchive }

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
