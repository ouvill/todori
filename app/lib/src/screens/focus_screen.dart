import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:taskveil/src/core/providers.dart';
import 'package:taskveil/src/generated/l10n/app_localizations.dart';
import 'package:taskveil/src/rust/api.dart';
import 'package:taskveil/src/timer/timer_engine.dart';
import 'package:taskveil/src/timer/timer_settings.dart';
import 'package:taskveil/src/ui/dialogs.dart';
import 'package:taskveil/src/ui/states.dart';
import 'package:taskveil/src/ui/task_components.dart';
import 'package:taskveil/src/ui/theme.dart';

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key, required this.listId, required this.taskId});

  final String listId;
  final String taskId;

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  TimerModeDto _selectedMode = TimerModeDto.pomodoro;
  bool _busy = false;
  bool _breakFinished = false;
  bool _taskCompleted = false;
  bool _sessionFinished = false;
  bool _activeConflict = false;

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider(widget.listId));
    final engineAsync = ref.watch(timerEngineProvider);
    final settingsAsync = ref.watch(timerSettingsProvider);
    final engine = engineAsync.value;
    final active = engine?.active;
    final hasFinishedState =
        engine?.lastCompletion?.taskId == widget.taskId ||
        engine?.isBreakPending == true ||
        engine?.breakJustCompleted == true ||
        _breakFinished ||
        _taskCompleted ||
        _sessionFinished;

    return PopScope<void>(
      canPop: active == null && !hasFinishedState,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        if (active != null) {
          unawaited(_requestExit());
        } else if (hasFinishedState) {
          unawaited(
            _finishPromptAndExit(
              acknowledgeBreak: engine?.isBreakPending == true,
            ),
          );
        }
      },
      child: Scaffold(
        key: const ValueKey('focus-screen'),
        backgroundColor: AppColors.canvas,
        body: ColoredBox(
          color: AppColors.canvas,
          child: SafeArea(
            child: _FocusStateTransition(
              child: tasksAsync.when(
                loading: () => _FocusCenteredState(
                  child: Semantics(
                    label: _l10n.focusRestoring,
                    liveRegion: true,
                    child: const AppLoadingState(),
                  ),
                ),
                error: (error, stackTrace) => _FocusErrorState(
                  onRetry: () => ref.invalidate(tasksProvider(widget.listId)),
                  onExit: _leaveFocus,
                ),
                data: (tasks) {
                  final task = tasks
                      .where((item) => item.id == widget.taskId)
                      .firstOrNull;
                  if (task == null) {
                    return _FocusErrorState(
                      onRetry: () =>
                          ref.invalidate(tasksProvider(widget.listId)),
                      onExit: _leaveFocus,
                    );
                  }
                  return engineAsync.when(
                    loading: () => _FocusCenteredState(
                      child: Semantics(
                        label: _l10n.focusRestoring,
                        liveRegion: true,
                        child: const AppLoadingState(),
                      ),
                    ),
                    error: (error, stackTrace) => _FocusErrorState(
                      onRetry: () => ref.invalidate(timerEngineProvider),
                      onExit: _leaveFocus,
                    ),
                    data: (engine) {
                      final belongsToTask =
                          engine.active?.taskId == null ||
                          engine.active?.taskId == task.id;
                      if (_activeConflict || !belongsToTask) {
                        return _FocusConflictState(onBack: _leaveFocus);
                      }
                      if (engine.active != null) {
                        return _FocusActiveView(
                          task: task,
                          engine: engine,
                          busy: _busy,
                          onClose: () => _showSessionOptions(task),
                          onPause: () => _runEngine(
                            () =>
                                ref.read(timerEngineProvider.notifier).pause(),
                          ),
                          onResume: () => _runEngine(
                            () =>
                                ref.read(timerEngineProvider.notifier).resume(),
                          ),
                          onOptions: () => _showSessionOptions(task),
                        );
                      }
                      if (_breakFinished || engine.breakJustCompleted) {
                        return _FocusFinishedView(
                          title: _l10n.focusBreakFinishedTitle,
                          body: _l10n.focusBreakFinishedBody,
                          onDone: () => unawaited(
                            _finishPromptAndExit(acknowledgeBreak: false),
                          ),
                        );
                      }
                      final completion =
                          engine.lastCompletion?.taskId == task.id
                          ? engine.lastCompletion
                          : null;
                      if (completion != null ||
                          _taskCompleted ||
                          _sessionFinished ||
                          engine.isBreakPending) {
                        final recordedDuration = completion == null
                            ? null
                            : Duration(
                                milliseconds: completion.activeDurationMs
                                    .toInt(),
                              );
                        return _FocusFinishedView(
                          title: _l10n.focusFinishedTitle,
                          body: completion == null
                              ? engine.isBreakPending
                                    ? _l10n.focusBreakPrompt
                                    : _l10n.undoCompleteMessage
                              : _l10n.focusFinishedSummary,
                          recordedTime: recordedDuration == null
                              ? null
                              : _formatDuration(recordedDuration),
                          onStartBreak: engine.isBreakPending
                              ? () => _runEngine(
                                  () => ref
                                      .read(timerEngineProvider.notifier)
                                      .startBreak(),
                                )
                              : null,
                          onDone: () => unawaited(
                            _finishPromptAndExit(
                              acknowledgeBreak: engine.isBreakPending,
                            ),
                          ),
                        );
                      }
                      return settingsAsync.when(
                        loading: () => _FocusCenteredState(
                          child: Semantics(
                            label: _l10n.focusRestoring,
                            liveRegion: true,
                            child: const AppLoadingState(),
                          ),
                        ),
                        error: (error, stackTrace) => _FocusErrorState(
                          onRetry: () => ref.invalidate(timerSettingsProvider),
                          onExit: _leaveFocus,
                        ),
                        data: (settings) => _FocusSetupView(
                          task: task,
                          settings: settings,
                          selectedMode: _selectedMode,
                          busy: _busy,
                          onModeChanged: (mode) =>
                              setState(() => _selectedMode = mode),
                          onStart: () => _start(task),
                          onSettings: () => _showSettings(settings),
                          onClose: _leaveFocus,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  Future<void> _finishPromptAndExit({required bool acknowledgeBreak}) async {
    if (acknowledgeBreak) {
      final succeeded = await _runEngine(
        () => ref.read(timerEngineProvider.notifier).skipBreak(),
      );
      if (!succeeded || !mounted) {
        return;
      }
    }
    ref.read(timerEngineProvider.notifier).clearLastOutcome();
    _leaveFocus();
  }

  void _leaveFocus() {
    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _start(TaskDto task) async {
    await _runEngine(() async {
      final controller = ref.read(timerEngineProvider.notifier);
      if (_selectedMode == TimerModeDto.pomodoro) {
        await controller.startPomodoro(taskId: task.id);
      } else {
        await controller.startStopwatch(taskId: task.id);
      }
      return null;
    });
  }

  Future<void> _finish(TimerFinishKindDto kind, {bool exit = false}) async {
    final active = ref.read(timerEngineProvider).value?.active;
    final wasBreak = active?.phase != TimerPhaseDto.work;
    CompletedTimerSessionDto? completion;
    final succeeded = await _runEngine(() async {
      completion = await ref
          .read(timerEngineProvider.notifier)
          .finish(kind: kind);
      return completion;
    });
    if (!succeeded || !mounted) {
      return;
    }
    final taskId = active?.taskId;
    if (taskId != null) {
      ref.invalidate(completedTimerSessionsProvider(taskId));
    }
    if (wasBreak) {
      setState(() => _breakFinished = true);
    } else if (completion != null) {
      setState(() => _sessionFinished = true);
    }
    if (exit) {
      ref.read(timerEngineProvider.notifier).clearLastOutcome();
      _leaveFocus();
    }
  }

  Future<void> _discard() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: _l10n.focusDiscardTitle,
      message: _l10n.focusDiscardBody,
      cancelLabel: _l10n.cancelButton,
      confirmLabel: _l10n.focusDiscardButton,
      isDestructive: true,
    );
    if (!confirmed) {
      return;
    }
    final succeeded = await _runEngine(
      () => ref.read(timerEngineProvider.notifier).discard(),
    );
    if (succeeded && mounted) {
      _leaveFocus();
    }
  }

  Future<void> _requestExit() async {
    final active = ref.read(timerEngineProvider).value?.active;
    if (active == null) {
      _leaveFocus();
      return;
    }
    final task = ref
        .read(tasksProvider(widget.listId))
        .value
        ?.where((item) => item.id == widget.taskId)
        .firstOrNull;
    await _showSessionOptions(task);
  }

  Future<void> _showSessionOptions(TaskDto? task) async {
    final active = ref.read(timerEngineProvider).value?.active;
    if (active == null) {
      _leaveFocus();
      return;
    }
    final action = await showModalBottomSheet<_FocusSessionAction>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      builder: (context) => _FocusSessionSheet(
        active: active,
        canCompleteTask: task != null && active.phase == TimerPhaseDto.work,
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _FocusSessionAction.addTime:
        await _runEngine(
          () => ref
              .read(timerEngineProvider.notifier)
              .addTime(const Duration(minutes: 5)),
        );
      case _FocusSessionAction.finish:
        await _finish(TimerFinishKindDto.completed);
      case _FocusSessionAction.completeTask:
        if (task != null) await _completeTask(task);
      case _FocusSessionAction.saveAndExit:
        await _finish(TimerFinishKindDto.interrupted, exit: true);
      case _FocusSessionAction.discard:
        await _discard();
    }
  }

  Future<void> _completeTask(TaskDto task) async {
    final completed = await _runEngine(
      () => ref
          .read(tasksProvider(task.listId).notifier)
          .setStatus(task.id, 'done'),
    );
    if (!completed || !mounted) {
      return;
    }
    if (ref.read(timerEngineProvider).value?.active != null) {
      return;
    }
    ref.invalidate(completedTimerSessionsProvider(task.id));
    setState(() => _taskCompleted = true);
    await _showUndo();
  }

  Future<void> _showUndo() async {
    ref.invalidate(latestTaskUndoProvider);
    final undo = await ref.read(latestTaskUndoProvider.future);
    if (!mounted || undo == null) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_l10n.undoCompleteMessage),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: _l10n.undoActionLabel,
          onPressed: () => unawaited(
            ref.read(latestTaskUndoProvider.notifier).undo(undo.id),
          ),
        ),
      ),
    );
  }

  Future<bool> _runEngine(Future<Object?> Function() operation) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await operation();
      return true;
    } on TimerActiveConflictException {
      if (mounted) setState(() => _activeConflict = true);
      return false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_l10n.focusActionFailed)));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSettings(TimerSettings initial) async {
    var draft = initial;
    final saved = await showModalBottomSheet<TimerSettings>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              _l10n.focusSettingsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            _TimerSettingDropdown(
              label: _l10n.focusWorkMinutesLabel,
              value: draft.workMinutes,
              values: [for (var value = 5; value <= 180; value += 5) value],
              onChanged: (value) => setSheetState(
                () => draft = _copySettings(draft, workMinutes: value),
              ),
            ),
            _TimerSettingDropdown(
              label: _l10n.focusShortBreakMinutesLabel,
              value: draft.shortBreakMinutes,
              values: [for (var value = 5; value <= 60; value += 5) value],
              onChanged: (value) => setSheetState(
                () => draft = _copySettings(draft, shortBreakMinutes: value),
              ),
            ),
            _TimerSettingDropdown(
              label: _l10n.focusLongBreakMinutesLabel,
              value: draft.longBreakMinutes,
              values: [for (var value = 5; value <= 120; value += 5) value],
              onChanged: (value) => setSheetState(
                () => draft = _copySettings(draft, longBreakMinutes: value),
              ),
            ),
            _TimerSettingDropdown(
              label: _l10n.focusLongBreakEveryLabel,
              value: draft.longBreakEvery,
              values: [for (var value = 2; value <= 12; value += 1) value],
              valueLabel: _l10n.focusWorkIntervals,
              onChanged: (value) => setSheetState(
                () => draft = _copySettings(draft, longBreakEvery: value),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(_l10n.focusNotificationsLabel),
              subtitle: Text(_l10n.focusNotificationsBody),
              value: draft.notificationsEnabled,
              onChanged: (value) => setSheetState(
                () => draft = _copySettings(draft, notificationsEnabled: value),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft),
              child: Text(_l10n.saveButton),
            ),
          ],
        ),
      ),
    );
    if (saved != null) {
      await _runEngine(
        () => ref.read(timerSettingsProvider.notifier).save(saved),
      );
    }
  }
}

