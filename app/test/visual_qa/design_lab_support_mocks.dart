part of 'design_lab_mocks.dart';

class _SearchMock extends StatelessWidget {
  const _SearchMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: _labPageIvory,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.sm,
            0,
            AppSpacing.xl,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  _QuietIconButton(icon: LucideIcons.arrowLeft300),
                  Spacer(),
                  _QuietIconButton(icon: LucideIcons.slidersHorizontal300),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Search',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontFamily: 'Newsreader',
                  color: colorScheme.primary,
                  fontSize: 46,
                  fontWeight: FontWeight.w400,
                  height: 0.96,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SupportSearchField(),
            const SizedBox(height: AppSpacing.lg),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _SupportSectionHeader(label: 'RECENT FILTERS'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: const [
                  _SupportFilterChip(
                    icon: LucideIcons.calendarDays300,
                    label: 'Due this week',
                    selected: true,
                  ),
                  _SupportFilterChip(
                    icon: LucideIcons.leaf300,
                    label: 'Focus-ready',
                  ),
                  _SupportFilterChip(
                    icon: LucideIcons.circleCheck300,
                    label: 'Completed',
                  ),
                  _SupportFilterChip(
                    icon: LucideIcons.folder300,
                    label: 'Design',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SupportResultsPanel(),
          ],
        ),
      ),
    );
  }
}

class _SettingsMock extends StatelessWidget {
  const _SettingsMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: _labPageIvory,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.sm,
            0,
            AppSpacing.xl,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  _QuietIconButton(icon: LucideIcons.arrowLeft300),
                  Spacer(),
                  _QuietIconButton(icon: LucideIcons.moreHorizontal300),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Settings',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontFamily: 'Newsreader',
                  color: colorScheme.primary,
                  fontSize: 46,
                  fontWeight: FontWeight.w400,
                  height: 0.96,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Calm controls for your private workspace.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SettingsAccountCard(),
            const SizedBox(height: AppSpacing.md),
            const _SettingsGroup(
              label: 'APP',
              rows: [
                _SettingsRowData(
                  icon: LucideIcons.refreshCw300,
                  title: 'Sync',
                  detail: 'Last updated 2 min ago',
                  accent: _priorityBlue,
                ),
                _SettingsRowData(
                  icon: LucideIcons.lock300,
                  title: 'Security',
                  detail: 'Device key protected',
                  accent: _priorityGreen,
                ),
                _SettingsRowData(
                  icon: LucideIcons.palette300,
                  title: 'Appearance',
                  detail: 'Warm ivory, system light',
                  accent: _priorityAmber,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _SettingsGroup(
              label: 'PREFERENCES',
              rows: [
                _SettingsRowData(
                  icon: LucideIcons.bell300,
                  title: 'Notifications',
                  detail: 'Daily planning at 9:00',
                  accent: _priorityCoral,
                ),
                _SettingsRowData(
                  icon: LucideIcons.timer300,
                  title: 'Focus timer',
                  detail: '25 min default',
                  accent: _prioritySage,
                ),
                _SettingsRowData(
                  icon: LucideIcons.languages300,
                  title: 'Language',
                  detail: 'English',
                  accent: Color(0xFF8F82C8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerSetupMock extends StatelessWidget {
  const _TimerSetupMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: _labPageIvory,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                const _QuietIconButton(icon: LucideIcons.x300),
                Expanded(
                  child: Center(
                    child: Text(
                      'Focus',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'Newsreader',
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const _QuietIconButton(icon: LucideIcons.moreHorizontal300),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _TimerSetupRing(),
            const SizedBox(height: AppSpacing.lg),
            const _TimerSetupTaskCard(),
            const SizedBox(height: AppSpacing.md),
            const _TimerSetupStartButton(),
          ],
        ),
      ),
    );
  }
}

class _SupportSearchField extends StatelessWidget {
  const _SupportSearchField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(
              LucideIcons.search300,
              color: colorScheme.primary.withValues(alpha: 0.72),
              size: 22,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Search tasks, lists, or notes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.64),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const _TaskTagPill(label: 'Cmd K'),
          ],
        ),
      ),
    );
  }
}

class _TimerSetupRing extends StatelessWidget {
  const _TimerSetupRing();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: SizedBox.square(
        dimension: 292,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              painter: _FocusRingPainter(
                trackColor: colorScheme.primary.withValues(alpha: 0.16),
                progressColor: colorScheme.primary.withValues(alpha: 0.18),
                progress: 1,
              ),
              child: const SizedBox.expand(),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.timer300,
                  color: colorScheme.primary.withValues(alpha: 0.76),
                  size: 28,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Ready to focus',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.66),
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '25:00',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontFamily: 'Newsreader',
                    color: colorScheme.primary,
                    fontSize: 64,
                    fontWeight: FontWeight.w400,
                    height: 0.95,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _TimerPresetPills(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerPresetPills extends StatelessWidget {
  const _TimerPresetPills();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _DurationChip(label: '15m'),
        _DurationChip(label: '25m', selected: true),
        _DurationChip(label: '45m'),
      ],
    );
  }
}

class _TimerSetupTaskCard extends StatelessWidget {
  const _TimerSetupTaskCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          children: [
            Text(
              'Review design direction',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'Newsreader',
                color: colorScheme.primary,
                fontWeight: FontWeight.w400,
                height: 1.08,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: const [
                _TaskTagPill(label: 'Design'),
                _TaskTagPill(label: 'Estimate 45m'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            const _TimerModeSelector(),
          ],
        ),
      ),
    );
  }
}

