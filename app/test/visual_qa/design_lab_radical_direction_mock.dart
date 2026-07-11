part of 'design_lab_mocks.dart';

const _rCanvas = Color(0xFFF3F0E7);
const _rSheet = Color(0xFFF9F7F0);
const _rInk = Color(0xFF182019);
const _rMuted = Color(0xFF73786F);
const _rGreen = Color(0xFF1D6048);
const _rSage = Color(0xFFBFD7C8);
const _rRule = Color(0xFFD3D3C9);
const _rCoral = Color(0xFFC96357);
const _rNight = Color(0xFF183E31);
const _rNightMuted = Color(0xFFAFC8BA);
const _rNightText = Color(0xFFF5F0E4);

class _RadicalHomeMock extends StatelessWidget {
  const _RadicalHomeMock({
    this.onSearch,
    this.onTaskTap,
    this.onNavSelected,
    this.onAdd,
  });

  final VoidCallback? onSearch;
  final VoidCallback? onTaskTap;
  final ValueChanged<int>? onNavSelected;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      bottomNavigationBar: _RadicalNav(
        selectedIndex: 0,
        onSelected: onNavSelected,
        onAdd: onAdd,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 76),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalBrandBar(onSearch: onSearch),
            ),
            const SizedBox(height: 23),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalHomeHeading(),
            ),
            const SizedBox(height: 29),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalSectionTitle(label: 'TODAY', trailing: '5 open'),
            ),
            const SizedBox(height: 3),
            _RadicalTaskStream(onTaskTap: onTaskTap),
            const SizedBox(height: 17),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalCalendarLink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalBrandBar extends StatelessWidget {
  const _RadicalBrandBar({this.onSearch});

  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        IconButton(
          onPressed: onSearch ?? () {},
          icon: const Icon(LucideIcons.search300, size: 20),
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

class _RadicalHomeHeading extends StatelessWidget {
  const _RadicalHomeHeading();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tuesday, May 27',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 12.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Today',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rInk,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 2),
          child: Text(
            '1 overdue',
            style: TextStyle(
              fontFamily: _directionSans,
              color: _rCoral,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RadicalTaskStream extends StatelessWidget {
  const _RadicalTaskStream({this.onTaskTap});

  final VoidCallback? onTaskTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RadicalTaskRow(
          title: 'Prepare launch notes',
          meta: 'Design · 25 minutes',
          time: '9:00',
          onTap: onTaskTap,
        ),
        const _RadicalTaskRow(
          title: 'Review onboarding copy',
          meta: 'Product',
          time: '9:30',
        ),
        _RadicalTaskRow(
          title: 'Finalize navigation states',
          meta: 'Design',
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
        _RadicalTaskRow(
          title: 'Send release build',
          meta: 'Work',
          time: '14:00',
        ),
        _RadicalTaskRow(
          title: 'Renew domain settings',
          meta: 'Personal · overdue',
          time: 'Mon',
          isOverdue: true,
          isLast: true,
        ),
      ],
    );
  }
}

class _RadicalTaskRow extends StatelessWidget {
  const _RadicalTaskRow({
    required this.title,
    required this.meta,
    required this.time,
    this.children = const [],
    this.isOverdue = false,
    this.isLast = false,
    this.onTap,
  });

  final String title;
  final String meta;
  final String time;
  final List<_RadicalSubtask> children;
  final bool isOverdue;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 15),
            child: _RadicalCheck(),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: _rRule, width: 0.65),
                      ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: _directionSans,
                                  color: _rInk,
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
                                  color: isOverdue ? _rCoral : _rMuted,
                                  fontSize: 11.5,
                                  fontWeight: isOverdue
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          time,
                          style: const TextStyle(
                            fontFamily: _directionSans,
                            color: _rMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    if (children.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Column(children: children),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadicalSubtask extends StatelessWidget {
  const _RadicalSubtask({
    required this.title,
    this.isDone = false,
    this.depth = 0,
    this.isLast = false,
    this.hasChildren = false,
  });

  final String title;
  final bool isDone;
  final int depth;
  final bool isLast;
  final bool hasChildren;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 28 + (depth * 22),
            child: CustomPaint(
              painter: _RadicalBranchPainter(
                depth: depth,
                isLast: isLast,
                hasChildren: hasChildren,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: _RadicalCheck(isDone: isDone, size: 17),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _directionSans,
                color: isDone ? _rMuted : _rInk,
                fontSize: 13.5,
                decoration: isDone ? TextDecoration.lineThrough : null,
                decorationColor: _rMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadicalBranchPainter extends CustomPainter {
  const _RadicalBranchPainter({
    required this.depth,
    required this.isLast,
    required this.hasChildren,
  });

  final int depth;
  final bool isLast;
  final bool hasChildren;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _rRule
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var ancestor = 1; ancestor < depth; ancestor += 1) {
      final x = 19.5 + ((ancestor - 1) * 22.0);
      canvas.drawLine(
        Offset(x, 0),
        Offset(
          x,
          isLast && ancestor == depth - 1 ? size.height / 2 : size.height,
        ),
        paint,
      );
    }
    final x = depth == 0 ? 1.0 : 19.5 + ((depth - 1) * 22.0);
    canvas.drawPath(
      Path()
        ..moveTo(x, 0)
        ..lineTo(x, size.height / 2)
        ..quadraticBezierTo(x, size.height / 2 + 3, x + 4, size.height / 2 + 3)
        ..lineTo(size.width - 23, size.height / 2 + 3),
      paint,
    );
    if (hasChildren) {
      final childStemX = size.width - 8.5;
      canvas.drawLine(
        Offset(childStemX, size.height / 2 + 12.5),
        Offset(childStemX, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RadicalBranchPainter oldDelegate) =>
      oldDelegate.depth != depth ||
      oldDelegate.isLast != isLast ||
      oldDelegate.hasChildren != hasChildren;
}

class _RadicalCalendarLink extends StatelessWidget {
  const _RadicalCalendarLink();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: const SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'See the rest of the week',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Calendar  →',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalDetailMock extends StatelessWidget {
  const _RadicalDetailMock({this.onBack, this.onBeginFocus});

  final VoidCallback? onBack;
  final VoidCallback? onBeginFocus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
          children: [
            _RadicalRouteBar(onBack: onBack),
            const SizedBox(height: 19),
            const _RadicalDetailTitle(),
            const SizedBox(height: 25),
            _RadicalDetailFocusLink(onTap: onBeginFocus),
            const SizedBox(height: 27),
            const _RadicalMetadataGrid(),
            const SizedBox(height: 32),
            const _RadicalSectionTitle(label: 'SUBTASKS', trailing: '1 / 4'),
            const SizedBox(height: 7),
            const _RadicalDetailTree(),
          ],
        ),
      ),
    );
  }
}

class _RadicalRouteBar extends StatelessWidget {
  const _RadicalRouteBar({this.onBack});

  final VoidCallback? onBack;

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
        IconButton(
          onPressed: () {},
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

class _RadicalDetailTitle extends StatelessWidget {
  const _RadicalDetailTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 5),
          child: _RadicalCheck(size: 23),
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prepare launch notes',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rInk,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                  height: 1.08,
                ),
              ),
              SizedBox(height: 11),
              Text(
                'Capture the decisions that make the release feel calm, clear, and ready to share.',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RadicalDetailFocusLink extends StatelessWidget {
  const _RadicalDetailFocusLink({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          height: 45,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'Begin a 25 minute focus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _directionSans,
                    color: _rGreen,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text('→', style: TextStyle(color: _rGreen, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadicalMetadataGrid extends StatelessWidget {
  const _RadicalMetadataGrid();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 36),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _RadicalMeta(label: 'LIST', value: 'Design'),
              ),
              Expanded(
                child: _RadicalMeta(label: 'DUE', value: 'Today'),
              ),
            ],
          ),
          SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _RadicalMeta(label: 'PLAN', value: '9:30 · 25m'),
              ),
              Expanded(
                child: _RadicalMeta(
                  label: 'PRIORITY',
                  value: 'High',
                  valueColor: _rCoral,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadicalMeta extends StatelessWidget {
  const _RadicalMeta({
    required this.label,
    required this.value,
    this.valueColor = _rInk,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: _directionSans,
            color: _rMuted,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontFamily: _directionSans,
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _RadicalDetailTree extends StatelessWidget {
  const _RadicalDetailTree();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _RadicalDetailSubtask(title: 'Collect final screenshots', isDone: true),
        _RadicalDetailSubtask(
          title: 'Write concise release summary',
          hasChildren: true,
        ),
        _RadicalDetailSubtask(
          title: 'Confirm product highlights',
          depth: 1,
          isLast: true,
        ),
        _RadicalDetailSubtask(title: 'Proofread Japanese copy', isLast: true),
        SizedBox(height: 5),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 36),
            child: Text(
              '+  Add subtask',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _rGreen,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RadicalDetailSubtask extends StatelessWidget {
  const _RadicalDetailSubtask({
    required this.title,
    this.isDone = false,
    this.isLast = false,
    this.depth = 0,
    this.hasChildren = false,
  });

  final String title;
  final bool isDone;
  final bool isLast;
  final int depth;
  final bool hasChildren;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 49,
      child: Row(
        children: [
          SizedBox(
            width: 34 + (depth * 22),
            child: CustomPaint(
              painter: _RadicalTreePainter(
                depth: depth,
                end: isLast,
                hasChildren: hasChildren,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: _RadicalCheck(isDone: isDone, size: 19),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: _directionSans,
                color: isDone ? _rMuted : _rInk,
                fontSize: 14.5,
                decoration: isDone ? TextDecoration.lineThrough : null,
                decorationColor: _rMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadicalTreePainter extends CustomPainter {
  const _RadicalTreePainter({
    required this.depth,
    required this.end,
    required this.hasChildren,
  });

  final int depth;
  final bool end;
  final bool hasChildren;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _rRule
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var ancestor = 1; ancestor < depth; ancestor += 1) {
      final x = 24.5 + ((ancestor - 1) * 22.0);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, end && ancestor == depth - 1 ? size.height / 2 : size.height),
        paint,
      );
    }
    final x = depth == 0 ? 3.0 : 24.5 + ((depth - 1) * 22.0);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, end ? size.height / 2 : size.height),
      paint,
    );
    if (hasChildren) {
      final childStemX = size.width - 9.5;
      canvas.drawLine(
        Offset(childStemX, size.height / 2 + 13.5),
        Offset(childStemX, size.height),
        paint,
      );
    }
    canvas.drawLine(
      Offset(x, size.height / 2),
      Offset(size.width - 25, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RadicalTreePainter oldDelegate) =>
      oldDelegate.depth != depth ||
      oldDelegate.end != end ||
      oldDelegate.hasChildren != hasChildren;
}

class _RadicalListsMock extends StatelessWidget {
  const _RadicalListsMock({this.onSearch, this.onNavSelected, this.onAdd});

  final VoidCallback? onSearch;
  final ValueChanged<int>? onNavSelected;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      bottomNavigationBar: _RadicalNav(
        selectedIndex: 3,
        onSelected: onNavSelected,
        onAdd: onAdd,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 15, 24, 76),
          children: [
            _RadicalBrandBar(onSearch: onSearch),
            const SizedBox(height: 22),
            const _RadicalSimpleHeading(title: 'Lists', trailing: 'Edit'),
            const SizedBox(height: 24),
            const _RadicalSectionTitle(label: 'SMART', trailing: '45 tasks'),
            const SizedBox(height: 3),
            const _RadicalListRow(title: 'Today', count: '6', marker: _rGreen),
            const _RadicalListRow(
              title: 'Inbox',
              count: '3',
              marker: Color(0xFF82A994),
            ),
            const _RadicalListRow(
              title: 'Scheduled',
              count: '12',
              marker: Color(0xFF7898AF),
            ),
            const _RadicalListRow(
              title: 'Completed',
              count: '24',
              marker: _rMuted,
              isLast: true,
            ),
            const SizedBox(height: 27),
            const _RadicalSectionTitle(label: 'YOUR LISTS', trailing: ''),
            const SizedBox(height: 3),
            const _RadicalListRow(
              title: 'Design',
              subtitle: 'Updated today',
              count: '7',
              marker: _rGreen,
            ),
            const _RadicalListRow(
              title: 'Work',
              subtitle: 'Launch and operations',
              count: '9',
              marker: Color(0xFFC98257),
            ),
            const _RadicalListRow(
              title: 'Personal',
              subtitle: 'Home and errands',
              count: '6',
              marker: Color(0xFF6F92A9),
            ),
            const _RadicalListRow(
              title: 'Learning',
              subtitle: 'Reading and courses',
              count: '3',
              marker: Color(0xFF927DAC),
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalListRow extends StatelessWidget {
  const _RadicalListRow({
    required this.title,
    required this.count,
    required this.marker,
    this.subtitle,
    this.isLast = false,
  });

  final String title;
  final String count;
  final Color marker;
  final String? subtitle;
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
        height: subtitle == null ? 55 : 64,
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: marker,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const SizedBox(width: 3, height: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontFamily: _directionSans,
                        color: _rMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              count,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 8),
            const Text('→', style: TextStyle(color: _rMuted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _RadicalCreateMock extends StatelessWidget {
  const _RadicalCreateMock();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const IgnorePointer(child: _RadicalHomeMock()),
        Positioned.fill(
          child: ColoredBox(color: _rInk.withValues(alpha: 0.28)),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: _RadicalComposer(),
        ),
      ],
    );
  }
}

class _RadicalComposer extends StatelessWidget {
  const _RadicalComposer({this.onSubmit});

  final VoidCallback? onSubmit;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: SizedBox(
                  width: 32,
                  child: Divider(color: _rRule, thickness: 3),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'What needs doing?',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rInk,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Add a note',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 20),
              const Divider(color: _rRule, height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const _RadicalComposerAction(label: 'Inbox'),
                  const _RadicalComposerAction(label: 'Today', isActive: true),
                  const _RadicalComposerAction(label: 'Any time'),
                  const Spacer(),
                  SizedBox.square(
                    dimension: 42,
                    child: Material(
                      color: _rGreen,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: onSubmit ?? () {},
                        customBorder: const CircleBorder(),
                        child: const Icon(
                          LucideIcons.arrowUp300,
                          color: _rNightText,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadicalComposerAction extends StatelessWidget {
  const _RadicalComposerAction({required this.label, this.isActive = false});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: _directionSans,
            color: isActive ? _rGreen : _rMuted,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _RadicalSearchMock extends StatelessWidget {
  const _RadicalSearchMock({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          children: [
            _RadicalSearchLine(onBack: onBack),
            const SizedBox(height: 29),
            const _RadicalSectionTitle(label: 'RECENT', trailing: 'Clear'),
            const SizedBox(height: 3),
            const _RadicalSearchResult(
              title: 'Prepare launch notes',
              subtitle: 'Today · Design',
            ),
            const _RadicalSearchResult(
              title: 'Design',
              subtitle: 'List · 7 open tasks',
            ),
            const _RadicalSearchResult(
              title: 'Draft restore flow',
              subtitle: 'Tomorrow · Product',
              isLast: true,
            ),
            const SizedBox(height: 30),
            const _RadicalSectionTitle(label: 'FILTER', trailing: ''),
            const SizedBox(height: 3),
            const _RadicalFilterRow(title: 'Due this week', count: '8'),
            const _RadicalFilterRow(title: 'Ready to focus', count: '4'),
            const _RadicalFilterRow(
              title: 'Recently completed',
              count: '12',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalSearchLine extends StatelessWidget {
  const _RadicalSearchLine({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _rInk, width: 1)),
      ),
      child: SizedBox(
        height: 55,
        child: Row(
          children: [
            IconButton(
              onPressed: onBack ?? () {},
              icon: const Icon(LucideIcons.arrowLeft300, size: 20),
              color: _rInk,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(44),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
            ),
            const Icon(LucideIcons.search300, size: 18, color: _rMuted),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Search tasks, lists, notes',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(LucideIcons.slidersHorizontal300, size: 18),
              color: _rInk,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(44),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerRight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalSearchResult extends StatelessWidget {
  const _RadicalSearchResult({
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final String title;
  final String subtitle;
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
        height: 66,
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              child: Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _rGreen,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 5),
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _rMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Text('→', style: TextStyle(color: _rMuted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _RadicalFilterRow extends StatelessWidget {
  const _RadicalFilterRow({
    required this.title,
    required this.count,
    this.isLast = false,
  });

  final String title;
  final String count;
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
        height: 53,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _rInk,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              count,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            const Text('→', style: TextStyle(color: _rMuted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _RadicalAccountMock extends StatelessWidget {
  const _RadicalAccountMock({this.onSearch, this.onNavSelected, this.onAdd});

  final VoidCallback? onSearch;
  final ValueChanged<int>? onNavSelected;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      bottomNavigationBar: _RadicalNav(
        selectedIndex: 4,
        onSelected: onNavSelected,
        onAdd: onAdd,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 15, 24, 76),
          children: [
            _RadicalBrandBar(onSearch: onSearch),
            const SizedBox(height: 22),
            const _RadicalSimpleHeading(title: 'You', trailing: ''),
            const SizedBox(height: 23),
            const _RadicalIdentity(),
            const SizedBox(height: 31),
            const _RadicalSectionTitle(
              label: 'PRIVATE SYNC',
              trailing: 'Sync now',
            ),
            const SizedBox(height: 3),
            const _RadicalSettingRow(
              title: 'Up to date',
              detail: 'Last synced 2 minutes ago',
            ),
            const _RadicalSettingRow(
              title: 'End-to-end encrypted',
              detail: 'Keys stay on your devices',
              isLast: true,
            ),
            const SizedBox(height: 29),
            const _RadicalSectionTitle(label: 'PREFERENCES', trailing: ''),
            const SizedBox(height: 3),
            const _RadicalSettingRow(
              title: 'Notifications',
              detail: 'Planning at 9:00',
            ),
            const _RadicalSettingRow(
              title: 'Focus',
              detail: '25 minute default',
            ),
            const _RadicalSettingRow(title: 'Appearance', detail: 'Warm light'),
            const _RadicalSettingRow(
              title: 'Language',
              detail: 'English',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalIdentity extends StatelessWidget {
  const _RadicalIdentity();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: _rGreen, width: 1),
              ),
            ),
            child: Center(
              child: Text(
                'Y',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rGreen,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
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
                  color: _rInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'youhei@example.com',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const Text('→', style: TextStyle(color: _rMuted, fontSize: 15)),
      ],
    );
  }
}

class _RadicalSettingRow extends StatelessWidget {
  const _RadicalSettingRow({
    required this.title,
    required this.detail,
    this.isLast = false,
  });

  final String title;
  final String detail;
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
        height: 61,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _rInk,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _rMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Text('→', style: TextStyle(color: _rMuted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _RadicalFocusSetupMock extends StatelessWidget {
  const _RadicalFocusSetupMock({
    this.onClose,
    this.onBegin,
    this.durationMinutes = 25,
    this.onDecrease,
    this.onIncrease,
    this.onPresetSelected,
  });

  final VoidCallback? onClose;
  final VoidCallback? onBegin;
  final int durationMinutes;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final ValueChanged<int>? onPresetSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 23),
          child: Column(
            children: [
              _RadicalFocusBar(label: 'SET FOCUS', onClose: onClose),
              const SizedBox(height: 36),
              const Text(
                'Prepare launch notes',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 74),
              _RadicalDurationControl(
                durationMinutes: durationMinutes,
                onDecrease: onDecrease,
                onIncrease: onIncrease,
              ),
              const SizedBox(height: 44),
              _RadicalPresetLine(
                durationMinutes: durationMinutes,
                onSelected: onPresetSelected,
              ),
              const SizedBox(height: 42),
              const _RadicalModeLine(),
              const Spacer(),
              _RadicalBeginButton(onPressed: onBegin),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadicalDurationControl extends StatelessWidget {
  const _RadicalDurationControl({
    required this.durationMinutes,
    this.onDecrease,
    this.onIncrease,
  });

  final int durationMinutes;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onDecrease ?? () {},
          icon: const Icon(LucideIcons.minus300, size: 20),
          color: _rMuted,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(48),
            side: const BorderSide(color: _rRule),
            shape: const CircleBorder(),
          ),
        ),
        const SizedBox(width: 29),
        Column(
          children: [
            Text(
              '$durationMinutes',
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rInk,
                fontSize: 70,
                fontWeight: FontWeight.w300,
                height: 0.92,
                letterSpacing: -3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'MINUTES',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(width: 29),
        IconButton(
          onPressed: onIncrease ?? () {},
          icon: const Icon(LucideIcons.plus300, size: 20),
          color: _rGreen,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(48),
            side: const BorderSide(color: _rGreen),
            shape: const CircleBorder(),
          ),
        ),
      ],
    );
  }
}

class _RadicalPresetLine extends StatelessWidget {
  const _RadicalPresetLine({required this.durationMinutes, this.onSelected});

  final int durationMinutes;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final minutes in const [15, 25, 45, 60])
          _RadicalPreset(
            label: '$minutes',
            active: durationMinutes == minutes,
            onTap: () => onSelected?.call(minutes),
          ),
      ],
    );
  }
}

class _RadicalPreset extends StatelessWidget {
  const _RadicalPreset({required this.label, this.active = false, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 54,
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: _directionSans,
                color: active ? _rGreen : _rMuted,
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              width: 16,
              child: Divider(
                color: active ? _rGreen : Colors.transparent,
                height: 1,
                thickness: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalModeLine extends StatelessWidget {
  const _RadicalModeLine();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _rRule, width: 0.65),
          bottom: BorderSide(color: _rRule, width: 0.65),
        ),
      ),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Text(
              'Mode',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 12.5,
              ),
            ),
            Spacer(),
            Text(
              'Timer',
              style: TextStyle(
                fontFamily: _directionSans,
                color: _rInk,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 8),
            Text('→', style: TextStyle(color: _rMuted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _RadicalBeginButton extends StatelessWidget {
  const _RadicalBeginButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: onPressed ?? () {},
        style: FilledButton.styleFrom(
          backgroundColor: _rGreen,
          foregroundColor: _rNightText,
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
            fontFamily: _directionSans,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: const Text('Begin focus  →'),
      ),
    );
  }
}

class _RadicalFocusMock extends StatelessWidget {
  const _RadicalFocusMock({
    this.onClose,
    this.onPause,
    this.onFinish,
    this.remainingSeconds = 1500,
    this.progress = 0.67,
    this.isPaused = false,
  });

  final VoidCallback? onClose;
  final VoidCallback? onPause;
  final VoidCallback? onFinish;
  final int remainingSeconds;
  final double progress;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rNight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              _RadicalFocusBar(
                label: 'FOCUS  ·  1 OF 4',
                inverse: true,
                onClose: onClose,
              ),
              const SizedBox(height: 39),
              const Text(
                'Prepare launch notes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rNightText,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(flex: 2),
              Text(
                _formatFocusTime(remainingSeconds),
                style: const TextStyle(
                  fontFamily: _directionSans,
                  color: _rNightText,
                  fontSize: 78,
                  fontWeight: FontWeight.w300,
                  height: 0.95,
                  letterSpacing: -4,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'until 10:05',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rNightMuted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 48),
              _RadicalHorizon(progress: progress),
              const Spacer(flex: 3),
              _RadicalFocusActions(
                onPause: onPause,
                onFinish: onFinish,
                isPaused: isPaused,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatFocusTime(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

class _RadicalHorizon extends StatelessWidget {
  const _RadicalHorizon({this.progress = 0.67});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final activeWidth = width * progress.clamp(0.0, 1.0);
        final birdLeft = (activeWidth - 25).clamp(0.0, width - 44);
        return SizedBox(
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                left: 0,
                right: 0,
                top: 22,
                child: Divider(color: Color(0xFF4F7162), height: 1),
              ),
              Positioned(
                left: 0,
                top: 21,
                child: Container(width: activeWidth, height: 2, color: _rSage),
              ),
              Positioned(
                left: birdLeft,
                top: -13,
                child: const Column(
                  children: [
                    _RadicalFlyingTsugumidori(),
                    SizedBox(height: 2),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _rSage,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(dimension: 5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RadicalFlyingTsugumidori extends StatelessWidget {
  const _RadicalFlyingTsugumidori();

  static const _asset =
      'assets/brand/generated/todori-mascot-ui-sprites-v1.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      width: 44,
      height: 42,
      fit: BoxFit.cover,
      alignment: Alignment.centerLeft,
    );
  }
}

class _RadicalFocusActions extends StatelessWidget {
  const _RadicalFocusActions({
    this.onPause,
    this.onFinish,
    this.isPaused = false,
  });

  final VoidCallback? onPause;
  final VoidCallback? onFinish;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: onPause ?? () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: _rNightText,
                side: const BorderSide(color: _rSage, width: 0.8),
                shape: const RoundedRectangleBorder(),
                textStyle: const TextStyle(
                  fontFamily: _directionSans,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(isPaused ? 'Resume' : 'Pause'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextButton(
            onPressed: onFinish ?? () {},
            style: TextButton.styleFrom(
              foregroundColor: _rNightMuted,
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(
                fontFamily: _directionSans,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: const Text('Finish'),
          ),
        ),
      ],
    );
  }
}

class _RadicalFocusBar extends StatelessWidget {
  const _RadicalFocusBar({
    required this.label,
    this.inverse = false,
    this.onClose,
  });

  final String label;
  final bool inverse;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final color = inverse ? _rNightText : _rInk;
    final muted = inverse ? _rNightMuted : _rMuted;
    return Row(
      children: [
        IconButton(
          onPressed: onClose ?? () {},
          icon: const Icon(LucideIcons.x300, size: 21),
          color: color,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _directionSans,
              color: muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.45,
            ),
          ),
        ),
        const SizedBox(width: 44),
      ],
    );
  }
}

class _RadicalNav extends StatelessWidget {
  const _RadicalNav({required this.selectedIndex, this.onSelected, this.onAdd});

  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    const items = [
      (LucideIcons.house300, 'Today'),
      (LucideIcons.calendarDays300, 'Calendar'),
      (LucideIcons.plus300, ''),
      (LucideIcons.listTodo300, 'Lists'),
      (LucideIcons.circleUserRound300, 'You'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _rCanvas,
        border: Border(top: BorderSide(color: _rRule, width: 0.65)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index += 1)
                Expanded(
                  child: index == 2
                      ? _RadicalNavAdd(onTap: onAdd)
                      : _RadicalNavLabel(
                          icon: items[index].$1,
                          label: items[index].$2,
                          isSelected: selectedIndex == index,
                          onTap: () => onSelected?.call(index),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadicalNavLabel extends StatelessWidget {
  const _RadicalNavLabel({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: isSelected ? _rGreen : _rMuted),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: _directionSans,
              color: isSelected ? _rInk : _rMuted,
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 14,
            child: Divider(
              color: isSelected ? _rGreen : Colors.transparent,
              height: 1,
              thickness: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RadicalNavAdd extends StatelessWidget {
  const _RadicalNavAdd({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 42,
        child: Material(
          color: _rGreen,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: const Icon(
              LucideIcons.plus300,
              size: 19,
              color: _rNightText,
            ),
          ),
        ),
      ),
    );
  }
}

class _RadicalSimpleHeading extends StatelessWidget {
  const _RadicalSimpleHeading({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: _directionSans,
              color: _rInk,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.8,
            ),
          ),
        ),
        if (trailing.isNotEmpty)
          Text(
            trailing,
            style: const TextStyle(
              fontFamily: _directionSans,
              color: _rGreen,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _RadicalSectionTitle extends StatelessWidget {
  const _RadicalSectionTitle({required this.label, required this.trailing});

  final String label;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
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
        ),
        if (trailing.isNotEmpty)
          Text(
            trailing,
            style: const TextStyle(
              fontFamily: _directionSans,
              color: _rMuted,
              fontSize: 10.5,
            ),
          ),
      ],
    );
  }
}

class _RadicalCheck extends StatelessWidget {
  const _RadicalCheck({this.isDone = false, this.size = 20});

  final bool isDone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDone ? _rGreen : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: _rGreen, width: 1),
      ),
      child: SizedBox.square(
        dimension: size,
        child: isDone
            ? Icon(LucideIcons.check300, size: size * 0.55, color: _rNightText)
            : null,
      ),
    );
  }
}
