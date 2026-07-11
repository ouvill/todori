part of 'design_lab_mocks.dart';

class _ProductSystemListsMock extends StatelessWidget {
  const _ProductSystemListsMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _directionIvory,
      floatingActionButton: const _DirectionAddButton(),
      bottomNavigationBar: const _DirectionNavigation(selectedIndex: 2),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 92),
          children: const [
            _SystemHeader(
              eyebrow: 'WORKSPACES',
              title: 'Lists',
              actionIcon: LucideIcons.search300,
            ),
            SizedBox(height: 22),
            _DirectionSectionLabel('SMART VIEWS'),
            SizedBox(height: 7),
            _SystemLinearGroup(
              children: [
                _SystemListRow(
                  icon: LucideIcons.sun300,
                  title: 'Today',
                  count: '6',
                  tint: Color(0xFFF2C46D),
                ),
                _SystemListRow(
                  icon: LucideIcons.inbox300,
                  title: 'Inbox',
                  count: '3',
                  tint: Color(0xFFA9C9B5),
                ),
                _SystemListRow(
                  icon: LucideIcons.calendarDays300,
                  title: 'Scheduled',
                  count: '12',
                  tint: Color(0xFFAFC5D4),
                ),
                _SystemListRow(
                  icon: LucideIcons.circleCheck300,
                  title: 'Completed',
                  count: '24',
                  tint: Color(0xFFC8CCC3),
                  isLast: true,
                ),
              ],
            ),
            SizedBox(height: 24),
            _SystemSectionHeading(label: 'MY LISTS', action: 'Edit'),
            SizedBox(height: 7),
            _SystemLinearGroup(
              children: [
                _SystemCustomListRow(
                  title: 'Design',
                  subtitle: '7 open · updated today',
                  count: '7',
                  tint: _directionForest,
                  isSelected: true,
                ),
                _SystemCustomListRow(
                  title: 'Work',
                  subtitle: 'Launch and operations',
                  count: '9',
                  tint: Color(0xFFD58A5D),
                ),
                _SystemCustomListRow(
                  title: 'Personal',
                  subtitle: 'Home and errands',
                  count: '6',
                  tint: Color(0xFF7397B5),
                ),
                _SystemCustomListRow(
                  title: 'Learning',
                  subtitle: 'Reading and courses',
                  count: '3',
                  tint: Color(0xFF9986B5),
                  isLast: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSystemCreateMock extends StatelessWidget {
  const _ProductSystemCreateMock();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const IgnorePointer(child: _ProductDirectionHomeMock()),
        Positioned.fill(
          child: ColoredBox(color: _directionInk.withValues(alpha: 0.26)),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: _SystemCreateSheet(),
        ),
      ],
    );
  }
}

class _SystemCreateSheet extends StatelessWidget {
  const _SystemCreateSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: _directionPorcelain,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 9, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SystemSheetHandle()),
              const SizedBox(height: 20),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: _DirectionCheck(size: 22),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What needs doing?',
                          style: TextStyle(
                            fontFamily: _directionSans,
                            color: _directionInk,
                            fontSize: 21,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: 9),
                        Text(
                          'Add a note',
                          style: TextStyle(
                            fontFamily: _directionSans,
                            color: _directionMuted,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: _directionRule, height: 1),
              const SizedBox(height: 11),
              const Row(
                children: [
                  _SystemCreateProperty(
                    icon: LucideIcons.inbox300,
                    label: 'Inbox',
                  ),
                  SizedBox(width: 4),
                  _SystemCreateProperty(
                    icon: LucideIcons.calendarDays300,
                    label: 'Today',
                    isActive: true,
                  ),
                  SizedBox(width: 4),
                  _SystemCreateProperty(
                    icon: LucideIcons.clock300,
                    label: 'Any time',
                  ),
                  Spacer(),
                  _SystemCreateSubmit(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemSheetHandle extends StatelessWidget {
  const _SystemSheetHandle();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _directionRule,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const SizedBox(width: 34, height: 4),
    );
  }
}

class _SystemCreateProperty extends StatelessWidget {
  const _SystemCreateProperty({
    required this.icon,
    required this.label,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? _directionForest : _directionMuted;
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: _directionSans,
                color: color,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemCreateSubmit extends StatelessWidget {
  const _SystemCreateSubmit();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: Material(
        color: _directionForest,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () {},
          customBorder: const CircleBorder(),
          child: const Icon(
            LucideIcons.arrowUp300,
            color: _directionPorcelain,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _ProductSystemSearchMock extends StatelessWidget {
  const _ProductSystemSearchMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _directionIvory,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          children: const [
            _SystemSearchBar(),
            SizedBox(height: 24),
            _SystemSectionHeading(label: 'RECENT', action: 'Clear'),
            SizedBox(height: 7),
            _SystemLinearGroup(
              children: [
                _SystemResultRow(
                  icon: LucideIcons.circleCheck300,
                  title: 'Prepare launch notes',
                  subtitle: 'Today · Design',
                ),
                _SystemResultRow(
                  icon: LucideIcons.folder300,
                  title: 'Design',
                  subtitle: 'List · 7 open tasks',
                ),
                _SystemResultRow(
                  icon: LucideIcons.clock300,
                  title: 'Draft restore flow',
                  subtitle: 'Tomorrow · Product',
                  isLast: true,
                ),
              ],
            ),
            SizedBox(height: 26),
            _DirectionSectionLabel('QUICK FILTERS'),
            SizedBox(height: 8),
            _SystemFilterRows(),
          ],
        ),
      ),
    );
  }
}

class _SystemSearchBar extends StatelessWidget {
  const _SystemSearchBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(LucideIcons.arrowLeft300, size: 21),
          color: _directionForest,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _directionPorcelain,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _directionRule, width: 0.7),
            ),
            child: const SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(width: 12),
                  Icon(LucideIcons.search300, size: 18, color: _directionMuted),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Search tasks, lists, notes',
                      style: TextStyle(
                        fontFamily: _directionSans,
                        color: _directionMuted,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        IconButton(
          onPressed: () {},
          icon: const Icon(LucideIcons.slidersHorizontal300, size: 19),
          color: _directionForest,
          style: IconButton.styleFrom(minimumSize: const Size.square(44)),
        ),
      ],
    );
  }
}

class _SystemFilterRows extends StatelessWidget {
  const _SystemFilterRows();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _SystemFilterRow(
          icon: LucideIcons.calendarDays300,
          title: 'Due this week',
          detail: '8 tasks',
        ),
        _SystemFilterRow(
          icon: LucideIcons.timer300,
          title: 'Ready to focus',
          detail: '4 tasks',
        ),
        _SystemFilterRow(
          icon: LucideIcons.circleCheck300,
          title: 'Recently completed',
          detail: '12 tasks',
          isLast: true,
        ),
      ],
    );
  }
}

