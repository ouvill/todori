part of 'design_lab_mocks.dart';

class _RadicalListTasksMock extends StatelessWidget {
  const _RadicalListTasksMock({
    this.onBack,
    this.onTaskTap,
    this.onActions,
    this.onDueDate,
    this.onAdd,
  });

  final VoidCallback? onBack;
  final VoidCallback? onTaskTap;
  final VoidCallback? onActions;
  final VoidCallback? onDueDate;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      bottomNavigationBar: _RadicalNav(selectedIndex: 3, onAdd: onAdd),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 76),
          children: [
            _CoverageRouteBar(
              onBack: onBack,
              onMore: onActions,
              moreKey: const ValueKey('design-lab-list-actions'),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalSimpleHeading(title: 'Design', trailing: '7 open'),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _CoverageToolbar(
                label: 'MANUAL ORDER',
                action: 'Sort  ↕',
                onAction: onDueDate,
              ),
            ),
            const SizedBox(height: 4),
            _RadicalTaskRow(
              title: 'Prepare launch notes',
              meta: 'Today · 25 minutes',
              time: '9:00',
              onTap: onTaskTap,
            ),
            const _RadicalTaskRow(
              title: 'Refine empty states',
              meta: 'Tomorrow · High',
              time: '',
            ),
            const _RadicalTaskRow(
              title: 'Finalize navigation states',
              meta: 'Friday',
              time: '11:00',
              children: [
                _RadicalSubtask(title: 'Check compact width', isDone: true),
                _RadicalSubtask(
                  title: 'Polish focus transition',
                  hasChildren: true,
                ),
                _RadicalSubtask(
                  title: 'Verify reduced motion',
                  depth: 1,
                  isLast: true,
                ),
              ],
            ),
            const _RadicalTaskRow(
              title: 'Review Japanese copy',
              meta: 'No date',
              time: '',
              isLast: true,
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalCompletedDisclosure(
                isExpanded: false,
                countLabel: '3 completed',
                onTap: null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverageRouteBar extends StatelessWidget {
  const _CoverageRouteBar({
    this.onBack,
    this.onMore,
    this.moreKey,
    this.trailing,
  });

  final VoidCallback? onBack;
  final VoidCallback? onMore;
  final Key? moreKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack ?? () {},
          icon: const Icon(LucideIcons.arrowLeft300, size: 21),
          color: _rInk,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          trailing!
        else
          IconButton(
            key: moreKey,
            onPressed: onMore ?? () {},
            icon: const Icon(LucideIcons.moreHorizontal300, size: 21),
            color: _rInk,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerRight,
            ),
          ),
      ],
    );
  }
}

class _CoverageToolbar extends StatelessWidget {
  const _CoverageToolbar({
    required this.label,
    required this.action,
    this.onAction,
  });

  final String label;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 39,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction ?? () {},
            style: TextButton.styleFrom(
              foregroundColor: _rGreen,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 39),
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(
              action,
              style: const TextStyle(
                fontFamily: _directionSans,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadicalTaskEditMock extends StatelessWidget {
  const _RadicalTaskEditMock({this.onClose, this.onSave});

  final VoidCallback? onClose;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 32),
          children: [
            _CoverageRouteBar(
              onBack: onClose,
              trailing: TextButton(
                key: const ValueKey('design-lab-save-task'),
                onPressed: onSave ?? () {},
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 18),
            const _CoverageFieldLabel(label: 'TASK'),
            const _CoverageUnderlineField(
              initialValue: 'Prepare launch notes',
              textStyle: TextStyle(
                fontFamily: _directionSans,
                color: _rInk,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                height: 1.12,
                letterSpacing: -0.65,
              ),
            ),
            const SizedBox(height: 28),
            const _CoverageFieldLabel(label: 'NOTE'),
            const _CoverageUnderlineField(
              initialValue:
                  'Capture the decisions that make the release feel calm, clear, and ready to share.',
              maxLines: 4,
            ),
            const SizedBox(height: 32),
            const _CoveragePropertyRow(
              label: 'List',
              value: 'Design',
              icon: LucideIcons.listTodo300,
            ),
            const _CoveragePropertyRow(
              label: 'Due',
              value: 'Today',
              icon: LucideIcons.calendarDays300,
            ),
            const _CoveragePropertyRow(
              label: 'Priority',
              value: 'High',
              icon: LucideIcons.flag300,
              valueColor: _rCoral,
            ),
            const _CoveragePropertyRow(
              label: 'Reminder',
              value: '9:15',
              icon: LucideIcons.bell300,
              isLast: true,
            ),
            const SizedBox(height: 28),
            const Text(
              'Changes can be undone for a few seconds after saving.',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverageFieldLabel extends StatelessWidget {
  const _CoverageFieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: _directionSans,
          color: _rMuted,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.45,
        ),
      ),
    );
  }
}

class _CoverageUnderlineField extends StatelessWidget {
  const _CoverageUnderlineField({
    required this.initialValue,
    this.maxLines = 2,
    this.obscureText = false,
    this.textStyle,
  });

  final String initialValue;
  final int maxLines;
  final bool obscureText;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      maxLines: obscureText ? 1 : maxLines,
      obscureText: obscureText,
      style:
          textStyle ??
          const TextStyle(
            fontFamily: _directionSans,
            color: _rInk,
            fontSize: 14,
            height: 1.45,
          ),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.fromLTRB(0, 4, 0, 12),
        border: UnderlineInputBorder(borderSide: BorderSide(color: _rRule)),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _rRule),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _rGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _CoveragePropertyRow extends StatelessWidget {
  const _CoveragePropertyRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = _rInk,
    this.isLast = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _rRule, width: 0.65)),
      ),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Icon(icon, size: 17, color: _rMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 12.5,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: _directionSans,
                color: valueColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.chevronRight300, size: 15, color: _rMuted),
          ],
        ),
      ),
    );
  }
}

