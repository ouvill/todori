import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/timer/timer_engine.dart';
import 'package:todori/src/timer/timer_settings.dart';
import 'package:todori/src/ui/dialogs.dart';
import 'package:todori/src/ui/states.dart';
import 'package:todori/src/ui/task_components.dart';
import 'package:todori/src/ui/theme.dart';

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
    final active = engineAsync.value?.active;
    final isImmersive = active != null;

    return PopScope<void>(
      canPop: active == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && active != null) {
          unawaited(_requestExit());
        }
      },
      child: Scaffold(
        key: const ValueKey('focus-screen'),
        backgroundColor: isImmersive
            ? AppFocusColors.surface
            : AppColors.canvas,
        body: SafeArea(
          child: tasksAsync.when(
            loading: () => _FocusCenteredState(
              inverse: isImmersive,
              child: Semantics(
                label: _l10n.focusRestoring,
                liveRegion: true,
                child: const AppLoadingState(),
              ),
            ),
            error: (error, stackTrace) => _FocusErrorState(
              inverse: isImmersive,
              onRetry: () => ref.invalidate(tasksProvider(widget.listId)),
              onExit: _leaveFocus,
            ),
            data: (tasks) {
              final task = tasks
                  .where((item) => item.id == widget.taskId)
                  .firstOrNull;
              if (task == null) {
                return _FocusErrorState(
                  inverse: isImmersive,
                  onRetry: () => ref.invalidate(tasksProvider(widget.listId)),
                  onExit: _leaveFocus,
                );
              }
              return engineAsync.when(
                loading: () => _FocusCenteredState(
                  inverse: isImmersive,
                  child: Semantics(
                    label: _l10n.focusRestoring,
                    liveRegion: true,
                    child: const AppLoadingState(),
                  ),
                ),
                error: (error, stackTrace) => _FocusErrorState(
                  inverse: isImmersive,
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
                      onClose: _requestExit,
                      onPause: () => _runEngine(
                        () => ref.read(timerEngineProvider.notifier).pause(),
                      ),
                      onResume: () => _runEngine(
                        () => ref.read(timerEngineProvider.notifier).resume(),
                      ),
                      onAddTime: engine.active!.mode == TimerModeDto.pomodoro
                          ? () => _runEngine(
                              () => ref
                                  .read(timerEngineProvider.notifier)
                                  .addTime(const Duration(minutes: 5)),
                            )
                          : null,
                      onFinish: () => _finish(TimerFinishKindDto.completed),
                      onSaveAndExit: engine.active!.phase == TimerPhaseDto.work
                          ? () => _finish(
                              TimerFinishKindDto.interrupted,
                              exit: true,
                            )
                          : null,
                      onDiscard: _discard,
                      onCompleteTask: engine.active!.phase == TimerPhaseDto.work
                          ? () => _completeTask(task)
                          : null,
                    );
                  }
                  if (_breakFinished) {
                    return _FocusFinishedView(
                      title: _l10n.focusBreakFinishedTitle,
                      body: _l10n.focusBreakFinishedBody,
                      onDone: _leaveFocus,
                    );
                  }
                  final completion = engine.lastCompletion;
                  if (completion != null ||
                      _taskCompleted ||
                      _sessionFinished ||
                      engine.isBreakPending) {
                    return _FocusFinishedView(
                      title: _l10n.focusFinishedTitle,
                      body: completion == null
                          ? engine.isBreakPending
                                ? _l10n.focusBreakPrompt
                                : _l10n.undoCompleteMessage
                          : _l10n.focusFinishedBody(
                              _formatDuration(
                                Duration(
                                  milliseconds: completion.activeDurationMs
                                      .toInt(),
                                ),
                              ),
                            ),
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
                      inverse: false,
                      child: Semantics(
                        label: _l10n.focusRestoring,
                        liveRegion: true,
                        child: const AppLoadingState(),
                      ),
                    ),
                    error: (error, stackTrace) => _FocusErrorState(
                      inverse: false,
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
    final action = await showModalBottomSheet<_FocusExitAction>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.play300),
              title: Text(_l10n.focusKeepSessionButton),
              onTap: () => Navigator.pop(context, _FocusExitAction.keep),
            ),
            if (active.phase == TimerPhaseDto.work)
              ListTile(
                leading: const Icon(LucideIcons.save300),
                title: Text(_l10n.focusSaveAndExitButton),
                onTap: () => Navigator.pop(context, _FocusExitAction.save),
              ),
            ListTile(
              leading: const Icon(LucideIcons.trash2300),
              title: Text(_l10n.focusDiscardButton),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () => Navigator.pop(context, _FocusExitAction.discard),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null || action == _FocusExitAction.keep) {
      return;
    }
    if (action == _FocusExitAction.save) {
      await _finish(TimerFinishKindDto.interrupted, exit: true);
    } else {
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
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          key: const ValueKey('focus-setup'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            4,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            _FocusHeader(inverse: false, onClose: onClose),
            const SizedBox(height: AppSpacing.xl),
            Text(
              l10n.focusSetupTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.focusSetupBody,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(task.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            _FocusModeSelector(
              selectedMode: selectedMode,
              enabled: !busy,
              onChanged: onModeChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              selectedMode == TimerModeDto.pomodoro
                  ? l10n.focusPomodoroSummary(
                      settings.workMinutes,
                      settings.shortBreakMinutes,
                    )
                  : l10n.focusStopwatchSummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const ValueKey('focus-start'),
              onPressed: busy || isTaskClosed(task) ? null : onStart,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size.fromHeight(52)),
              ),
              child: Text(l10n.focusStartButton),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: busy ? null : onSettings,
              icon: const Icon(LucideIcons.settings2300),
              label: Text(l10n.focusSettingsButton),
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
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
    final highScale = MediaQuery.textScalerOf(context).scale(16) > 21;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360 || highScale) {
          return Column(
            key: const ValueKey('focus-mode-selector-stacked'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FocusModeButton(
                label: l10n.focusPomodoroMode,
                selected: selectedMode == TimerModeDto.pomodoro,
                onPressed: enabled
                    ? () => onChanged(TimerModeDto.pomodoro)
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              _FocusModeButton(
                label: l10n.focusStopwatchMode,
                selected: selectedMode == TimerModeDto.stopwatch,
                onPressed: enabled
                    ? () => onChanged(TimerModeDto.stopwatch)
                    : null,
              ),
            ],
          );
        }
        return SegmentedButton<TimerModeDto>(
          key: const ValueKey('focus-mode-selector'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: TimerModeDto.pomodoro,
              label: Text(l10n.focusPomodoroMode),
            ),
            ButtonSegment(
              value: TimerModeDto.stopwatch,
              label: Text(l10n.focusStopwatchMode),
            ),
          ],
          selected: {selectedMode},
          onSelectionChanged: enabled
              ? (values) => onChanged(values.single)
              : null,
        );
      },
    );
  }
}

class _FocusModeButton extends StatelessWidget {
  const _FocusModeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      backgroundColor: WidgetStatePropertyAll(
        selected ? AppColors.subtleSage : Colors.transparent,
      ),
      side: const WidgetStatePropertyAll(BorderSide(color: AppColors.hairline)),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: Text(label, textAlign: TextAlign.center),
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
    required this.onAddTime,
    required this.onFinish,
    required this.onSaveAndExit,
    required this.onDiscard,
    required this.onCompleteTask,
  });

  final TaskDto task;
  final TimerEngineState engine;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback? onAddTime;
  final VoidCallback onFinish;
  final VoidCallback? onSaveAndExit;
  final VoidCallback onDiscard;
  final VoidCallback? onCompleteTask;

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
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppFocusColors.text,
          onPrimary: AppFocusColors.surface,
          surface: AppFocusColors.surface,
          onSurface: AppFocusColors.text,
          onSurfaceVariant: AppFocusColors.muted,
          outlineVariant: AppFocusColors.hairline,
          error: AppFocusColors.error,
        ),
        scaffoldBackgroundColor: AppFocusColors.surface,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: ValueKey(engine.isPaused ? 'focus-paused' : 'focus-running'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              4,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              _FocusHeader(inverse: true, onClose: onClose),
              const SizedBox(height: AppSpacing.lg),
              Text(
                phaseLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppFocusColors.muted,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                label: '$phaseLabel. ${_formatDuration(display)}. $stateLabel',
                child: SizedBox(
                  height: 112,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _formatClock(display),
                      key: const ValueKey('focus-clock'),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppFocusColors.text,
                        fontSize: 72,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (engine.isPaused) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    stateLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppFocusColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                active.phase == TimerPhaseDto.work
                    ? task.title
                    : l10n.focusBreakPrompt,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: AppFocusColors.text),
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton.icon(
                    key: ValueKey(
                      engine.isPaused ? 'focus-resume' : 'focus-pause',
                    ),
                    onPressed: busy
                        ? null
                        : engine.isPaused
                        ? onResume
                        : onPause,
                    icon: Icon(
                      engine.isPaused
                          ? LucideIcons.play300
                          : LucideIcons.pause300,
                    ),
                    label: Text(
                      engine.isPaused
                          ? l10n.focusResumeButton
                          : l10n.focusPauseButton,
                    ),
                    style: _focusButtonStyle(primary: true),
                  ),
                  if (onAddTime != null)
                    OutlinedButton.icon(
                      key: const ValueKey('focus-add-time'),
                      onPressed: busy ? null : onAddTime,
                      icon: const Icon(LucideIcons.plus300),
                      label: Text(l10n.focusAddTimeButton),
                      style: _focusButtonStyle(),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('focus-finish'),
                    onPressed: busy ? null : onFinish,
                    icon: const Icon(LucideIcons.square300),
                    label: Text(l10n.focusFinishButton),
                    style: _focusButtonStyle(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (onCompleteTask != null)
                TextButton.icon(
                  key: const ValueKey('focus-complete-task'),
                  onPressed: busy ? null : onCompleteTask,
                  icon: const Icon(LucideIcons.circleCheck300),
                  label: Text(l10n.focusCompleteTaskButton),
                  style: _focusTextButtonStyle(),
                ),
              if (onSaveAndExit != null)
                TextButton(
                  onPressed: busy ? null : onSaveAndExit,
                  style: _focusTextButtonStyle(),
                  child: Text(l10n.focusSaveAndExitButton),
                ),
              TextButton(
                onPressed: busy ? null : onDiscard,
                style: _focusTextButtonStyle(destructive: true),
                child: Text(l10n.focusDiscardButton),
              ),
            ],
          ),
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
    this.onStartBreak,
  });

  final String title;
  final String body;
  final VoidCallback onDone;
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
            const SizedBox(height: 80),
            Icon(
              LucideIcons.circleCheck300,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
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
              FilledButton(
                key: const ValueKey('focus-start-break'),
                onPressed: onStartBreak,
                child: Text(l10n.focusStartBreakButton),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextButton(
              key: const ValueKey('focus-done'),
              onPressed: onDone,
              child: Text(l10n.focusDoneButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusHeader extends StatelessWidget {
  const _FocusHeader({required this.inverse, required this.onClose});

  final bool inverse;
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
            color: inverse ? AppFocusColors.text : null,
          ),
          const Spacer(),
          Text(
            l10n.focusTitle,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: inverse ? AppFocusColors.muted : null,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _FocusCenteredState extends StatelessWidget {
  const _FocusCenteredState({required this.inverse, required this.child});
  final bool inverse;
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
    child: DefaultTextStyle.merge(
      style: TextStyle(color: inverse ? AppFocusColors.text : AppColors.ink),
      child: child,
    ),
  );
}

class _FocusErrorState extends StatelessWidget {
  const _FocusErrorState({
    required this.inverse,
    required this.onRetry,
    required this.onExit,
  });
  final bool inverse;
  final VoidCallback onRetry;
  final VoidCallback onExit;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final foreground = inverse ? AppFocusColors.text : AppColors.ink;
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
                color: foreground,
              ),
              Icon(LucideIcons.cloudOff300, color: AppColors.coral),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.focusLoadFailed,
                textAlign: TextAlign.center,
                style: TextStyle(color: foreground),
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
              Text(l10n.focusActiveConflictBody, textAlign: TextAlign.center),
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

ButtonStyle _focusButtonStyle({bool primary = false}) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(148, 52)),
  foregroundColor: WidgetStatePropertyAll(
    primary ? AppFocusColors.surface : AppFocusColors.text,
  ),
  backgroundColor: WidgetStatePropertyAll(
    primary ? AppFocusColors.text : Colors.transparent,
  ),
  side: primary
      ? null
      : const WidgetStatePropertyAll(
          BorderSide(color: AppFocusColors.hairline),
        ),
);

ButtonStyle _focusTextButtonStyle({bool destructive = false}) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
  foregroundColor: WidgetStatePropertyAll(
    destructive ? AppFocusColors.error : AppFocusColors.muted,
  ),
);

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

enum _FocusExitAction { keep, save, discard }