class _TimerSetupStartButton extends StatelessWidget {
  const _TimerSetupStartButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return FilledButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Start'),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        minimumSize: const Size.fromHeight(56),
        textStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _SupportFilterChip extends StatelessWidget {
  const _SupportFilterChip({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.09)
            : _labSurfaceWarm.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.66)
              : colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.62),
              size: 16,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportResultsPanel extends StatelessWidget {
  const _SupportResultsPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(_taskPanelRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SupportSectionHeader(label: 'RESULTS'),
            SizedBox(height: AppSpacing.xs),
            _SupportResultRow(
              icon: LucideIcons.circleCheck300,
              title: 'Review design direction',
              detail: 'Task - Today - Design',
              accent: _priorityCoral,
            ),
            _SupportResultRow(
              icon: LucideIcons.folder300,
              title: 'Design',
              detail: 'List - 7 open tasks',
              accent: _priorityGreen,
            ),
            _SupportResultRow(
              icon: LucideIcons.circleCheckBig300,
              title: 'Collect references',
              detail: 'Completed - Today',
              accent: _prioritySage,
              completed: true,
            ),
            _SupportResultRow(
              icon: LucideIcons.timer300,
              title: 'Draft restore flow',
              detail: 'Task - Focus-ready',
              accent: _priorityAmber,
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportResultRow extends StatelessWidget {
  const _SupportResultRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.accent,
    this.completed = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color accent;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleColor = completed
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.58)
        : colorScheme.onSurface.withValues(alpha: 0.82);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _labSoftIvory.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox.square(
              dimension: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    color: colorScheme.primary.withValues(alpha: 0.74),
                    size: 22,
                  ),
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: _PriorityMark(color: accent, size: 6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: titleColor,
                    decoration: completed ? TextDecoration.lineThrough : null,
                    decorationColor: titleColor,
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.66),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            LucideIcons.chevronRight300,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.44),
          ),
        ],
      ),
    );
  }
}

class _SettingsAccountCard extends StatelessWidget {
  const _SettingsAccountCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(_taskPanelRadius),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.38),
                ),
              ),
              child: SizedBox.square(
                dimension: 54,
                child: Center(
                  child: Text(
                    'Y',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFamily: 'Newsreader',
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Youhei',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Private sync workspace',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.68,
                      ),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
            const _SmallPill(label: 'E2EE'),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.label, required this.rows});

  final String label;
  final List<_SettingsRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSurfaceWarm.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(_taskPanelRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.48),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            _SupportSectionHeader(label: label),
            const SizedBox(height: AppSpacing.xs),
            for (var index = 0; index < rows.length; index += 1) ...[
              _SettingsRow(data: rows[index]),
              if (index < rows.length - 1)
                Divider(
                  height: AppSpacing.sm,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRowData {
  const _SettingsRowData({
    required this.icon,
    required this.title,
    required this.detail,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color accent;
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.data});

  final _SettingsRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _labSoftIvory.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(13),
            ),
            child: SizedBox.square(
              dimension: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    data.icon,
                    color: colorScheme.primary.withValues(alpha: 0.72),
                    size: 21,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _PriorityMark(color: data.accent, size: 5.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.66),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            LucideIcons.chevronRight300,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.44),
          ),
        ],
      ),
    );
  }
}

class _TimerModeSelector extends StatelessWidget {
  const _TimerModeSelector();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const labels = ['Timer', 'Pomodoro', 'Stopwatch'];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _labSoftIvory.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.44),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index += 1)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: index == 0
                        ? colorScheme.primary.withValues(alpha: 0.09)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                    border: index == 0
                        ? Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.68),
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Center(
                      child: Text(
                        labels[index],
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: index == 0
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                          fontWeight: FontWeight.w400,
                        ),
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

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.09)
            : _labSurfaceWarm.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.64)
              : colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SupportSectionHeader extends StatelessWidget {
  const _SupportSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.74),
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
