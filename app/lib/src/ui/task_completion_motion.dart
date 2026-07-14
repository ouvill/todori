import 'dart:async';

import 'package:flutter/material.dart';

/// The retained part of Todori's task-completion timeline.
///
/// Checkbox fill, check, halo, and title strike are owned by the task row
/// components. This controller keeps the completed row in its original
/// position for [holdDuration], then exposes [TaskCompletionRetentionPhase.exiting]
/// while the row collapses for [collapseDuration]. A key may identify either a
/// task or a particular occurrence of a task, so Calendar can retain due and
/// scheduled occurrences independently.
class TaskCompletionRetentionController<K extends Object>
    extends ChangeNotifier {
  TaskCompletionRetentionController({
    this.holdDuration = const Duration(milliseconds: 500),
    this.collapseDuration = const Duration(milliseconds: 420),
  });

  final Duration holdDuration;
  final Duration collapseDuration;

  final Map<K, TaskCompletionRetentionPhase> _phases = {};
  final Map<K, Timer> _timers = {};

  Iterable<K> get keys => _phases.keys;

  bool contains(K key) => _phases.containsKey(key);

  TaskCompletionRetentionPhase? phaseOf(K key) => _phases[key];

  /// Starts (or restarts) the hold and collapse timeline for [key].
  void retain(K key) {
    _timers.remove(key)?.cancel();
    _phases[key] = TaskCompletionRetentionPhase.holding;
    notifyListeners();
    _timers[key] = Timer(holdDuration, () => _beginExit(key));
  }

  /// Cancels retention immediately, for reopen, failed completion, or undo.
  void cancel(K key) {
    _timers.remove(key)?.cancel();
    if (_phases.remove(key) != null) {
      notifyListeners();
    }
  }

  void _beginExit(K key) {
    if (!_phases.containsKey(key)) {
      return;
    }
    _phases[key] = TaskCompletionRetentionPhase.exiting;
    notifyListeners();
    _timers[key] = Timer(collapseDuration, () {
      _timers.remove(key);
      if (_phases.remove(key) != null) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _phases.clear();
    super.dispose();
  }
}

enum TaskCompletionRetentionPhase { holding, exiting }

/// Smoothly removes a retained task row while following rows close the gap.
class AppTaskCompletionExit extends StatelessWidget {
  const AppTaskCompletionExit({
    super.key,
    required this.isExiting,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
  });

  final bool isExiting;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (!isExiting || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: duration,
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, -4 * (1 - value)),
                child: child,
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
