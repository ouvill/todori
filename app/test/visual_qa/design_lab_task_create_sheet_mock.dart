part of 'design_lab_mocks.dart';

class _TaskCreateSheetMock extends StatelessWidget {
  const _TaskCreateSheetMock();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        const IgnorePointer(child: _TaskListMock()),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.scrim.withValues(alpha: 0.24),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: _TaskCreateSheet(),
        ),
      ],
    );
  }
}

class _TaskCreateSheet extends StatelessWidget {
  const _TaskCreateSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _labSurfaceWarm,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 628),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const SizedBox(width: 38, height: 4),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Create task',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFamily: 'Newsreader',
                          color: colorScheme.primary,
                          fontSize: 26,
                          fontWeight: FontWeight.w400,
                          height: 1,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _labSoftIvory.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.42,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 5,
                        ),
                        child: Text(
                          'Inbox',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _TaskCreateTitleField(),
                        SizedBox(height: AppSpacing.sm),
                        _TaskCreateQuickChips(),
                        SizedBox(height: AppSpacing.sm),
                        _TaskCreateNotesField(),
                        SizedBox(height: AppSpacing.sm),
                        _TaskCreateSubtaskRow(),
                        SizedBox(height: AppSpacing.sm),
                        _TaskCreateFocusOption(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _TaskCreateActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskCreateTitleField extends StatelessWidget {
  const _TaskCreateTitleField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
        child: Row(
          children: [
            _TaskCreateCircleIcon(
              icon: Icons.add_task_rounded,
              color: colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Add a task...',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCreateQuickChips extends StatelessWidget {
  const _TaskCreateQuickChips();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _TaskCreateQuickChip(
          label: 'Today',
          icon: Icons.wb_sunny_outlined,
          selected: true,
        ),
        _TaskCreateQuickChip(label: 'Design', icon: Icons.palette_outlined),
        _TaskCreateQuickChip(
          label: 'Priority',
          icon: Icons.flag_outlined,
          accent: _priorityCoral,
        ),
      ],
    );
  }
}

class _TaskCreateQuickChip extends StatelessWidget {
  const _TaskCreateQuickChip({
    required this.label,
    required this.icon,
    this.selected = false,
    this.accent,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected ? colorScheme.primary : colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : _labSoftIvory.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.54)
              : colorScheme.outlineVariant.withValues(alpha: 0.34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: accent ?? foreground.withValues(alpha: 0.74),
              size: 15,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground.withValues(alpha: selected ? 0.9 : 0.66),
                fontWeight: FontWeight.w400,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCreateNotesField extends StatelessWidget {
  const _TaskCreateNotesField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return _TaskCreatePanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaskCreateCircleIcon(
            icon: Icons.notes_rounded,
            color: colorScheme.primary.withValues(alpha: 0.74),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w400,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Add context, links, or a gentle reminder.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w300,
                    height: 1.18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCreateSubtaskRow extends StatelessWidget {
  const _TaskCreateSubtaskRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return _TaskCreatePanel(
      child: Row(
        children: [
          _TaskCreateCircleIcon(
            icon: Icons.playlist_add_rounded,
            color: colorScheme.primary.withValues(alpha: 0.74),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Add subtask',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          const _TaskTagPill(label: 'Quick add'),
        ],
      ),
    );
  }
}

class _TaskCreateFocusOption extends StatelessWidget {
  const _TaskCreateFocusOption();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return _TaskCreatePanel(
      highlighted: true,
      child: Row(
        children: [
          _TaskCreateCircleIcon(
            icon: Icons.timer_outlined,
            color: colorScheme.primary,
            tinted: true,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start with focus timer',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '25 min after adding',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.44),
              ),
            ),
            child: SizedBox(
              width: 42,
              height: 24,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCreateActions extends StatelessWidget {
  const _TaskCreateActions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.62),
              ),
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add task'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.94),
              foregroundColor: colorScheme.onPrimary,
              minimumSize: const Size.fromHeight(48),
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskCreatePanel extends StatelessWidget {
  const _TaskCreatePanel({required this.child, this.highlighted = false});

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted
            ? colorScheme.primary.withValues(alpha: 0.045)
            : _labSurfaceWarm.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? colorScheme.primary.withValues(alpha: 0.22)
              : colorScheme.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: child,
      ),
    );
  }
}

class _TaskCreateCircleIcon extends StatelessWidget {
  const _TaskCreateCircleIcon({
    required this.icon,
    required this.color,
    this.tinted = false,
  });

  final IconData icon;
  final Color color;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tinted ? color.withValues(alpha: 0.1) : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(icon, size: 17, color: color.withValues(alpha: 0.82)),
      ),
    );
  }
}
