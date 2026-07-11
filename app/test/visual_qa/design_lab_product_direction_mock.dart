part of 'design_lab_mocks.dart';

const _directionForest = Color(0xFF285E46);
const _directionInk = Color(0xFF202820);
const _directionMuted = Color(0xFF73796F);
const _directionIvory = Color(0xFFF8F5EC);
const _directionPorcelain = Color(0xFFFFFDF8);
const _directionSage = Color(0xFFDDEBDD);
const _directionRule = Color(0xFFD9DDD3);
const _directionCoral = Color(0xFFD66B5D);

const _directionSerif = 'SourceSerif4';
const _directionSans = 'Inter';

class _ProductDirectionHomeMock extends StatelessWidget {
  const _ProductDirectionHomeMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _directionIvory,
      floatingActionButton: const _DirectionAddButton(),
      bottomNavigationBar: const _DirectionNavigation(selectedIndex: 0),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 92),
          children: const [
            _DirectionHomeHeader(),
            SizedBox(height: 18),
            _DirectionSectionLabel('NOW'),
            SizedBox(height: 7),
            _DirectionNowTask(),
            SizedBox(height: 24),
            _DirectionSectionLabel('QUEUE'),
            SizedBox(height: 5),
            _DirectionQueue(),
            SizedBox(height: 17),
            _DirectionReviewSchedule(),
          ],
        ),
      ),
    );
  }
}

class _DirectionHomeHeader extends StatelessWidget {
  const _DirectionHomeHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MAY 27 · TUESDAY',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Today',
                style: TextStyle(
                  fontFamily: _directionSerif,
                  color: _directionInk,
                  fontSize: 35,
                  fontWeight: FontWeight.w400,
                  height: 1.02,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(LucideIcons.search300, size: 21),
          color: _directionForest,
          style: IconButton.styleFrom(minimumSize: const Size.square(44)),
        ),
      ],
    );
  }
}

class _DirectionSectionLabel extends StatelessWidget {
  const _DirectionSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: _directionSans,
        color: _directionMuted,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.55,
      ),
    );
  }
}

