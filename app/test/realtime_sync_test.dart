import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskveil/src/core/realtime_sync.dart';

import 'support/fake_realtime.dart';

void main() {
  group('realtime frame parser', () {
    test('accepts only the exact v1 changed frame', () {
      expect(isRealtimeChangedFrame('{"v":1,"type":"changed"}'), isTrue);
      expect(isRealtimeChangedFrame('{"type":"changed","v":1}'), isTrue);

      for (final invalid in <Object?>[
        null,
        <int>[1, 2],
        'not json',
        '{}',
        '{"v":1.0,"type":"changed"}',
        '{"v":2,"type":"changed"}',
        '{"v":1,"type":"unknown"}',
        '{"v":1,"type":"changed","high_water":4}',
        '{"v":1,"type":"changed","tenant_id":"secret"}',
      ]) {
        expect(isRealtimeChangedFrame(invalid), isFalse, reason: '$invalid');
      }
    });
  });

  group('realtime sync scheduler', () {
    test('coalesces triggers for 250ms', () async {
      final timers = FakeRealtimeTimers();
      var runs = 0;
      final scheduler = RealtimeSyncScheduler(
        runSync: () async => runs += 1,
        timerFactory: timers.create,
      );
      addTearDown(scheduler.dispose);

      scheduler.setEnabled(true);
      await _pumpAsync();
      runs = 0;

      scheduler.trigger();
      scheduler.trigger();
      scheduler.trigger();

      expect(
        timers.active.where((timer) => timer.delay == realtimeMutationDebounce),
        hasLength(1),
      );
      expect(runs, 0);

      timers.activeWithDelay(realtimeMutationDebounce).fire();
      await _pumpAsync();
      expect(runs, 1);
    });

    test('runs a dirty follow-up until a trigger-free run completes', () async {
      final timers = FakeRealtimeTimers();
      final firstRun = Completer<void>();
      var runs = 0;
      final scheduler = RealtimeSyncScheduler(
        runSync: () {
          runs += 1;
          return runs == 1 ? firstRun.future : Future<void>.value();
        },
        timerFactory: timers.create,
      );
      addTearDown(scheduler.dispose);

      scheduler.setEnabled(true);
      await _pumpAsync();
      expect(runs, 1);

      scheduler.trigger();
      scheduler.trigger();
      firstRun.complete();
      await _pumpAsync();

      expect(runs, 2);
    });

    test(
      'switches between 30 second fallback and 5 minute safety pull',
      () async {
        final timers = FakeRealtimeTimers();
        var runs = 0;
        final scheduler = RealtimeSyncScheduler(
          runSync: () async {
            runs += 1;
          },
          timerFactory: timers.create,
        );
        addTearDown(scheduler.dispose);

        scheduler.setEnabled(true);
        await _pumpAsync();
        runs = 0;
        timers.activeWithDelay(realtimeDisconnectedPolling).fire();
        await _pumpAsync();
        expect(runs, 1);

        scheduler.setConnected(true);
        timers.activeWithDelay(realtimeConnectedSafetyPull).fire();
        await _pumpAsync();
        expect(runs, 2);

        scheduler.setForeground(false);
        expect(timers.active, isEmpty);
      },
    );
  });

  group('realtime connection lifecycle', () {
    test(
      'connects, filters frames, refreshes 30 seconds early, and stops',
      () async {
        final now = DateTime.utc(2026, 7, 15);
        final timers = FakeRealtimeTimers();
        final connector = FakeRealtimeSocketConnector();
        final connectionStates = <bool>[];
        var changed = 0;
        var tickets = 0;
        final controller = RealtimeConnectionController(
          fetchTicket: () async {
            tickets += 1;
            return RealtimeTicketView(
              websocketUrl: 'wss://realtime.example/v1/connect',
              ticket: 'opaque-$tickets',
              expiresAt: now.add(const Duration(minutes: 5)),
            );
          },
          connector: connector,
          onChanged: () => changed += 1,
          onConnectionChanged: connectionStates.add,
          timerFactory: timers.create,
          now: () => now,
          jitter: () => 0,
        );
        addTearDown(controller.dispose);

        await controller.start();
        expect(controller.state, RealtimeConnectionState.connected);
        expect(connectionStates, [true]);
        expect(connector.calls.single.websocketUrl.query, isEmpty);
        expect(connector.calls.single.ticket, 'opaque-1');

        final firstSocket = connector.sockets.single;
        firstSocket.add('{"v":1,"type":"changed","record_id":"x"}');
        firstSocket.add('{"v":1,"type":"changed"}');
        await _pumpAsync();
        expect(changed, 1);

        timers.activeWithDelay(const Duration(minutes: 4, seconds: 30)).fire();
        await _pumpAsync();
        expect(tickets, 2);
        expect(connector.sockets, hasLength(2));
        expect(firstSocket.closed, isTrue);

        await controller.stop();
        expect(controller.state, RealtimeConnectionState.disconnected);
        expect(connectionStates, [true, false, true, false]);
        expect(connector.sockets.last.closed, isTrue);
      },
    );

    test('retries with the fixed exponential sequence and jitter', () async {
      final now = DateTime.utc(2026, 7, 15);
      final timers = FakeRealtimeTimers();
      final connector = FakeRealtimeSocketConnector()..failuresRemaining = 2;
      final controller = RealtimeConnectionController(
        fetchTicket: () async => RealtimeTicketView(
          websocketUrl: 'wss://realtime.example/v1/connect',
          ticket: 'opaque',
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
        connector: connector,
        onChanged: () {},
        onConnectionChanged: (_) {},
        timerFactory: timers.create,
        now: () => now,
        jitter: () => 0,
      );
      addTearDown(controller.dispose);

      await controller.start();
      expect(controller.state, RealtimeConnectionState.disconnected);
      timers.activeWithDelay(const Duration(seconds: 1)).fire();
      await _pumpAsync();
      expect(controller.state, RealtimeConnectionState.disconnected);
      timers.activeWithDelay(const Duration(seconds: 2)).fire();
      await _pumpAsync();
      expect(controller.state, RealtimeConnectionState.connected);

      expect(realtimeReconnectDelays, const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
        Duration(seconds: 30),
      ]);
    });
  });
}

Future<void> _pumpAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
