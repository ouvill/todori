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
      minimum: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _labSurfaceWarm,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          constraints: const BoxConstraints(maxHeight: 320),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
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
                const SizedBox(height: AppSpacing.lg),
                const _TaskCreateFields(),
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

class _TaskCreateFields extends StatelessWidget {
  const _TaskCreateFields();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TaskCreateTitleField(),
        SizedBox(height: AppSpacing.sm),
        _TaskCreateNotesField(),
        SizedBox(height: AppSpacing.md),
        _TaskCreateQuickChips(),
      ],
    );
  }
}

class _TaskCreateTitleField extends StatelessWidget {
  const _TaskCreateTitleField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Add a task...',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              fontSize: 26,
              fontWeight: FontWeight.w300,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 5),
          const _TaskCreateCursor(height: 28),
          const Spacer(),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Note',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.54),
              fontSize: 15,
              fontWeight: FontWeight.w300,
              height: 1.15,
            ),
          ),
          const SizedBox(width: 5),
          const _TaskCreateCursor(height: 18, quiet: true),
          const Spacer(),
        ],
      ),
    );
  }
}

class _TaskCreateQuickChips extends StatelessWidget {
  const _TaskCreateQuickChips();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        children: const [
          _TaskCreateQuickChip(
            label: 'List',
            value: 'Inbox',
            icon: LucideIcons.inbox300,
          ),
          SizedBox(width: AppSpacing.xs),
          _TaskCreateQuickChip(
            label: 'Due',
            value: 'Today',
            icon: LucideIcons.calendarDays300,
            selected: true,
          ),
          SizedBox(width: AppSpacing.xs),
          _TaskCreateQuickChip(
            label: 'Plan',
            value: '14:00',
            icon: LucideIcons.clock300,
          ),
          SizedBox(width: AppSpacing.xs),
          _TaskCreateQuickChip(
            label: 'Estimate',
            value: '45m',
            icon: LucideIcons.hourglass300,
          ),
          SizedBox(width: AppSpacing.xs),
          _TaskCreateQuickChip(
            label: 'Tag',
            value: 'UI',
            icon: LucideIcons.tag300,
          ),
          SizedBox(width: AppSpacing.xs),
          _TaskCreateQuickChip(
            label: 'Priority',
            value: 'High',
            dotColor: _priorityCoral,
          ),
          SizedBox(width: AppSpacing.xs),
          _TaskCreateMoreChip(),
        ],
      ),
    );
  }
}

class _TaskCreateQuickChip extends StatelessWidget {
  const _TaskCreateQuickChip({
    required this.label,
    required this.value,
    this.icon,
    this.selected = false,
    this.dotColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool selected;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : _labSurfaceWarm.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.48)
              : colorScheme.outlineVariant.withValues(alpha: 0.44),
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
                color: colorScheme.primary.withValues(
                  alpha: selected ? 0.88 : 0.84,
                ),
                size: 15,
              )
            else
              _PriorityMark(color: dotColor!, size: 7),
            const SizedBox(width: 7),
            RichText(
              text: TextSpan(
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
                children: [
                  TextSpan(text: '$label '),
                  TextSpan(
                    text: value,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? colorScheme.primary.withValues(alpha: 0.9)
                          : colorScheme.onSurface.withValues(alpha: 0.84),
                      fontWeight: FontWeight.w400,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              LucideIcons.chevronDown300,
              size: 16,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.54),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCreateMoreChip extends StatelessWidget {
  const _TaskCreateMoreChip();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.44),
          width: _taskControlStrokeWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Icon(
          LucideIcons.moreHorizontal300,
          size: 17,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
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
    return FilledButton.icon(
      onPressed: () {},
      icon: const Icon(LucideIcons.plus300),
      label: const Text('Add task'),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary.withValues(alpha: 0.94),
        foregroundColor: colorScheme.onPrimary,
        minimumSize: const Size.fromHeight(50),
        textStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _TaskCreateCursor extends StatelessWidget {
  const _TaskCreateCursor({required this.height, this.quiet = false});

  final double height;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: quiet ? 0.34 : 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(width: 1.5, height: height),
    );
  }
}
