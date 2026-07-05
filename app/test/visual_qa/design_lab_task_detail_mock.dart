part of 'design_lab_mocks.dart';

class _TaskDetailMock extends StatelessWidget {
  const _TaskDetailMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _labPageIvory,
      floatingActionButton: const _TaskDetailFocusFab(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: const [
            _TaskDetailTopBar(),
            SizedBox(height: AppSpacing.lg),
            _TaskDetailHero(),
            SizedBox(height: AppSpacing.md),
            _TaskDetailMetaChips(),
            SizedBox(height: AppSpacing.lg),
            _TaskDetailDivider(),
            SizedBox(height: AppSpacing.lg),
            _TaskDetailSubtasksSection(),
            SizedBox(height: AppSpacing.lg),
            _TaskDetailActivitySection(),
          ],
        ),
      ),
    );
  }
}

class _TaskDetailTopBar extends StatelessWidget {
  const _TaskDetailTopBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        TextButton.icon(
          onPressed: () {},
          icon: Icon(
            Icons.arrow_back_rounded,
            color: colorScheme.primary.withValues(alpha: 0.9),
            size: 22,
          ),
          label: Text(
            'All tasks',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary.withValues(alpha: 0.9),
              fontWeight: FontWeight.w400,
            ),
          ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const Spacer(),
        const _QuietIconButton(icon: Icons.more_vert_rounded),
      ],
    );
  }
}

class _TaskDetailHero extends StatelessWidget {
  const _TaskDetailHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _CheckCircle(dimension: 28, checkSize: 15),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review design direction',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: 'Newsreader',
                  color: colorScheme.onSurface.withValues(alpha: 0.9),
                  fontSize: 39,
                  fontWeight: FontWeight.w400,
                  height: 0.98,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Align on the visual direction for Todori across mobile and '
                'desktop. Define the tone, typography, spacing, and common '
                'components.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.66),
                  fontWeight: FontWeight.w300,
                  height: 1.42,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskDetailMetaChips extends StatelessWidget {
  const _TaskDetailMetaChips();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _TaskDetailSetChip(
              icon: Icons.inbox_outlined,
              label: 'List',
              value: 'Design',
            ),
            _TaskDetailSetChip(
              icon: Icons.today_outlined,
              label: 'Due',
              value: 'Today',
            ),
            _TaskDetailSetChip(
              icon: Icons.schedule_rounded,
              label: 'Plan',
              value: '14:00',
            ),
            _TaskDetailSetChip(
              icon: Icons.hourglass_empty_rounded,
              label: 'Estimate',
              value: '45m',
            ),
            _TaskDetailSetChip(
              icon: Icons.label_outline_rounded,
              label: 'Tag',
              value: 'UI',
            ),
            _TaskDetailSetChip(
              dotColor: _priorityCoral,
              label: 'Priority',
              value: 'High',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: const [
              _TaskDetailAddChip(
                icon: Icons.notifications_none,
                label: 'Reminder',
              ),
              SizedBox(width: AppSpacing.xs),
              _TaskDetailAddChip(icon: Icons.repeat_rounded, label: 'Repeat'),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskDetailSetChip extends StatelessWidget {
  const _TaskDetailSetChip({
    required this.label,
    required this.value,
    this.icon,
    this.dotColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: _taskControlStrokeWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 15,
                color: colorScheme.primary.withValues(alpha: 0.72),
              )
            else
              _PriorityMark(color: dotColor!, size: 7),
            const SizedBox(width: 7),
            RichText(
              text: TextSpan(
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w300,
                  height: 1.0,
                ),
                children: [
                  TextSpan(text: '$label '),
                  TextSpan(
                    text: value,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w400,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.42),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskDetailFocusFab extends StatelessWidget {
  const _TaskDetailFocusFab();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: _labSurfaceWarm.withValues(alpha: 0.78),
          width: _taskControlStrokeWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Icon(
          Icons.play_arrow_rounded,
          color: colorScheme.onPrimary,
          size: 30,
        ),
      ),
    );
  }
}

class _TaskDetailAddChip extends StatelessWidget {
  const _TaskDetailAddChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.24),
          width: _taskControlStrokeWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 15,
              color: colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 3),
            Icon(
              icon,
              size: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.74),
                fontWeight: FontWeight.w300,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskDetailSubtasksSection extends StatelessWidget {
  const _TaskDetailSubtasksSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TaskDetailSectionTitle('Subtasks'),
        const SizedBox(height: AppSpacing.sm),
        const _SubtaskTree(
          subtasks: [
            _LabSubtask(
              title: 'Collect mood references',
              dueLabel: 'Jul 3',
              isDone: true,
            ),
            _LabSubtask(
              title: 'Define visual principles and tone',
              dueLabel: 'Today',
            ),
            _LabSubtask(
              title: 'Create mockups for key screens',
              dueLabel: 'Today',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const Padding(
          padding: EdgeInsets.only(left: _subtaskLineWidth),
          child: _TaskDetailAddSubtaskButton(),
        ),
      ],
    );
  }
}

class _TaskDetailAddSubtaskButton extends StatelessWidget {
  const _TaskDetailAddSubtaskButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.22),
          width: _taskControlStrokeWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 13, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 17,
              color: colorScheme.primary.withValues(alpha: 0.72),
            ),
            const SizedBox(width: 7),
            Text(
              'Add subtask',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary.withValues(alpha: 0.82),
                fontWeight: FontWeight.w400,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskDetailActivitySection extends StatelessWidget {
  const _TaskDetailActivitySection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TaskDetailSectionTitle('Activity'),
        SizedBox(height: AppSpacing.sm),
        _TaskDetailActivityList(),
      ],
    );
  }
}

class _TaskDetailActivityList extends StatelessWidget {
  const _TaskDetailActivityList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _TaskDetailActivityItem(
          icon: Icons.add_circle_outline_rounded,
          label: 'Created',
          value: 'Jul 2, 2026',
        ),
        SizedBox(height: AppSpacing.xs),
        _TaskDetailActivityItem(
          icon: Icons.update_rounded,
          label: 'Autosaved',
          value: 'Today at 09:24',
        ),
      ],
    );
  }
}

class _TaskDetailActivityItem extends StatelessWidget {
  const _TaskDetailActivityItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.52),
          size: 17,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 86,
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w300,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskDetailSectionTitle extends StatelessWidget {
  const _TaskDetailSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.w500,
        height: 1.1,
      ),
    );
  }
}

class _TaskDetailDivider extends StatelessWidget {
  const _TaskDetailDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      color: colorScheme.outlineVariant.withValues(alpha: 0.42),
    );
  }
}
