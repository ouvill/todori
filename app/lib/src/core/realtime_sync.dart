import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/io.dart';

// Public constructor argument names stay descriptive while the callbacks are
// stored privately; initializing formals would expose underscore-only names.
// ignore_for_file: prefer_initializing_formals

const realtimeMutationDebounce = Duration(milliseconds: 250);
const realtimeConnectedSafetyPull = Duration(minutes: 5);
const realtimeDisconnectedPolling = Duration(seconds: 30);
const realtimeTicketRefreshLead = Duration(seconds: 30);
const realtimeReconnectDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

abstract interface class RealtimeTimer {
  void cancel();
}

typedef RealtimeTimerFactory =
    RealtimeTimer Function(Duration delay, void Function() callback);

class SystemRealtimeTimer implements RealtimeTimer {
  SystemRealtimeTimer(Duration delay, void Function() callback)
    : _timer = Timer(delay, callback);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

RealtimeTimer systemRealtimeTimerFactory(
  Duration delay,
  void Function() callback,
) => SystemRealtimeTimer(delay, callback);

/// Coalesces wake-up hints around the existing HTTPS synchronization run.
///
/// This class owns timing and single-flight behavior only. The callback keeps
/// the actual push/pull, cursor, merge, and provider invalidation logic in the
/// existing client and Riverpod layers.
class RealtimeSyncScheduler {
  RealtimeSyncScheduler({
    required Future<void> Function() runSync,
    RealtimeTimerFactory timerFactory = systemRealtimeTimerFactory,
    this.debounce = realtimeMutationDebounce,
    this.connectedPoll = realtimeConnectedSafetyPull,
    this.disconnectedPoll = realtimeDisconnectedPolling,
  }) : _runSync = runSync,
       _timerFactory = timerFactory;

  final Future<void> Function() _runSync;
  final RealtimeTimerFactory _timerFactory;
  final Duration debounce;
  final Duration connectedPoll;
  final Duration disconnectedPoll;

  RealtimeTimer? _debounceTimer;
  RealtimeTimer? _pollTimer;
  Future<void>? _inFlight;
  bool _dirty = false;
  bool _enabled = false;
  bool _foreground = true;
  bool _connected = false;
  bool _disposed = false;

  bool get isConnected => _connected;

  bool get _active => !_disposed && _enabled && _foreground;

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) {
      return;
    }
    _enabled = enabled;
    if (!_active) {
      _cancelIdleTimers();
      _dirty = false;
      return;
    }
    _schedulePoll();
    unawaited(syncNow());
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) {
      return;
    }
    _foreground = foreground;
    if (!_active) {
      _cancelIdleTimers();
      _dirty = false;
      return;
    }
    _schedulePoll();
  }

  void setConnected(bool connected) {
    if (_disposed || _connected == connected) {
      return;
    }
    _connected = connected;
    if (_active) {
      _schedulePoll();
    }
  }

  /// Schedules a local mutation or remote change hint after the common 250ms
  /// debounce. A trigger received during a run marks the scheduler dirty and
  /// guarantees a follow-up run.
  void trigger() {
    if (!_active) {
      return;
    }
    if (_inFlight != null) {
      _dirty = true;
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = _timerFactory(debounce, () {
      _debounceTimer = null;
      unawaited(syncNow());
    });
  }

  Future<void> syncNow() {
    if (!_active) {
      return Future<void>.value();
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final current = _inFlight;
    if (current != null) {
      _dirty = true;
      return current;
    }
    late final Future<void> operation;
    operation = _drain().whenComplete(() {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    });
    _inFlight = operation;
    return operation;
  }

  Future<void> _drain() async {
    do {
      _dirty = false;
      try {
        await _runSync();
      } catch (_) {
        // Automatic realtime orchestration is best effort. The underlying
        // SyncStatus remains the diagnostic source and the next poll retries.
      }
    } while (_active && _dirty);
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    final delay = _connected ? connectedPoll : disconnectedPoll;
    _pollTimer = _timerFactory(delay, () {
      _pollTimer = null;
      if (!_active) {
        return;
      }
      _schedulePoll();
      unawaited(syncNow());
    });
  }

  void _cancelIdleTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelIdleTimers();
    _dirty = false;
  }
}