class _FocusSetupView extends StatelessWidget {
  const _FocusSetupView({
    required this.task,
    required this.settings,
    required this.selectedMode,
    required this.busy,
    required this.onModeChanged,
    required this.onStart,
    required this.onSettings,
    required this.onClose,
  });

  final TaskDto task;
  final TimerSettings settings;
  final TimerModeDto selectedMode;
  final bool busy;
  final ValueChanged<TimerModeDto> onModeChanged;
  final VoidCallback onStart;
  final VoidCallback onSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final preview = selectedMode == TimerModeDto.pomodoro
        ? Duration(minutes: settings.workMinutes)
        : Duration.zero;
    final mediaSize = MediaQuery.sizeOf(context);
    final dialSize = mediaSize.height < 700
        ? 192.0
        : mediaSize.width < 350
        ? 220.0
        : 264.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          key: const ValueKey('focus-setup'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            4,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            _FocusHeader(onClose: onClose),
            const SizedBox(height: AppSpacing.lg),
            Text(
              task.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            _FocusModeSelector(
              selectedMode: selectedMode,
              enabled: !busy,
              onChanged: onModeChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: _FocusDial(
                diameter: dialSize,
                clock: _formatClock(preview),
                clockKey: const ValueKey('focus-preview-clock'),
                semanticsLabel: selectedMode == TimerModeDto.pomodoro
                    ? l10n.focusPomodoroSummary(
                        settings.workMinutes,
                        settings.shortBreakMinutes,
                      )
                    : l10n.focusStopwatchSummary,
                progress: selectedMode == TimerModeDto.pomodoro ? 1 : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              selectedMode == TimerModeDto.pomodoro
                  ? l10n.focusPomodoroSummary(
                      settings.workMinutes,
                      settings.shortBreakMinutes,
                    )
                  : l10n.focusStopwatchSummary,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            if (selectedMode == TimerModeDto.pomodoro)
              Center(
                child: TextButton.icon(
                  key: const ValueKey('focus-settings'),
                  onPressed: busy ? null : onSettings,
                  icon: const Icon(LucideIcons.slidersHorizontal300, size: 18),
                  label: Text(l10n.focusSettingsButton),
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(48, 44)),
                    foregroundColor: WidgetStatePropertyAll(AppColors.muted),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: SizedBox(
                width: 280,
                child: FilledButton(
                  key: const ValueKey('focus-start'),
                  onPressed: busy || isTaskClosed(task) ? null : onStart,
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size.fromHeight(52)),
                  ),
                  child: Text(l10n.focusStartButton),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusModeSelector extends StatelessWidget {
  const _FocusModeSelector({
    required this.selectedMode,
    required this.enabled,
    required this.onChanged,
  });

  final TimerModeDto selectedMode;
  final bool enabled;
  final ValueChanged<TimerModeDto> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      key: const ValueKey('focus-mode-selector'),
      alignment: WrapAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        _FocusModeTab(
          label: l10n.focusPomodoroMode,
          selected: selectedMode == TimerModeDto.pomodoro,
          onPressed: enabled ? () => onChanged(TimerModeDto.pomodoro) : null,
        ),
        _FocusModeTab(
          label: l10n.focusStopwatchMode,
          selected: selectedMode == TimerModeDto.stopwatch,
          onPressed: enabled ? () => onChanged(TimerModeDto.stopwatch) : null,
        ),
      ],
    );
  }
}

class _FocusModeTab extends StatelessWidget {
  const _FocusModeTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: TextButton(
        onPressed: onPressed,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(120, 48)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? AppColors.forest : AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              width: selected ? 28 : 0,
              height: 2,
              color: AppColors.forest,
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusActiveView extends StatelessWidget {
  const _FocusActiveView({
    required this.task,
    required this.engine,
    required this.busy,
    required this.onClose,
    required this.onPause,
    required this.onResume,
    required this.onOptions,
  });

  final TaskDto task;
  final TimerEngineState engine;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = engine.active!;
    final display = engine.remaining ?? engine.elapsed;
    final phaseLabel = switch (active.phase) {
      TimerPhaseDto.work => l10n.focusWorkPhase,
      TimerPhaseDto.shortBreak => l10n.focusShortBreakPhase,
      TimerPhaseDto.longBreak => l10n.focusLongBreakPhase,
    };
    final stateLabel = engine.isPaused
        ? l10n.focusPausedState
        : l10n.focusRunningState;
    final targetDurationMs = active.targetDurationMs;
    final progress = targetDurationMs == null
        ? null
        : (display.inMilliseconds / targetDurationMs).clamp(0.0, 1.0);
    final dialSize = MediaQuery.sizeOf(context).width < 350 ? 224.0 : 272.0;
    final isBreak = active.phase != TimerPhaseDto.work;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          key: ValueKey(
            isBreak
                ? engine.isPaused
                      ? 'focus-break-paused'
                      : 'focus-break-running'
                : engine.isPaused
                ? 'focus-paused'
                : 'focus-running',
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            4,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            _FocusHeader(onClose: onClose),
            const SizedBox(height: AppSpacing.lg),
            Text(
              phaseLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.muted,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: _FocusDial(
                diameter: dialSize,
                clock: _formatClock(display),
                semanticsLabel:
                    '$phaseLabel. ${_formatDuration(display)}. $stateLabel',
                progress: progress,
                paused: engine.isPaused,
                isBreak: isBreak,
              ),
            ),
            SizedBox(height: engine.isPaused ? AppSpacing.sm : AppSpacing.md),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: engine.isPaused
                  ? Semantics(
                      key: const ValueKey('focus-paused-label'),
                      liveRegion: true,
                      child: Text(
                        stateLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('focus-running-label-space'),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              active.phase == TimerPhaseDto.work
                  ? task.title
                  : l10n.focusBreakPrompt,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Semantics(
                button: true,
                label: engine.isPaused
                    ? l10n.focusResumeButton
                    : l10n.focusPauseButton,
                child: SizedBox.square(
                  dimension: 64,
                  child: IconButton.filled(
                    key: ValueKey(
                      engine.isPaused ? 'focus-resume' : 'focus-pause',
                    ),
                    onPressed: busy
                        ? null
                        : engine.isPaused
                        ? onResume
                        : onPause,
                    tooltip: engine.isPaused
                        ? l10n.focusResumeButton
                        : l10n.focusPauseButton,
                    icon: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Icon(
                        engine.isPaused
                            ? LucideIcons.play300
                            : LucideIcons.pause300,
                        key: ValueKey(
                          engine.isPaused ? 'resume-icon' : 'pause-icon',
                        ),
                        size: 24,
                      ),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.forest,
                      foregroundColor: AppColors.canvas,
                      disabledBackgroundColor: AppColors.sage,
                      disabledForegroundColor: AppColors.muted,
                      shape: const CircleBorder(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton.icon(
                key: const ValueKey('focus-session-options'),
                onPressed: busy ? null : onOptions,
                icon: const Icon(LucideIcons.ellipsis300, size: 18),
                label: Text(l10n.focusSessionOptionsButton),
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(48, 44)),
                  foregroundColor: WidgetStatePropertyAll(AppColors.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusFinishedView extends StatelessWidget {
  const _FocusFinishedView({
    required this.title,
    required this.body,
    required this.onDone,
    this.recordedTime,
    this.onStartBreak,
  });

  final String title;
  final String body;
  final VoidCallback onDone;
  final String? recordedTime;
  final VoidCallback? onStartBreak;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          key: const ValueKey('focus-finished'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: 48),
            Center(
              child: _FocusResultDial(
                recordedTime: recordedTime,
                semanticsLabel: '$title. $body',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (onStartBreak != null) ...[
              Center(
                child: SizedBox(
                  width: 280,
                  child: FilledButton(
                    key: const ValueKey('focus-start-break'),
                    onPressed: onStartBreak,
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size.fromHeight(52)),
                    ),
                    child: Text(l10n.focusStartBreakButton),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Center(
              child: TextButton(
                key: const ValueKey('focus-done'),
                onPressed: onDone,
                child: Text(l10n.focusDoneButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusHeader extends StatelessWidget {
  const _FocusHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('focus-close'),
            onPressed: onClose,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(LucideIcons.x300),
          ),
          const Spacer(),
          Text(
            l10n.focusTitle,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppColors.muted),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _FocusCenteredState extends StatelessWidget {
  const _FocusCenteredState({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: AppColors.ink),
      child: child,
    ),
  );
}

class _FocusErrorState extends StatelessWidget {
  const _FocusErrorState({required this.onRetry, required this.onExit});
  final VoidCallback onRetry;
  final VoidCallback onExit;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onExit,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(LucideIcons.arrowLeft300),
                color: AppColors.ink,
              ),
              Icon(LucideIcons.cloudOff300, color: AppColors.coral),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.focusLoadFailed,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: onRetry, child: Text(l10n.retryButton)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusConflictState extends StatelessWidget {
  const _FocusConflictState({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.focusActiveConflictTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.focusActiveConflictBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: onBack,
                child: Text(
                  MaterialLocalizations.of(context).backButtonTooltip,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusStateTransition extends StatelessWidget {
  const _FocusStateTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: AppColors.canvas,
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [...previousChildren, ?currentChild],
          ),
          transitionBuilder: (child, animation) => Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.canvas),
              FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                  child: child,
                ),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FocusDial extends StatelessWidget {
  const _FocusDial({
    required this.diameter,
    required this.clock,
    required this.semanticsLabel,
    required this.progress,
    this.clockKey = const ValueKey('focus-clock'),
    this.paused = false,
    this.isBreak = false,
  });

  final double diameter;
  final String clock;
  final String semanticsLabel;
  final double? progress;
  final Key clockKey;
  final bool paused;
  final bool isBreak;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final activeColor = isBreak ? AppColors.sage : AppColors.forest;
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        duration: duration,
        curve: Curves.easeOutCubic,
        tween: Tween<double>(end: progress ?? -1),
        builder: (context, animatedProgress, child) =>
            TweenAnimationBuilder<double>(
              duration: duration,
              curve: Curves.easeOutCubic,
              tween: Tween<double>(end: paused ? 1 : 0),
              builder: (context, pausedAmount, child) {
                final arcColor = Color.lerp(
                  activeColor,
                  AppColors.sage,
                  pausedAmount,
                )!;
                return CustomPaint(
                  painter: _OpenDialPainter(
                    progress: animatedProgress < 0
                        ? null
                        : animatedProgress.clamp(0, 1),
                    arcColor: arcColor,
                  ),
                  child: child,
                );
              },
              child: child,
            ),
        child: SizedBox.square(
          dimension: diameter,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  clock,
                  key: clockKey,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 64,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusResultDial extends StatelessWidget {
  const _FocusResultDial({this.recordedTime, required this.semanticsLabel});

  final String? recordedTime;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    excludeSemantics: true,
    child: CustomPaint(
      painter: const _OpenDialPainter(progress: null, arcColor: AppColors.sage),
      child: SizedBox.square(
        dimension: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.check300,
                size: 30,
                color: AppColors.forest,
              ),
              if (recordedTime != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  recordedTime!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _OpenDialPainter extends CustomPainter {
  const _OpenDialPainter({required this.progress, required this.arcColor});

  final double? progress;
  final Color arcColor;

  static const _startAngle = 135 * math.pi / 180;
  static const _sweepAngle = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeInset = 4.0;
    final rect =
        Offset(strokeInset, strokeInset) &
        Size(size.width - strokeInset * 2, size.height - strokeInset * 2);
    final track = Paint()
      ..color = AppColors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, track);

    final value = progress;
    final active = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = value == null ? 1.25 : 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      _startAngle,
      value == null ? _sweepAngle : _sweepAngle * value,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _OpenDialPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.arcColor != arcColor;
}

class _FocusSessionSheet extends StatelessWidget {
  const _FocusSessionSheet({
    required this.active,
    required this.canCompleteTask,
  });

  final ActiveTimerSessionDto active;
  final bool canCompleteTask;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isWork = active.phase == TimerPhaseDto.work;
    final canAddTime = isWork && active.mode == TimerModeDto.pomodoro;
    return Material(
      color: AppColors.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.focusSessionOptionsButton,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (canAddTime)
              _FocusSessionActionTile(
                key: const ValueKey('focus-add-time'),
                icon: LucideIcons.plus300,
                label: l10n.focusAddTimeButton,
                action: _FocusSessionAction.addTime,
              ),
            _FocusSessionActionTile(
              key: const ValueKey('focus-finish'),
              icon: LucideIcons.square300,
              label: isWork
                  ? l10n.focusFinishSessionButton
                  : l10n.focusEndBreakButton,
              action: _FocusSessionAction.finish,
            ),
            if (canCompleteTask)
              _FocusSessionActionTile(
                key: const ValueKey('focus-complete-task'),
                icon: LucideIcons.circleCheck300,
                label: l10n.focusCompleteTaskButton,
                action: _FocusSessionAction.completeTask,
              ),
            if (isWork)
              _FocusSessionActionTile(
                key: const ValueKey('focus-save-and-exit'),
                icon: LucideIcons.save300,
                label: l10n.focusSaveAndExitButton,
                action: _FocusSessionAction.saveAndExit,
              ),
            const Divider(height: 1, color: AppColors.hairline),
            _FocusSessionActionTile(
              key: const ValueKey('focus-discard'),
              icon: LucideIcons.trash2300,
              label: l10n.focusDiscardButton,
              action: _FocusSessionAction.discard,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusSessionActionTile extends StatelessWidget {
  const _FocusSessionActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.action,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final _FocusSessionAction action;
  final bool destructive;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 52,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20),
    title: Text(label),
    textColor: destructive ? AppColors.coral : AppColors.ink,
    iconColor: destructive ? AppColors.coral : AppColors.muted,
    onTap: () => Navigator.pop(context, action),
  );
}

class _TimerSettingDropdown extends StatelessWidget {
  const _TimerSettingDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.valueLabel,
  });
  final String label;
  final int value;
  final List<int> values;
  final ValueChanged<int> onChanged;
  final String Function(int)? valueLabel;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final option in values)
        DropdownMenuItem(
          value: option,
          child: Text(valueLabel?.call(option) ?? '$option min'),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

TimerSettings _copySettings(
  TimerSettings value, {
  int? workMinutes,
  int? shortBreakMinutes,
  int? longBreakMinutes,
  int? longBreakEvery,
  bool? notificationsEnabled,
}) => TimerSettings(
  workMinutes: workMinutes ?? value.workMinutes,
  shortBreakMinutes: shortBreakMinutes ?? value.shortBreakMinutes,
  longBreakMinutes: longBreakMinutes ?? value.longBreakMinutes,
  longBreakEvery: longBreakEvery ?? value.longBreakEvery,
  notificationsEnabled: notificationsEnabled ?? value.notificationsEnabled,
);

String _formatClock(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 1) return '${duration.inSeconds}s';
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}

enum _FocusSessionAction { addTime, finish, completeTask, saveAndExit, discard }