class _RadicalAccountAccessMock extends StatelessWidget {
  const _RadicalAccountAccessMock({
    this.onBack,
    this.registerMode = false,
    this.onModeChanged,
    this.onSubmit,
  });

  final VoidCallback? onBack;
  final bool registerMode;
  final ValueChanged<bool>? onModeChanged;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 32),
          children: [
            _CoverageRouteBar(onBack: onBack, trailing: const SizedBox()),
            const SizedBox(height: 16),
            Text(
              registerMode ? 'Create account' : 'Welcome back',
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rInk,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              registerMode
                  ? 'Create the private sync identity used across your devices.'
                  : 'Sign in to continue your private, encrypted sync.',
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: _CoverageModeButton(
                    label: 'SIGN IN',
                    selected: !registerMode,
                    onTap: () => onModeChanged?.call(false),
                  ),
                ),
                Expanded(
                  child: _CoverageModeButton(
                    label: 'CREATE ACCOUNT',
                    selected: registerMode,
                    onTap: () => onModeChanged?.call(true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _CoverageFieldLabel(label: 'EMAIL'),
            const _CoverageUnderlineField(initialValue: 'youhei@example.com'),
            const SizedBox(height: 22),
            const _CoverageFieldLabel(label: 'PASSWORD'),
            const _CoverageUnderlineField(
              initialValue: 'private-password',
              obscureText: true,
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const ValueKey('design-lab-account-submit'),
                onPressed: onSubmit ?? () {},
                style: FilledButton.styleFrom(
                  backgroundColor: _rGreen,
                  foregroundColor: _rNightText,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  registerMode ? 'Create private account' : 'Sign in',
                ),
              ),
            ),
            const SizedBox(height: 36),
            const _RadicalSectionTitle(
              label: 'PRIVATE SYNC SERVER',
              trailing: 'Advanced',
            ),
            const SizedBox(height: 12),
            const _CoverageUnderlineField(
              initialValue: 'https://sync.todori.app',
            ),
            const SizedBox(height: 12),
            const Text(
              'Your encryption keys remain on your devices.',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverageModeButton extends StatelessWidget {
  const _CoverageModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? _rGreen : _rRule,
              width: selected ? 2 : 0.65,
            ),
          ),
        ),
        child: SizedBox(
          height: 43,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: _directionSans,
                color: selected ? _rGreen : _rMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadicalActionSheetMock extends StatelessWidget {
  const _RadicalActionSheetMock();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const IgnorePointer(child: _RadicalListTasksMock()),
        Positioned.fill(
          child: ColoredBox(color: _rInk.withValues(alpha: 0.28)),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: _RadicalActionSheetContent(),
        ),
      ],
    );
  }
}

class _RadicalActionSheetContent extends StatelessWidget {
  const _RadicalActionSheetContent({this.onDueDate});