class RealtimeTicketView {
  const RealtimeTicketView({
    required this.websocketUrl,
    required this.ticket,
    required this.expiresAt,
  });

  final String websocketUrl;
  final String ticket;
  final DateTime expiresAt;
}

abstract interface class RealtimeSocket {
  Stream<Object?> get messages;

  Future<void> close();
}

abstract interface class RealtimeSocketConnector {
  Future<RealtimeSocket> connect({
    required Uri websocketUrl,
    required String ticket,
  });
}

class IoRealtimeSocketConnector implements RealtimeSocketConnector {
  const IoRealtimeSocketConnector();

  @override
  Future<RealtimeSocket> connect({
    required Uri websocketUrl,
    required String ticket,
  }) async {
    final channel = IOWebSocketChannel.connect(
      websocketUrl,
      headers: {'Authorization': 'Bearer $ticket'},
      connectTimeout: const Duration(seconds: 10),
    );
    await channel.ready;
    return _IoRealtimeSocket(channel);
  }
}

class _IoRealtimeSocket implements RealtimeSocket {
  _IoRealtimeSocket(this._channel);

  final IOWebSocketChannel _channel;

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

enum RealtimeConnectionState { disconnected, connecting, connected }

bool isRealtimeChangedFrame(Object? frame) {
  if (frame is! String) {
    return false;
  }
  try {
    final value = jsonDecode(frame);
    if (value is! Map<String, dynamic> || value.length != 2) {
      return false;
    }
    return value['v'] == 1 &&
        value['type'] == 'changed' &&
        value.containsKey('v') &&
        value.containsKey('type');
  } catch (_) {
    return false;
  }
}

/// Owns only foreground WebSocket lifecycle. It never interprets sync state;
/// a valid fixed frame invokes [onChanged] as a wake-up hint.
class RealtimeConnectionController {
  RealtimeConnectionController({
    required Future<RealtimeTicketView> Function() fetchTicket,
    required RealtimeSocketConnector connector,
    required void Function() onChanged,
    required void Function(bool connected) onConnectionChanged,
    RealtimeTimerFactory timerFactory = systemRealtimeTimerFactory,
    DateTime Function()? now,
    double Function()? jitter,
  }) : _fetchTicket = fetchTicket,
       _connector = connector,
       _onChanged = onChanged,
       _onConnectionChanged = onConnectionChanged,
       _timerFactory = timerFactory,
       _now = now ?? DateTime.now,
       _jitter = jitter ?? Random.secure().nextDouble;

  final Future<RealtimeTicketView> Function() _fetchTicket;
  final RealtimeSocketConnector _connector;
  final void Function() _onChanged;
  final void Function(bool connected) _onConnectionChanged;
  final RealtimeTimerFactory _timerFactory;
  final DateTime Function() _now;
  final double Function() _jitter;

  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;
  RealtimeTimer? _retryTimer;
  RealtimeTimer? _refreshTimer;
  RealtimeSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  int _retryAttempt = 0;

  RealtimeConnectionState get state => _state;

  Future<void> start() async {
    if (_disposed || _running) {
      return;
    }
    _running = true;
    _retryAttempt = 0;
    final generation = ++_generation;
    await _connect(generation);
  }

