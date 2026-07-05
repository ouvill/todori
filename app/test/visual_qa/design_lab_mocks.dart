import 'package:flutter/material.dart';
import 'package:todori/src/ui/theme.dart';

enum DesignLabMock { calmToday, denseToday, smartLists }

class DesignLabMockApp extends StatelessWidget {
  const DesignLabMockApp({required this.mock, super.key});

  final DesignLabMock mock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTodoriTheme(Brightness.light),
      home: switch (mock) {
        DesignLabMock.calmToday => const _CalmTodayMock(),
        DesignLabMock.denseToday => const _DenseTodayMock(),
        DesignLabMock.smartLists => const _SmartListsMock(),
      },
    );
  }
}

class _LabTask {
  const _LabTask({
    required this.title,
    required this.dueLabel,
    required this.priority,
    this.contextLabel,
    this.isDone = false,
    this.isOverdue = false,
  });

  final String title;
  final String dueLabel;
  final int priority;
  final String? contextLabel;
  final bool isDone;
  final bool isOverdue;
}

const _tasks = [
  _LabTask(
    title: '地図アプリのUI微調整を仕上げる',
    dueLabel: 'Today',
    priority: 2,
    contextLabel: 'Inbox',
  ),
  _LabTask(
    title: 'Review checklist with design',
    dueLabel: 'Today',
    priority: 1,
    contextLabel: 'Launch',
  ),
  _LabTask(
    title: 'Renew passport before the trip',
    dueLabel: 'Jul 1',
    priority: 0,
    contextLabel: 'Personal',
    isOverdue: true,
  ),
  _LabTask(
    title: 'Draft the Q3 roadmap presentation for leadership',
    dueLabel: 'Tomorrow',
    priority: 3,
    contextLabel: 'Work',
  ),
  _LabTask(
    title: '朝会に参加する',
    dueLabel: 'Completed',
    priority: 0,
    contextLabel: 'Work',
    isDone: true,
  ),
];

class _CalmTodayMock extends StatelessWidget {
  const _CalmTodayMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('Add task'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl * 3,
          ),
          children: [
            _IconToolbar(
              leading: Icons.menu_rounded,
              actions: const [Icons.search_rounded, Icons.tune_rounded],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Today',
              style: theme.textTheme.displayLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
                height: 0.9,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Sun, Jul 5',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: const [
                _SoftPill(icon: Icons.inbox_outlined, label: 'Inbox'),
                _SoftPill(icon: Icons.radio_button_checked, label: '5 open'),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _FocusBand(task: _tasks.first),
            const SizedBox(height: AppSpacing.lg),
            Text('Next', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            for (final task in _tasks.skip(1).where((task) => !task.isDone))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _QuietTaskRow(task: task),
              ),
            const SizedBox(height: AppSpacing.sm),
            const _CollapsedCompleted(count: 1),
          ],
        ),
      ),
    );
  }
}

class _DenseTodayMock extends StatelessWidget {
  const _DenseTodayMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            _IconToolbar(
              leading: Icons.menu_rounded,
              actions: const [Icons.add_rounded, Icons.swap_vert_rounded],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'Today',
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      height: 0.92,
                    ),
                  ),
                ),
                const _CountBadge(label: '5 open'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _SegmentedStrip(labels: ['Now', 'Later', 'Done']),
            const SizedBox(height: AppSpacing.md),
            _DenseSection(
              title: 'Now',
              tasks: _tasks.take(2).toList(growable: false),
            ),
            const SizedBox(height: AppSpacing.md),
            _DenseSection(
              title: 'Later',
              tasks: _tasks.skip(2).take(2).toList(growable: false),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _CollapsedCompleted(count: 1),
          ],
        ),
      ),
    );
  }
}