class _SystemFilterRow extends StatelessWidget {
  const _SystemFilterRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: _directionRule, width: 0.6),
              ),
      ),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Icon(icon, size: 18, color: _directionForest),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _directionInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              detail,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _directionMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              LucideIcons.chevronRight300,
              size: 16,
              color: _directionMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSystemAccountMock extends StatelessWidget {
  const _ProductSystemAccountMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _directionIvory,
      bottomNavigationBar: const _DirectionNavigation(selectedIndex: 3),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 86),
          children: const [
            _SystemHeader(
              eyebrow: 'PRIVATE WORKSPACE',
              title: 'Account',
              actionIcon: LucideIcons.moreHorizontal300,
            ),
            SizedBox(height: 20),
            _SystemIdentity(),
            SizedBox(height: 24),
            _SystemSectionHeading(label: 'SYNC', action: 'Sync now'),
            SizedBox(height: 7),
            _SystemLinearGroup(
              children: [
                _SystemSettingRow(
                  icon: LucideIcons.refreshCw300,
                  title: 'Up to date',
                  subtitle: 'Last synced 2 minutes ago',
                ),
                _SystemSettingRow(
                  icon: LucideIcons.lock300,
                  title: 'End-to-end encrypted',
                  subtitle: 'Keys stay on your devices',
                  isLast: true,
                ),
              ],
            ),
            SizedBox(height: 24),
            _DirectionSectionLabel('PREFERENCES'),
            SizedBox(height: 7),
            _SystemLinearGroup(
              children: [
                _SystemSettingRow(
                  icon: LucideIcons.bell300,
                  title: 'Notifications',
                  subtitle: 'Planning reminder at 9:00',
                ),
                _SystemSettingRow(
                  icon: LucideIcons.timer300,
                  title: 'Focus',
                  subtitle: '25 minute default',
                ),
                _SystemSettingRow(
                  icon: LucideIcons.palette300,
                  title: 'Appearance',
                  subtitle: 'Warm ivory · System light',
                ),
                _SystemSettingRow(
                  icon: LucideIcons.languages300,
                  title: 'Language',
                  subtitle: 'English',
                  isLast: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemIdentity extends StatelessWidget {
  const _SystemIdentity();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: _directionSage,
            shape: BoxShape.circle,
          ),
          child: const SizedBox.square(
            dimension: 52,
            child: Center(
              child: Text(
                'Y',
                style: TextStyle(
                  fontFamily: _directionSerif,
                  color: _directionForest,
                  fontSize: 25,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Youhei',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'youhei@example.com',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          LucideIcons.chevronRight300,
          color: _directionMuted,
          size: 17,
        ),
      ],
    );
  }
}

class _ProductSystemFocusSetupMock extends StatelessWidget {
  const _ProductSystemFocusSetupMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _directionIvory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
          child: Column(
            children: [
              const _SystemFocusSetupTopBar(),
              const SizedBox(height: 28),
              const Text(
                'Prepare launch notes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 35),
              const _SystemDurationDial(),
              const SizedBox(height: 30),
              const _SystemPresetRow(),
              const SizedBox(height: 27),
              const _SystemFocusModeRow(),
              const Spacer(),
              const _SystemStartFocusButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemFocusSetupTopBar extends StatelessWidget {
  const _SystemFocusSetupTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(LucideIcons.x300, size: 22),
          color: _directionForest,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
        const Expanded(
          child: Text(
            'SET UP FOCUS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _directionSans,
              color: _directionMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.3,
            ),
          ),
        ),
        const SizedBox(width: 44),
      ],
    );
  }
}

class _SystemDurationDial extends StatelessWidget {
  const _SystemDurationDial();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 246,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            painter: const _SystemSetupDialPainter(),
            child: const SizedBox.expand(),
          ),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '25',
                style: TextStyle(
                  fontFamily: _directionSerif,
                  color: _directionForest,
                  fontSize: 66,
                  fontWeight: FontWeight.w400,
                  height: 0.9,
                ),
              ),
              SizedBox(height: 9),
              Text(
                'minutes',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SystemSetupDialPainter extends CustomPainter {
  const _SystemSetupDialPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final track = Paint()
      ..color = _directionSage
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final active = Paint()
      ..color = _directionForest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.35,
      false,
      active,
    );
    final knobAngle = -math.pi / 2 + math.pi * 1.35;
    final knob = Offset(
      center.dx + math.cos(knobAngle) * radius,
      center.dy + math.sin(knobAngle) * radius,
    );
    canvas.drawCircle(knob, 7, Paint()..color = _directionPorcelain);
    canvas.drawCircle(knob, 4, Paint()..color = _directionForest);
  }

  @override
  bool shouldRepaint(_SystemSetupDialPainter oldDelegate) => false;
}

class _SystemPresetRow extends StatelessWidget {
  const _SystemPresetRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SystemPreset(label: '15'),
        SizedBox(width: 7),
        _SystemPreset(label: '25', isSelected: true),
        SizedBox(width: 7),
        _SystemPreset(label: '45'),
        SizedBox(width: 7),
        _SystemPreset(label: '60'),
      ],
    );
  }
}