  Future<void> stop() async {
    if (!_running && _state == RealtimeConnectionState.disconnected) {
      return;
    }
    _running = false;
    _generation += 1;
    _retryTimer?.cancel();
    _retryTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    _setState(RealtimeConnectionState.disconnected);
    try {
      await socket?.close();
    } catch (_) {
      // Closing is best effort and never exposes connection material.
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
  }

  Future<void> _connect(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    _setState(RealtimeConnectionState.connecting);
    try {
      final ticket = await _fetchTicket();
      if (!_isCurrent(generation)) {
        return;
      }
      final uri = Uri.parse(ticket.websocketUrl);
      if (!_validWebsocketUri(uri) ||
          !ticket.expiresAt.toUtc().isAfter(
            _now().toUtc().add(realtimeTicketRefreshLead),
          )) {
        throw const FormatException();
      }
      final socket = await _connector.connect(
        websocketUrl: uri,
        ticket: ticket.ticket,
      );
      if (!_isCurrent(generation)) {
        await socket.close();
        return;
      }
      _retryAttempt = 0;
      _socket = socket;
      _subscription = socket.messages.listen(
        (frame) {
          if (_isCurrent(generation) && isRealtimeChangedFrame(frame)) {
            _onChanged();
          }
        },
        onError: (_) => _handleDisconnect(generation),
        onDone: () => _handleDisconnect(generation),
        cancelOnError: true,
      );
      _setState(RealtimeConnectionState.connected);
      _scheduleRefresh(ticket.expiresAt.toUtc(), generation);
    } catch (_) {
      if (_isCurrent(generation)) {
        final subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
        final socket = _socket;
        _socket = null;
        try {
          await socket?.close();
        } catch (_) {
          // Failed setup is retried without exposing socket details.
        }
        _setState(RealtimeConnectionState.disconnected);
        _scheduleRetry(generation);
      }
    }
  }

  void _scheduleRefresh(DateTime expiresAt, int generation) {
    _refreshTimer?.cancel();
    final refreshAt = expiresAt.subtract(realtimeTicketRefreshLead);
    final delay = refreshAt.difference(_now().toUtc());
    _refreshTimer = _timerFactory(delay, () {
      if (_isCurrent(generation)) {
        unawaited(_replaceConnection(generation));
      }
    });
  }

  Future<void> _replaceConnection(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    final nextGeneration = ++_generation;
    _refreshTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    _setState(RealtimeConnectionState.disconnected);
    try {
      await socket?.close();
    } catch (_) {
      // A fresh ticket and socket are still attempted below.
    }
    await _connect(nextGeneration);
  }

  void _handleDisconnect(int generation) {
    if (!_isCurrent(generation)) {
      return;
    }
    final nextGeneration = ++_generation;
    _subscription = null;
    _socket = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _setState(RealtimeConnectionState.disconnected);
    _scheduleRetry(nextGeneration);
  }

  void _scheduleRetry(int generation) {
    if (!_isCurrent(generation)) {
      return;
    }
    _retryTimer?.cancel();
    final index = min(_retryAttempt, realtimeReconnectDelays.length - 1);
    final base = realtimeReconnectDelays[index];
    _retryAttempt += 1;
    final jitterFraction = _jitter().clamp(0.0, 1.0);
    final jitterMs = (base.inMilliseconds * 0.25 * jitterFraction).round();
    _retryTimer = _timerFactory(base + Duration(milliseconds: jitterMs), () {
      _retryTimer = null;
      if (_isCurrent(generation)) {
        unawaited(_connect(generation));
      }
    });
  }

  bool _isCurrent(int generation) => _running && generation == _generation;

  void _setState(RealtimeConnectionState next) {
    if (_state == next) {
      return;
    }
    final wasConnected = _state == RealtimeConnectionState.connected;
    _state = next;
    final isConnected = next == RealtimeConnectionState.connected;
    if (wasConnected != isConnected) {
      _onConnectionChanged(isConnected);
    }
  }
}

bool _validWebsocketUri(Uri uri) =>
    uri.scheme == 'wss' &&
    uri.host.isNotEmpty &&
    uri.path == '/v1/connect' &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    uri.userInfo.isEmpty;