  final VoidCallback? onDueDate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _rSheet,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                child: Divider(color: _rRule, thickness: 3),
              ),
              const SizedBox(height: 15),
              const _RadicalSectionTitle(
                label: 'LIST ACTIONS',
                trailing: 'Design',
              ),
              const SizedBox(height: 6),
              const _CoverageSheetAction(
                icon: LucideIcons.pencil300,
                label: 'Rename list',
              ),
              const _CoverageSheetAction(
                icon: LucideIcons.arrowDownUp300,
                label: 'Change sort order',
              ),
              _CoverageSheetAction(
                icon: LucideIcons.calendarDays300,
                label: 'Change a task due date',
                onTap: onDueDate,
              ),
              const _CoverageSheetAction(
                icon: LucideIcons.archive300,
                label: 'Archive list',
              ),
              const _CoverageSheetAction(
                icon: LucideIcons.trash2300,
                label: 'Delete list',
                destructive: true,
                isLast: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverageSheetAction extends StatelessWidget {
  const _CoverageSheetAction({
    required this.icon,
    required this.label,
    this.destructive = false,
    this.isLast = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool destructive;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? _rCoral : _rInk;
    return InkWell(
      onTap: onTap ?? () {},
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: _rRule, width: 0.65)),
        ),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Icon(icon, size: 17, color: destructive ? _rCoral : _rMuted),
              const SizedBox(width: 13),
              Text(
                label,
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadicalDueDateSheetMock extends StatelessWidget {
  const _RadicalDueDateSheetMock();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const IgnorePointer(child: _RadicalListTasksMock()),
        Positioned.fill(
          child: ColoredBox(color: _rInk.withValues(alpha: 0.28)),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: _RadicalDueDateSheetContent(),
        ),
      ],
    );
  }
}

class _RadicalDueDateSheetContent extends StatelessWidget {
  const _RadicalDueDateSheetContent();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _rSheet,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                child: Divider(color: _rRule, thickness: 3),
              ),
              const SizedBox(height: 15),
              const _RadicalSectionTitle(
                label: 'DUE DATE',
                trailing: 'Prepare launch notes',
              ),
              const SizedBox(height: 7),
              const _CoverageDueOption(label: 'Today', value: 'Tue 27'),
              const _CoverageDueOption(label: 'Tomorrow', value: 'Wed 28'),
              const _CoverageDueOption(label: 'This weekend', value: 'Sat 31'),
              const _CoverageDueOption(
                label: 'Choose a date',
                value: 'Calendar  →',
              ),
              const _CoverageDueOption(
                label: 'No date',
                value: '',
                muted: true,
                isLast: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverageDueOption extends StatelessWidget {
  const _CoverageDueOption({
    required this.label,
    required this.value,
    this.muted = false,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool muted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _rRule, width: 0.65)),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: muted ? _rMuted : _rInk,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalSystemStatesMock extends StatelessWidget {
  const _RadicalSystemStatesMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
          children: const [
            _RadicalSimpleHeading(title: 'System states', trailing: 'UI kit'),
            SizedBox(height: 32),
            _RadicalSectionTitle(label: 'EMPTY', trailing: 'No tasks'),
            SizedBox(height: 16),
            _CoverageStateRow(
              icon: LucideIcons.checkCheck300,
              title: 'The day is clear',
              body: 'Add something when it deserves your attention.',
            ),
            SizedBox(height: 32),
            _RadicalSectionTitle(label: 'LOADING', trailing: 'Syncing'),
            SizedBox(height: 16),
            _CoverageStateRow(
              icon: LucideIcons.refreshCw300,
              title: 'Bringing your tasks up to date',
              body: 'Encrypted changes are being reconciled.',
            ),
            SizedBox(height: 32),
            _RadicalSectionTitle(label: 'ERROR', trailing: 'Retry'),
            SizedBox(height: 16),
            _CoverageStateRow(
              icon: LucideIcons.cloudOff300,
              title: 'Couldn’t reach private sync',
              body: 'Your local tasks are safe. Try again when connected.',
              error: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverageStateRow extends StatelessWidget {
  const _CoverageStateRow({
    required this.icon,
    required this.title,
    required this.body,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: 38,
          child: Icon(icon, color: error ? _rCoral : _rGreen, size: 21),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _rInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RadicalOnboardingMock extends StatelessWidget {
  const _RadicalOnboardingMock({this.onContinue});

  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TODORI',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.1,
                ),
              ),
              const Spacer(flex: 2),
              const Text(
                'Make room for\nwhat matters.',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rInk,
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 300,
                child: Text(
                  'A quiet place for today’s work, private sync, and the progress you want to remember.',
                  style: TextStyle(
                    fontFamily: _directionSans,
                    color: _rMuted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(flex: 3),
              const Row(
                children: [
                  Expanded(child: Divider(color: _rGreen, thickness: 2)),
                  Expanded(child: Divider(color: _rRule, thickness: 1)),
                  Expanded(child: Divider(color: _rRule, thickness: 1)),
                ],
              ),
              const SizedBox(height: 13),
              const Text(
                '1 OF 3  ·  YOUR DAY',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: onContinue ?? () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: _rGreen,
                    foregroundColor: _rNightText,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text('Continue  →'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
