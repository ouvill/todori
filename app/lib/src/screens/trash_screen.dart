import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/task_components.dart';
import 'package:todori/src/ui/theme.dart';

/// Shows logically deleted tasks and lets the user restore them.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final trashedTasksAsync = ref.watch(trashedTasksProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trashTitle)),
      body: trashedTasksAsync.when(
        loading: () => const AppLoadingState(),
        error: (error, stackTrace) =>
            AppErrorState(message: l10n.failedToLoadTrash(error.toString())),
        data: (tasks) {
          if (tasks.isEmpty) {
            return AppEmptyState(
              icon: Icons.restore_from_trash_outlined,
              title: l10n.trashEmptyTitle,
              body: l10n.trashEmptyBody,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: tasks.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _TrashTaskRow(
                key: ValueKey('trash-row-${task.id}'),
                task: task,
                onRestore: () => ref
                    .read(trashedTasksProvider.notifier)
                    .restoreTask(task.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _TrashTaskRow extends StatelessWidget {
  const _TrashTaskRow({super.key, required this.task, required this.onRestore});

  final TaskDto task;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metadata = [
      TaskMetadataItem(
        icon: Icons.delete_outline,
        label: l10n.taskDeletedAt(formatDueDate(l10n, task.deletedAt)),
      ),
      if (task.priority > 0)
        TaskMetadataItem(
          icon: Icons.flag_outlined,
          label: l10n.taskPriority(taskPriorityLabel(l10n, task.priority)),
        ),
      if (task.dueAt != null)
        TaskMetadataItem(
          icon: Icons.event_outlined,
          label: l10n.taskDueAt(formatDueDate(l10n, task.dueAt)),
        ),
    ];

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.78),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final stackAction = constraints.maxWidth < 340 || textScale > 1.25;
            final restoreButton = Semantics(
              button: true,
              label: l10n.restoreTaskTooltip,
              child: IconButton(
                key: ValueKey('restore-task-${task.id}'),
                icon: const Icon(Icons.restore_outlined),
                tooltip: l10n.restoreTaskTooltip,
                onPressed: onRestore,
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.restore_from_trash_outlined,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            softWrap: true,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          TaskMetadata(items: metadata),
                        ],
                      ),
                    ),
                    if (!stackAction) ...[
                      const SizedBox(width: AppSpacing.xs),
                      restoreButton,
                    ],
                  ],
                ),
                if (stackAction) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: restoreButton,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
