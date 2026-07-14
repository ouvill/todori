import 'dart:async';

import 'package:todori/src/core/realtime_sync.dart';

class FakeRealtimeTimers {
  final List<FakeRealtimeTimer> timers = [];

  RealtimeTimer create(Duration delay, void Function() callback) {
    final timer = FakeRealtimeTimer(delay, callback);
    timers.add(timer);
    return timer;
  }

  Iterable<FakeRealtimeTimer> get active =>
      timers.where((timer) => !timer.cancelled && !timer.fired);

  FakeRealtimeTimer activeWithDelay(Duration delay) =>
      active.lastWhere((timer) => timer.delay == delay);
}

class FakeRealtimeTimer implements RealtimeTimer {
  FakeRealtimeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) {
      return;
    }
    fired = true;
    _callback();
  }

  @override
  void cancel() {
    cancelled = true;
  }
}

class FakeRealtimeSocket implements RealtimeSocket {
  final StreamController<Object?> _messages = StreamController<Object?>();
  bool closed = false;

  @override
  Stream<Object?> get messages => _messages.stream;

  void add(Object? frame) => _messages.add(frame);

  Future<void> end() => _messages.close();

  @override
  Future<void> close() async {
    closed = true;
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }
}

class FakeRealtimeSocketConnector implements RealtimeSocketConnector {
  final List<FakeRealtimeSocket> sockets = [];
  final List<({Uri websocketUrl, String ticket})> calls = [];
  int failuresRemaining = 0;

  @override
  Future<RealtimeSocket> connect({
    required Uri websocketUrl,
    required String ticket,
  }) async {
    calls.add((websocketUrl: websocketUrl, ticket: ticket));
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw Exception('socket unavailable');
    }
    final socket = FakeRealtimeSocket();
    sockets.add(socket);
    return socket;
  }
}