class _SmartListsMock extends StatelessWidget {
  const _SmartListsMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            const _IconToolbar(
              leading: Icons.menu_rounded,
              actions: [Icons.search_rounded, Icons.add_rounded],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Today',
              style: theme.textTheme.displayMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
                height: 0.95,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A focused view across lists',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.65,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              children: const [
                _SmartListTile(
                  icon: Icons.today_outlined,
                  label: 'Today',
                  count: '5',
                  accent: _priorityAmber,
                ),
                _SmartListTile(
                  icon: Icons.calendar_month_outlined,
                  label: 'Upcoming',
                  count: '8',
                  accent: _prioritySage,
                ),
                _SmartListTile(
                  icon: Icons.inbox_outlined,
                  label: 'Inbox',
                  count: '12',
                  accent: _priorityGreen,
                ),
                _SmartListTile(
                  icon: Icons.check_circle_outline,
                  label: 'Completed',
                  count: '24',
                  accent: _priorityCoral,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Today plan', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            for (final task in _tasks.where((task) => !task.isDone))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _SmartTaskRow(task: task),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconToolbar extends StatelessWidget {
  const _IconToolbar({required this.leading, required this.actions});

  final IconData leading;
  final List<IconData> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIconButton(icon: leading),
        const Spacer(),
        for (final icon in actions) ...[
          _RoundIconButton(icon: icon, quiet: true),
          const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.quiet = false});

  final IconData icon;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      onPressed: () {},
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: quiet
            ? colorScheme.surface.withValues(alpha: 0.62)
            : colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurface,
        minimumSize: const Size(48, 48),
      ),
    );
  }
}

class _FocusBand extends StatelessWidget {
  const _FocusBand({required this.task});

  final _LabTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Now',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _CheckCircle(),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _SoftPill(icon: Icons.event_outlined, label: task.dueLabel),
                if (task.contextLabel != null)
                  _SoftPill(
                    icon: Icons.list_alt_outlined,
                    label: task.contextLabel!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietTaskRow extends StatelessWidget {
  const _QuietTaskRow({required this.task});

  final _LabTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const _CheckCircle(),
            const SizedBox(width: AppSpacing.sm),
            _PriorityDot(priority: task.priority),
            Expanded(
              child: Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DenseSection extends StatelessWidget {
  const _DenseSection({required this.title, required this.tasks});

  final String title;
  final List<_LabTask> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
              ),
            ),
          ),
          for (var index = 0; index < tasks.length; index += 1) ...[
            if (index > 0)
              Divider(color: colorScheme.outlineVariant, height: 1),
            _DenseTaskRow(task: tasks[index]),
          ],
        ],
      ),
    );
  }
}

class _DenseTaskRow extends StatelessWidget {
  const _DenseTaskRow({required this.task});

  final _LabTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dueColor = task.isOverdue ? colorScheme.error : colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const _CheckCircle(size: 28),
          const SizedBox(width: AppSpacing.sm),
          _PriorityDot(priority: task.priority),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${task.dueLabel}  /  ${task.contextLabel ?? 'Inbox'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: dueColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartTaskRow extends StatelessWidget {
  const _SmartTaskRow({required this.task});

  final _LabTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _PriorityDot(priority: task.priority),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _MiniMeta(
                        icon: Icons.event_outlined,
                        label: task.dueLabel,
                      ),
                      if (task.contextLabel != null)
                        _MiniMeta(
                          icon: Icons.folder_outlined,
                          label: task.contextLabel!,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftPill extends StatelessWidget {
  const _SoftPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.primary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SegmentedStrip extends StatelessWidget {
  const _SegmentedStrip({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index += 1)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: index == 0
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: index == 0
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
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

class _CollapsedCompleted extends StatelessWidget {
  const _CollapsedCompleted({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Completed',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$count done',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartListTile extends StatelessWidget {
  const _SmartListTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: accent),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  count,
                  style: theme.textTheme.titleMedium?.copyWith(color: accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.onSurfaceVariant, width: 2.3),
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final int priority;

  @override
  Widget build(BuildContext context) {
    if (priority == 0) {
      return const SizedBox(width: AppSpacing.sm);
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: switch (priority) {
            1 => _prioritySage,
            2 => _priorityAmber,
            _ => _priorityCoral,
          },
          shape: BoxShape.circle,
        ),
        child: const SizedBox(width: 12, height: 12),
      ),
    );
  }
}

const _priorityGreen = Color(0xFF2F6F4E);
const _prioritySage = Color(0xFFA9BFAE);
const _priorityAmber = Color(0xFFF0B83F);
const _priorityCoral = Color(0xFFE8755A);