class _SystemPreset extends StatelessWidget {
  const _SystemPreset({required this.label, this.isSelected = false});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected ? _directionSage : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: _directionSans,
              color: isSelected ? _directionForest : _directionMuted,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemFocusModeRow extends StatelessWidget {
  const _SystemFocusModeRow();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Divider(color: _directionRule, height: 1),
        SizedBox(
          height: 50,
          child: Row(
            children: [
              Text(
                'Mode',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionMuted,
                  fontSize: 13,
                ),
              ),
              Spacer(),
              Text(
                'Timer',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionInk,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 5),
              Icon(
                LucideIcons.chevronRight300,
                color: _directionMuted,
                size: 17,
              ),
            ],
          ),
        ),
        Divider(color: _directionRule, height: 1),
      ],
    );
  }
}

class _SystemStartFocusButton extends StatelessWidget {
  const _SystemStartFocusButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.play_arrow_rounded, size: 21),
        label: const Text('Begin focus'),
        style: FilledButton.styleFrom(
          backgroundColor: _directionForest,
          foregroundColor: _directionPorcelain,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: _directionSans,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SystemHeader extends StatelessWidget {
  const _SystemHeader({
    required this.eyebrow,
    required this.title,
    required this.actionIcon,
  });

  final String eyebrow;
  final String title;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _directionMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: _directionSerif,
                  color: _directionInk,
                  fontSize: 35,
                  fontWeight: FontWeight.w400,
                  height: 1,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: Icon(actionIcon, size: 21),
          color: _directionForest,
          style: IconButton.styleFrom(minimumSize: const Size.square(44)),
        ),
      ],
    );
  }
}

