import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/ui/task_components.dart';
import 'package:todori/src/ui/theme.dart';

/// Immersive, task-first search. This route intentionally lives outside the
/// product shell so the query remains the only navigation context on screen.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(taskSearchProvider.notifier).clear();
      }
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return;
    }
    ref.read(taskSearchProvider.notifier).setQuery(_controller.text);
    setState(() {});
  }

  void _submitQuery() {
    ref.read(taskSearchProvider.notifier).setQuery(_controller.text);
  }

  void _clearQuery() {
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(taskSearchProvider);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _SearchLine(
              controller: _controller,
              showClear: _controller.text.isNotEmpty,
              onClear: _clearQuery,
              onSubmitted: _submitQuery,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _SearchContent(
                    state: state,
                    onRetry: _submitQuery,
                    onOpen: (item) => context.pushNamed(
                      'searchTaskDetail',
                      pathParameters: {
                        'listId': item.task.listId,
                        'taskId': item.task.id,
                      },
                    ),
                    l10n: l10n,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchLine extends StatelessWidget {
  const _SearchLine({
    required this.controller,
    required this.showClear,
    required this.onClear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool showClear;
  final VoidCallback onClear;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, minHeight: 56),
          child: Row(
            children: [
              const SizedBox.square(dimension: 48, child: BackButton()),
              const ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 40,
                  child: Icon(LucideIcons.search300, size: 20),
                ),
              ),
              Expanded(
                child: Semantics(
                  label: l10n.searchFieldSemantics,
                  textField: true,
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => onSubmitted(),
                    onEditingComplete: onSubmitted,
                    decoration: InputDecoration(
                      hintText: l10n.searchFieldHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              if (showClear)
                SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    tooltip: l10n.clearSearchTooltip,
                    onPressed: onClear,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: const Icon(LucideIcons.x300, size: 20),
                  ),
                )
              else
                const SizedBox(width: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchContent extends StatelessWidget {
  const _SearchContent({
    required this.state,
    required this.onRetry,
    required this.onOpen,
    required this.l10n,
  });

  final TaskSearchState state;
  final VoidCallback onRetry;
  final ValueChanged<TaskSearchResult> onOpen;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      TaskSearchIdle() => _SearchMessage(
        icon: LucideIcons.search300,
        title: l10n.searchEmptyTitle,
        body: l10n.searchEmptyBody,
      ),
      TaskSearchLoading() => Semantics(
        label: l10n.searchLoadingSemantics,
        liveRegion: true,
        child: const Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      ),
      TaskSearchData(:final query, :final items) when items.isEmpty =>
        _SearchMessage(
          icon: LucideIcons.searchX300,
          title: l10n.searchNoResultsTitle,
          body: l10n.searchNoResultsBody(query),
        ),
      TaskSearchData(:final items) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: items.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) => _SearchResultRow(
          result: items[index],
          onTap: () => onOpen(items[index]),
        ),
      ),
      TaskSearchError() => _SearchMessage(
        icon: LucideIcons.cloudOff300,
        title: l10n.searchFailed,
        liveRegion: true,
        action: TextButton(onPressed: onRetry, child: Text(l10n.retryButton)),
      ),
    };
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.liveRegion = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Semantics(
          liveRegion: liveRegion,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: AppColors.forest),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                if (body != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    body!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.result, required this.onTap});

  final TaskSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final task = result.task;
    final status = taskStatusLabel(l10n, task.status);
    final listContext = result.listArchived
        ? l10n.searchArchivedListLabel(result.listName)
        : result.listName;
    final note = task.note.trim();
    return Semantics(
      button: true,
      label: l10n.searchResultSemantics(task.title, listContext, status),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    height: 24,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: PriorityDot(
                        priority: task.priority,
                        isMuted: false,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: 2,
                          children: [
                            Text(
                              listContext,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: AppColors.muted),
                            ),
                            Text(
                              status,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
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