class _DirectionNowTask extends StatelessWidget {
  const _DirectionNowTask();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _directionSage.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
        child: Row(
          children: [
            const _DirectionCheck(),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prepare launch notes',
                    style: TextStyle(
                      fontFamily: _directionSans,
                      color: _directionInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Design · 25 min',
                    style: TextStyle(
                      fontFamily: _directionSans,
                      color: _directionMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Focus'),
              style: TextButton.styleFrom(
                foregroundColor: _directionForest,
                minimumSize: const Size(78, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontFamily: _directionSans,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionQueue extends StatelessWidget {
  const _DirectionQueue();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: _directionPorcelain,
        border: Border(
          top: BorderSide(color: _directionRule, width: 0.7),
          bottom: BorderSide(color: _directionRule, width: 0.7),
        ),
      ),
      child: Column(
        children: [
          _DirectionTaskRow(
            title: 'Review onboarding copy',
            meta: 'Product',
            trailing: '9:30',
          ),
          _DirectionTaskRow(
            title: 'Finalize navigation states',
            meta: 'Design',
            trailing: '11:00',
            children: [
              _DirectionSubtask(title: 'Check compact width', isDone: true),
              _DirectionSubtask(title: 'Polish focus transition'),
            ],
          ),
          _DirectionTaskRow(
            title: 'Send release build',
            meta: 'Work',
            trailing: '14:00',
          ),
          _DirectionTaskRow(
            title: 'Renew domain settings',
            meta: 'Overdue · Personal',
            trailing: 'Mon',
            isOverdue: true,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _DirectionTaskRow extends StatelessWidget {
  const _DirectionTaskRow({
    required this.title,
    required this.meta,
    required this.trailing,
    this.children = const [],
    this.isOverdue = false,
    this.isLast = false,
  });

  final String title;
  final String meta;
  final String trailing;
  final List<_DirectionSubtask> children;
  final bool isOverdue;
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
          padding: const EdgeInsets.fromLTRB(0, 13, 12, 12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: _DirectionCheck(),
                  ),
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
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          style: TextStyle(
                            fontFamily: _directionSans,
                            color: isOverdue
                                ? _directionCoral
                                : _directionMuted,
                            fontSize: 11.5,
                            fontWeight: isOverdue
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    trailing,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _directionMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(children: children),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionSubtask extends StatelessWidget {
  const _DirectionSubtask({required this.title, this.isDone = false});

  final String title;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: CustomPaint(
              painter: _DirectionBranchPainter(color: _directionRule),
              child: Align(
                alignment: Alignment.centerRight,
                child: _DirectionCheck(isDone: isDone, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontFamily: _directionSans,
              color: isDone ? _directionMuted : _directionInk,
              fontSize: 13.5,
              decoration: isDone ? TextDecoration.lineThrough : null,
              decorationColor: _directionMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionBranchPainter extends CustomPainter {
  const _DirectionBranchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(3, 0)
        ..lineTo(3, size.height / 2)
        ..quadraticBezierTo(3, size.height / 2 + 3, 7, size.height / 2 + 3)
        ..lineTo(size.width - 9, size.height / 2 + 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DirectionBranchPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DirectionReviewSchedule extends StatelessWidget {
  const _DirectionReviewSchedule();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(12),
      child: const SizedBox(
        height: 48,
        child: Row(
          children: [
            Icon(
              LucideIcons.calendarDays300,
              color: _directionForest,
              size: 19,
            ),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Review schedule',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionForest,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(LucideIcons.chevronRight300, color: _directionMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ProductDirectionDetailMock extends StatelessWidget {
  const _ProductDirectionDetailMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _directionIvory,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          children: const [
            _DirectionDetailTopBar(),
            SizedBox(height: 13),
            _DirectionDetailHero(),
            SizedBox(height: 20),
            _DirectionFocusEntry(),
            SizedBox(height: 20),
            _DirectionProperties(),
            SizedBox(height: 26),
            _DirectionDetailSubtasks(),
          ],
        ),
      ),
    );
  }
}

class _DirectionDetailTopBar extends StatelessWidget {
  const _DirectionDetailTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(LucideIcons.arrowLeft300, size: 22),
          color: _directionForest,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () {},
          icon: const Icon(LucideIcons.moreHorizontal300, size: 22),
          color: _directionForest,
          style: IconButton.styleFrom(minimumSize: const Size.square(44)),
        ),
      ],
    );
  }
}

class _DirectionDetailHero extends StatelessWidget {
  const _DirectionDetailHero();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: _DirectionCheck(size: 24),
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prepare launch notes',
                style: TextStyle(
                  fontFamily: _directionSerif,
                  color: _directionInk,
                  fontSize: 29,
                  fontWeight: FontWeight.w400,
                  height: 1.08,
                  letterSpacing: -0.35,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Capture the decisions that make the release feel calm, clear, and ready to share.',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _directionMuted,
                  fontSize: 14,
                  height: 1.48,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DirectionFocusEntry extends StatelessWidget {
  const _DirectionFocusEntry();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _directionSage.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(13),
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(13),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.play_arrow_rounded, color: _directionForest, size: 24),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Start a 25 minute focus session',
                  style: TextStyle(
                    fontFamily: _directionSans,
                    color: _directionForest,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                LucideIcons.arrowUpRight300,
                color: _directionForest,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionProperties extends StatelessWidget {
  const _DirectionProperties();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _directionRule, width: 0.7),
          bottom: BorderSide(color: _directionRule, width: 0.7),
        ),
      ),
      child: Column(
        children: [
          _DirectionProperty(
            icon: LucideIcons.inbox300,
            label: 'List',
            value: 'Design',
          ),
          _DirectionProperty(
            icon: LucideIcons.calendarDays300,
            label: 'Due',
            value: 'Today',
          ),
          _DirectionProperty(
            icon: LucideIcons.clock300,
            label: 'Plan',
            value: '9:30 · 25 min',
          ),
          _DirectionProperty(
            icon: LucideIcons.flag300,
            label: 'Priority',
            value: 'High',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _DirectionProperty extends StatelessWidget {
  const _DirectionProperty({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: _directionRule, width: 0.55),
              ),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Icon(icon, color: _directionMuted, size: 18),
            const SizedBox(width: 12),
            SizedBox(
              width: 70,
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _directionMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _directionInk,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.chevronRight300,
              color: _directionMuted,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionDetailSubtasks extends StatelessWidget {
  const _DirectionDetailSubtasks();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _DirectionSectionLabel('SUBTASKS · 1 OF 3')),
            Text(
              '+ Add',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _directionForest,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: 9),
        _DirectionDetailSubtask(
          title: 'Collect final screenshots',
          isDone: true,
        ),
        _DirectionDetailSubtask(title: 'Write concise release summary'),
        _DirectionDetailSubtask(title: 'Proofread Japanese copy', isLast: true),
      ],
    );
  }
}

class _DirectionDetailSubtask extends StatelessWidget {
  const _DirectionDetailSubtask({
    required this.title,
    this.isDone = false,
    this.isLast = false,
  });

  final String title;
  final bool isDone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: CustomPaint(
              painter: _DirectionVerticalTreePainter(
                color: _directionRule,
                end: isLast,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: _DirectionCheck(isDone: isDone, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: _directionSans,
                color: isDone ? _directionMuted : _directionInk,
                fontSize: 14.5,
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionVerticalTreePainter extends CustomPainter {
  const _DirectionVerticalTreePainter({required this.color, required this.end});

  final Color color;
  final bool end;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final x = 4.0;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, end ? size.height / 2 : size.height),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x, size.height / 2)
        ..quadraticBezierTo(x, size.height / 2 + 4, x + 4, size.height / 2 + 4)
        ..lineTo(size.width - 10, size.height / 2 + 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DirectionVerticalTreePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.end != end;
}

class _ProductDirectionFocusMock extends StatelessWidget {
  const _ProductDirectionFocusMock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _directionIvory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
          child: Column(
            children: [
              const _DirectionFocusTopBar(),
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
              const SizedBox(height: 34),
              const _DirectionTimer(),
              const SizedBox(height: 34),
              const _DirectionFocusActions(),
              const Spacer(),
              const _DirectionMascotMoment(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionFocusTopBar extends StatelessWidget {
  const _DirectionFocusTopBar();

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
            'FOCUS SESSION · 1 OF 4',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _directionSans,
              color: _directionMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.25,
            ),
          ),
        ),
        const SizedBox(width: 44),
      ],
    );
  }
}

class _DirectionTimer extends StatelessWidget {
  const _DirectionTimer();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 274,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            painter: const _DirectionTimerPainter(progress: 0.72),
            child: const SizedBox.expand(),
          ),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '25:00',
                style: TextStyle(
                  fontFamily: _directionSerif,
                  color: _directionForest,
                  fontSize: 64,
                  fontWeight: FontWeight.w400,
                  height: 0.94,
                  letterSpacing: -1.5,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'until 10:05',
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

class _DirectionTimerPainter extends CustomPainter {
  const _DirectionTimerPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(11);
    final track = Paint()
      ..color = _directionSage
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = _directionForest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, active);
  }

  @override
  bool shouldRepaint(_DirectionTimerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _DirectionFocusActions extends StatelessWidget {
  const _DirectionFocusActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(LucideIcons.pause300, size: 18),
          label: const Text('Pause'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _directionForest,
            side: const BorderSide(color: _directionForest, width: 0.8),
            minimumSize: const Size(112, 48),
            textStyle: const TextStyle(
              fontFamily: _directionSans,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            foregroundColor: _directionMuted,
            minimumSize: const Size(92, 48),
            textStyle: const TextStyle(
              fontFamily: _directionSans,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: const Text('Finish'),
        ),
      ],
    );
  }
}

class _DirectionMascotMoment extends StatelessWidget {
  const _DirectionMascotMoment();

  @override
  Widget build(BuildContext context) {
    return const Opacity(
      opacity: 0.72,
      child: Column(
        children: [
          Icon(LucideIcons.bird300, color: _directionForest, size: 25),
          SizedBox(height: 4),
          SizedBox(width: 42, child: Divider(color: _directionRule, height: 1)),
        ],
      ),
    );
  }
}

class _DirectionCheck extends StatelessWidget {
  const _DirectionCheck({this.isDone = false, this.size = 21});

  final bool isDone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone ? _directionForest : Colors.transparent,
        border: Border.all(color: _directionForest, width: 1.05),
      ),
      child: SizedBox.square(
        dimension: size,
        child: isDone
            ? Icon(
                LucideIcons.check300,
                color: _directionPorcelain,
                size: size * 0.57,
              )
            : null,
      ),
    );
  }
}

class _DirectionAddButton extends StatelessWidget {
  const _DirectionAddButton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _directionForest.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: SizedBox.square(
        dimension: 48,
        child: Material(
          color: _directionForest,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () {},
            customBorder: const CircleBorder(),
            child: const Icon(
              LucideIcons.plus300,
              color: _directionPorcelain,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectionNavigation extends StatelessWidget {
  const _DirectionNavigation({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    const items = [
      (LucideIcons.house300, 'Home'),
      (LucideIcons.calendarDays300, 'Calendar'),
      (LucideIcons.listTodo300, 'Lists'),
      (LucideIcons.circleUserRound300, 'Account'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _directionPorcelain,
        border: Border(top: BorderSide(color: _directionRule, width: 0.65)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index += 1)
                Expanded(
                  child: _DirectionNavigationItem(
                    icon: items[index].$1,
                    label: items[index].$2,
                    isSelected: selectedIndex == index,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionNavigationItem extends StatelessWidget {
  const _DirectionNavigationItem({
    required this.icon,
    required this.label,
    required this.isSelected,
  });

  final IconData icon;
  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? _directionForest : _directionMuted;
    return InkWell(
      onTap: () {},
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: _directionSans,
              color: color,
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