class _SystemSectionHeading extends StatelessWidget {
  const _SystemSectionHeading({required this.label, required this.action});

  final String label;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _DirectionSectionLabel(label)),
        Text(
          action,
          style: const TextStyle(
            fontFamily: _directionSans,
            color: _directionForest,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SystemLinearGroup extends StatelessWidget {
  const _SystemLinearGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _directionPorcelain,
        border: Border(
          top: BorderSide(color: _directionRule, width: 0.7),
          bottom: BorderSide(color: _directionRule, width: 0.7),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _SystemListRow extends StatelessWidget {
  const _SystemListRow({
    required this.icon,
    required this.title,
    required this.count,
    required this.tint,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String count;
  final Color tint;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return _SystemRowFrame(
      isLast: isLast,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: _directionForest, size: 17),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _directionInk,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            count,
            style: const TextStyle(
              fontFamily: _directionSans,
              color: _directionMuted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 5),
          const Icon(
            LucideIcons.chevronRight300,
            color: _directionMuted,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _SystemCustomListRow extends StatelessWidget {
  const _SystemCustomListRow({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.tint,
    this.isSelected = false,
    this.isLast = false,
  });

  final String title;
  final String subtitle;
  final String count;
  final Color tint;
  final bool isSelected;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: isSelected
          ? _directionSage.withValues(alpha: 0.46)
          : Colors.transparent,
      child: _SystemRowFrame(
        isLast: isLast,
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 9),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _directionInk,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _directionMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              count,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _directionMuted,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              LucideIcons.chevronRight300,
              color: _directionMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemResultRow extends StatelessWidget {
  const _SystemResultRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return _SystemRowFrame(
      isLast: isLast,
      child: Row(
        children: [
          Icon(icon, color: _directionForest, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: _directionSans,
                    color: _directionInk,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: _directionSans,
                    color: _directionMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight300,
            color: _directionMuted,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _SystemSettingRow extends StatelessWidget {
  const _SystemSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return _SystemRowFrame(
      isLast: isLast,
      child: Row(
        children: [
          Icon(icon, color: _directionForest, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: _directionSans,
                    color: _directionInk,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: _directionSans,
                    color: _directionMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight300,
            color: _directionMuted,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _SystemRowFrame extends StatelessWidget {
  const _SystemRowFrame({required this.child, required this.isLast});

  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: _directionRule, width: 0.6),
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 11, 12, 11),
          child: child,
        ),
      ),
    );
  }
}
