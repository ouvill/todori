part of 'design_lab_mocks.dart';

class InteractiveDesignLabApp extends StatelessWidget {
  const InteractiveDesignLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Todori Design Lab',
      theme: buildTodoriTheme(Brightness.light),
      home: const _InteractiveDesignLabShell(),
    );
  }
}

class _InteractiveDesignLabShell extends StatefulWidget {
  const _InteractiveDesignLabShell();

  @override
  State<_InteractiveDesignLabShell> createState() =>
      _InteractiveDesignLabShellState();
}

class _InteractiveDesignLabShellState
    extends State<_InteractiveDesignLabShell> {
  var _selectedIndex = 0;
  var _showTodayCompleted = false;
  final _completedTaskTitles = <String>{};
  final _retiredTaskTitles = <String>{};

  @override
  Widget build(BuildContext context) {
    return switch (_selectedIndex) {
      0 => _RadicalHomeMock(
        onSearch: _openSearch,
        onTaskTap: _openTaskDetail,
        onTaskFocus: () => _openFocusSetup(context),
        onNavSelected: _selectTab,
        onAdd: _openComposer,
        completedTaskTitles: _completedTaskTitles,
        hiddenTaskTitles: _retiredTaskTitles,
        onTaskToggle: _toggleTask,
        showCompleted: _showTodayCompleted,
        onCompletedTap: () {
          setState(() => _showTodayCompleted = !_showTodayCompleted);
        },
      ),
      1 => _InteractiveCalendarMock(
        onNavSelected: _selectTab,
        onAdd: _openComposer,
        onTaskTap: _openTaskDetail,
        onTaskFocus: () => _openFocusSetup(context),
        completedTaskTitles: _completedTaskTitles,
        onTaskToggle: _toggleTask,
      ),
      3 => _RadicalListsMock(
        onSearch: _openSearch,
        onNavSelected: _selectTab,
        onAdd: _openComposer,
        onListTap: _openListTasks,
      ),
      4 => _RadicalAccountMock(
        onSearch: _openSearch,
        onNavSelected: _selectTab,
        onAdd: _openComposer,
        onAccountTap: _openAccountAccess,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  void _selectTab(int index) {
    if (index == 2 || index == _selectedIndex) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _toggleTask(String title) {
    final completed = !_completedTaskTitles.contains(title);
    setState(() {
      if (completed) {
        _completedTaskTitles.add(title);
      } else {
        _completedTaskTitles.remove(title);
        _retiredTaskTitles.remove(title);
      }
    });
    if (completed) {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _completedTaskTitles.contains(title)) {
          setState(() => _retiredTaskTitles.add(title));
        }
      });
    }
  }

  void _openSearch() {
    _pushLabRoute(
      context,
      builder: (routeContext) =>
          _RadicalSearchMock(onBack: () => Navigator.of(routeContext).pop()),
    );
  }

  void _openTaskDetail() {
    _pushLabRoute(
      context,
      builder: (routeContext) => _RadicalDetailMock(
        onBack: () => Navigator.of(routeContext).pop(),
        onBeginFocus: () => _openFocusSetup(routeContext),
        onEdit: () => _openTaskEdit(routeContext),
        onActions: () => _openTaskActions(routeContext),
      ),
    );
  }

  void _openListTasks() {
    _pushLabRoute(
      context,
      builder: (routeContext) => _RadicalListTasksMock(
        onBack: () => Navigator.of(routeContext).pop(),
        onTaskTap: () => _openTaskDetailFrom(routeContext),
        onTaskFocus: () => _openFocusSetup(routeContext),
        onActions: () => _openTaskActions(routeContext),
        onDueDate: () => _openDueDate(routeContext),
        onAdd: () => _openComposerFrom(routeContext),
      ),
    );
  }

  void _openTaskDetailFrom(BuildContext parentContext) {
    _pushLabRoute(
      parentContext,
      builder: (routeContext) => _RadicalDetailMock(
        onBack: () => Navigator.of(routeContext).pop(),
        onBeginFocus: () => _openFocusSetup(routeContext),
        onEdit: () => _openTaskEdit(routeContext),
        onActions: () => _openTaskActions(routeContext),
      ),
    );
  }

  void _openTaskEdit(BuildContext parentContext) {
    _pushLabRoute(
      parentContext,
      builder: (routeContext) => _RadicalTaskEditMock(
        onClose: () => Navigator.of(routeContext).pop(),
        onSave: () => Navigator.of(routeContext).pop(),
      ),
    );
  }

  Future<void> _openTaskActions(BuildContext parentContext) {
    return showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: Colors.transparent,
      barrierColor: _rInk.withValues(alpha: 0.3),
      isScrollControlled: true,
      builder: (sheetContext) => _RadicalActionSheetContent(
        onDueDate: () {
          Navigator.of(sheetContext).pop();
          _openDueDate(parentContext);
        },
      ),
    );
  }

  Future<void> _openDueDate(BuildContext parentContext) {
    return showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: Colors.transparent,
      barrierColor: _rInk.withValues(alpha: 0.3),
      isScrollControlled: true,
      builder: (sheetContext) => const _RadicalDueDateSheetContent(),
    );
  }

  void _openAccountAccess() {
    _pushLabRoute(
      context,
      builder: (routeContext) => _InteractiveAccountAccess(
        onBack: () => Navigator.of(routeContext).pop(),
        onSubmit: () => Navigator.of(routeContext).pop(),
      ),
    );
  }

  void _openFocusSetup(BuildContext parentContext) {
    _pushLabRoute(
      parentContext,
      builder: (routeContext) => _InteractiveFocusSetup(
        onClose: () => Navigator.of(routeContext).pop(),
        onBegin: (durationMinutes) {
          Navigator.of(routeContext).pushReplacement(
            _labRoute(
              routeContext,
              builder: (focusContext) => _InteractiveFocusTimer(
                onClose: () => Navigator.of(focusContext).pop(),
                onFinish: () => Navigator.of(focusContext).pop(),
                durationMinutes: durationMinutes,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openComposer() {
    return _openComposerFrom(context);
  }

  Future<void> _openComposerFrom(BuildContext parentContext) {
    return showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: Colors.transparent,
      barrierColor: _rInk.withValues(alpha: 0.3),
      isScrollControlled: true,
      builder: (sheetContext) =>
          _RadicalComposer(onSubmit: () => Navigator.of(sheetContext).pop()),
    );
  }
}

class _InteractiveAccountAccess extends StatefulWidget {
  const _InteractiveAccountAccess({
    required this.onBack,
    required this.onSubmit,
  });

  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  State<_InteractiveAccountAccess> createState() =>
      _InteractiveAccountAccessState();
}

class _InteractiveAccountAccessState extends State<_InteractiveAccountAccess> {
  var _registerMode = false;

  @override
  Widget build(BuildContext context) {
    return _RadicalAccountAccessMock(
      registerMode: _registerMode,
      onBack: widget.onBack,
      onSubmit: widget.onSubmit,
      onModeChanged: (registerMode) {
        setState(() => _registerMode = registerMode);
      },
    );
  }
}

class _InteractiveCalendarMock extends StatefulWidget {
  const _InteractiveCalendarMock({
    this.onNavSelected,
    this.onAdd,
    this.onTaskTap,
    this.onTaskFocus,
    this.completedTaskTitles = const <String>{},
    this.onTaskToggle,
  });

  final ValueChanged<int>? onNavSelected;
  final VoidCallback? onAdd;
  final VoidCallback? onTaskTap;
  final VoidCallback? onTaskFocus;
  final Set<String> completedTaskTitles;
  final ValueChanged<String>? onTaskToggle;

  @override
  State<_InteractiveCalendarMock> createState() =>
      _InteractiveCalendarMockState();
}

class _InteractiveCalendarMockState extends State<_InteractiveCalendarMock> {
  var _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rCanvas,
      bottomNavigationBar: _RadicalNav(
        selectedIndex: 1,
        onSelected: widget.onNavSelected,
        onAdd: widget.onAdd,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 76),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalSimpleHeading(
                title: 'Calendar',
                trailing: 'May 2026',
              ),
            ),
            const SizedBox(height: 27),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _InteractiveWeekStrip(),
            ),
            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalSectionTitle(
                label: 'TUESDAY 27',
                trailing: '4 tasks',
              ),
            ),
            const SizedBox(height: 5),
            _RadicalTaskRow(
              title: 'Prepare launch notes',
              meta: 'Design · 25 minutes',
              time: '9:00',
              priority: 3,
              onTap: widget.onTaskTap,
              onFocus: widget.onTaskFocus,
              isDone: widget.completedTaskTitles.contains(
                'Prepare launch notes',
              ),
              onToggle: () => widget.onTaskToggle?.call('Prepare launch notes'),
            ),
            _RadicalTaskRow(
              title: 'Review onboarding copy',
              meta: 'Product',
              time: '9:30',
              priority: 2,
              isDone: widget.completedTaskTitles.contains(
                'Review onboarding copy',
              ),
              onToggle: () =>
                  widget.onTaskToggle?.call('Review onboarding copy'),
            ),
            _RadicalTaskRow(
              title: 'Finalize navigation states',
              meta: 'Design',
              time: '11:00',
              priority: 1,
              isDone: widget.completedTaskTitles.contains(
                'Finalize navigation states',
              ),
              onToggle: () =>
                  widget.onTaskToggle?.call('Finalize navigation states'),
              children: const [
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
              isLast: true,
              isDone: widget.completedTaskTitles.contains('Send release build'),
              onToggle: () => widget.onTaskToggle?.call('Send release build'),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _RadicalCompletedDisclosure(
                isExpanded: _showCompleted,
                countLabel:
                    '${3 + widget.completedTaskTitles.length} this week',
                onTap: () {
                  setState(() => _showCompleted = !_showCompleted);
                },
              ),
            ),
            if (_showCompleted) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: _RadicalCompletedRow(
                  title: 'Approved release direction',
                  detail: 'Today · Design',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _RadicalCompletedRow(
                  title: 'Shared weekly plan',
                  detail: 'Yesterday · Work',
                  isLast: widget.completedTaskTitles.isEmpty,
                ),
              ),
              for (
                var index = 0;
                index < widget.completedTaskTitles.length;
                index += 1
              )
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _RadicalCompletedRow(
                    title: widget.completedTaskTitles.elementAt(index),
                    detail: 'Today · Completed',
                    isLast: index == widget.completedTaskTitles.length - 1,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RadicalCompletedDisclosure extends StatelessWidget {
  const _RadicalCompletedDisclosure({
    required this.isExpanded,
    required this.countLabel,
    required this.onTap,
  });

  final bool isExpanded;
  final String countLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const Icon(LucideIcons.circleCheck300, size: 16, color: _rMuted),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Completed',
                style: TextStyle(
                  fontFamily: _directionSans,
                  color: _rMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              countLabel,
              style: const TextStyle(
                fontFamily: _directionSans,
                color: _rMuted,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: const Icon(
                LucideIcons.chevronDown300,
                size: 15,
                color: _rMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadicalCompletedRow extends StatelessWidget {
  const _RadicalCompletedRow({
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 11, 0, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(LucideIcons.check300, size: 13, color: _rGreen),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _rInk,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontFamily: _directionSans,
                      color: _rMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveWeekStrip extends StatelessWidget {
  const _InteractiveWeekStrip();

  @override
  Widget build(BuildContext context) {
    const days = [
      ('M', '26'),
      ('T', '27'),
      ('W', '28'),
      ('T', '29'),
      ('F', '30'),
    ];
    return Row(
      children: [
        for (var index = 0; index < days.length; index += 1)
          Expanded(
            child: Column(
              children: [
                Text(
                  days[index].$1,
                  style: const TextStyle(
                    fontFamily: _directionSans,
                    color: _rMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  days[index].$2,
                  style: TextStyle(
                    fontFamily: _directionSans,
                    color: index == 1 ? _rGreen : _rInk,
                    fontSize: 15,
                    fontWeight: index == 1 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 14,
                  child: Divider(
                    color: index == 1 ? _rGreen : Colors.transparent,
                    thickness: 2,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InteractiveFocusSetup extends StatefulWidget {
  const _InteractiveFocusSetup({required this.onClose, required this.onBegin});

  final VoidCallback onClose;
  final ValueChanged<int> onBegin;

  @override
  State<_InteractiveFocusSetup> createState() => _InteractiveFocusSetupState();
}

class _InteractiveFocusSetupState extends State<_InteractiveFocusSetup> {
  var _durationMinutes = 25;

  @override
  Widget build(BuildContext context) {
    return _RadicalFocusSetupMock(
      onClose: widget.onClose,
      onBegin: () => widget.onBegin(_durationMinutes),
      durationMinutes: _durationMinutes,
      onDecrease: () => _changeDuration(-5),
      onIncrease: () => _changeDuration(5),
      onPresetSelected: (minutes) {
        setState(() => _durationMinutes = minutes);
      },
    );
  }

  void _changeDuration(int delta) {
    setState(() {
      _durationMinutes = (_durationMinutes + delta).clamp(5, 120);
    });
  }
}

class _InteractiveFocusTimer extends StatefulWidget {
  const _InteractiveFocusTimer({
    required this.onClose,
    required this.onFinish,
    required this.durationMinutes,
  });

  final VoidCallback onClose;
  final VoidCallback onFinish;
  final int durationMinutes;

  @override
  State<_InteractiveFocusTimer> createState() => _InteractiveFocusTimerState();
}

class _InteractiveFocusTimerState extends State<_InteractiveFocusTimer> {
  Timer? _timer;
  late final int _totalSeconds;
  late int _remainingSeconds;
  var _isPaused = false;

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.durationMinutes * 60;
    _remainingSeconds = _totalSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick(Timer timer) {
    if (_isPaused || _remainingSeconds == 0) {
      return;
    }
    setState(() => _remainingSeconds -= 1);
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _totalSeconds - _remainingSeconds;
    return _RadicalFocusMock(
      onClose: widget.onClose,
      onPause: _togglePause,
      onFinish: widget.onFinish,
      remainingSeconds: _remainingSeconds,
      progress: elapsed / _totalSeconds,
      isPaused: _isPaused,
    );
  }
}

Future<T?> _pushLabRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return Navigator.of(context).push(_labRoute(context, builder: builder));
}

PageRoute<T> _labRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280),
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) {
        return child;
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.025, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
