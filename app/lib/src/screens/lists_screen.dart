import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
              ),
              error: (error, stackTrace) => AppErrorState(
                message: l10n.failedToLoadLists(error.toString()),
              ),
              data: (archivedLists) => _ListsManagementView(
                lists: lists,
                archivedLists: archivedLists,
                onCreateList: () => _createList(context, ref),
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
}

class _ListsManagementView extends StatefulWidget {
  const _ListsManagementView({
    required this.lists,
    required this.archivedLists,
    required this.onCreateList,
  });

  final List<ListDto> lists;
  final List<ListDto> archivedLists;
  final VoidCallback onCreateList;

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
              icon: const Icon(LucideIcons.arrowLeft300),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: l10n.listsMoreMenuTooltip,
              icon: const Icon(LucideIcons.ellipsisVertical300),
              onSelected: (value) {
                if (value == 'account') {
                  context.push('/account');
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'account',
                  child: Row(
                    children: [
                      const Icon(LucideIcons.userCircle300),
                      const SizedBox(width: AppSpacing.sm),
                      Text(l10n.accountTitle),
                    ],
                  ),
                ),
              ],
            ),
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
              _ListManagementRow(
                icon: LucideIcons.house300,
                color: colorScheme.primary,
                title: l10n.homeTitle,
                tooltip: l10n.homeSmartListTooltip,
                onTap: () => context.go('/'),
              ),
              Divider(color: colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: _SectionLabel(label: l10n.listsSectionTitle),
              ),
              if (widget.lists.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppEmptyState(
                    icon: LucideIcons.listTodo300,
                    title: l10n.listsEmptyTitle,
                    body: l10n.listsEmptyBody,
                  ),
                )
              else
                for (var index = 0; index < widget.lists.length; index += 1)
                  _ListManagementRow(
                    icon: LucideIcons.circle300,
                    color: _listAccent(colorScheme, index),
                    title: widget.lists[index].name,
                    onTap: () =>
                        context.push('/lists/${widget.lists[index].id}/tasks'),
                  ),
              Divider(color: colorScheme.outlineVariant),
              _ListManagementRow(
                icon: LucideIcons.plus300,
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
                      icon: LucideIcons.archive300,
                      color: colorScheme.onSurfaceVariant,
                      title: widget.archivedLists[index].name,
                      onTap: () => context.push(
                        '/lists/${widget.archivedLists[index].id}/tasks',
                      ),
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
    final tooltip = expanded
        ? l10n.hideArchivedListsTooltip
        : l10n.showArchivedListsTooltip;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.archivedListsSectionTitle(count),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Icon(
                      expanded
                          ? LucideIcons.chevronUp300
                          : LucideIcons.chevronDown300,
                      color: colorScheme.onSurfaceVariant,
                    ),
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

class _ListManagementRow extends StatelessWidget {
  const _ListManagementRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final row = InkWell(
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
          ],
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip == null) {
      return row;
    }
    return Tooltip(
      message: tooltip,
      child: Semantics(label: tooltip, button: true, child: row),
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
