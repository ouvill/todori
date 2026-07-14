import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/realtime_sync.dart';

import 'support/fake_realtime.dart';

void main() {
  test(
    'mutation commit reaches remote sync start in deterministic 500ms',
    () async {
      var now = DateTime.utc(2026, 7, 15);
      final sourceTimers = FakeRealtimeTimers();
      final remoteTimers = FakeRealtimeTimers();
      final connector = FakeRealtimeSocketConnector();
      final observations = <RealtimeObservation>[];
      var mutationCommitted = false;
      var sourceRuns = 0;
      var remoteRuns = 0;
      DateTime? remoteStartedAt;

      late final RealtimeSyncScheduler remoteScheduler;
      remoteScheduler = RealtimeSyncScheduler(
        runSync: () async {
          remoteRuns += 1;
          remoteStartedAt = now;
        },
        timerFactory: remoteTimers.create,
        observer: observations.add,
        now: () => now,
      );
      final controller = RealtimeConnectionController(
        fetchTicket: () async => RealtimeTicketView(
          websocketUrl: 'wss://realtime.example/v1/connect',
          ticket: 'public-test-ticket',
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
        connector: connector,
        onChanged: () =>
            remoteScheduler.trigger(RealtimeTriggerKind.remoteHint),
        onConnectionChanged: remoteScheduler.setConnected,
        timerFactory: remoteTimers.create,
        observer: observations.add,
        now: () => now,
        jitter: () => 0,
      );
      final sourceScheduler = RealtimeSyncScheduler(
        runSync: () async {
          sourceRuns += 1;
          if (mutationCommitted) {
            final socket = connector.sockets.single;
            // Fixed frames carry no ordering state. Repeated delivery therefore
            // models duplicate, delayed, and out-of-order wake-up hints alike.
            socket.add('{"v":1,"type":"changed"}');
            socket.add('{"v":1,"type":"changed"}');
            socket.add('{"v":1,"type":"changed"}');
          }
        },
        timerFactory: sourceTimers.create,
        observer: observations.add,
        now: () => now,
      );
      addTearDown(sourceScheduler.dispose);
      addTearDown(remoteScheduler.dispose);
      addTearDown(controller.dispose);

      remoteScheduler.setEnabled(true);
      sourceScheduler.setEnabled(true);
      await controller.start();
      await _pumpAsync();
      sourceRuns = 0;
      remoteRuns = 0;
      remoteStartedAt = null;
      observations.clear();

      final committedAt = now;
      mutationCommitted = true;
      sourceScheduler.trigger();
      now = now.add(realtimeMutationDebounce);
      sourceTimers.activeWithDelay(realtimeMutationDebounce).fire();
      await _pumpAsync();

      expect(remoteTimers.activeWithDelay(realtimeMutationDebounce), isNotNull);
      now = now.add(realtimeMutationDebounce);
      remoteTimers.activeWithDelay(realtimeMutationDebounce).fire();
      await _pumpAsync();

      expect(sourceRuns, 1);
      expect(remoteRuns, 1);
      expect(remoteStartedAt, isNotNull);
      final latency = remoteStartedAt!.difference(committedAt);
      expect(latency, const Duration(milliseconds: 500));
      expect(latency, lessThan(const Duration(seconds: 2)));

      final remoteStart = observations.lastWhere(
        (observation) =>
            observation.event == RealtimeEvent.syncStarted &&
            observation.connectionState == 'connected',
      );
      expect(remoteStart.latencyMs, 250);
      expect(remoteStart.triggerKind, RealtimeTriggerKind.remoteHint);
    },
  );

  test(
    'socket outage preserves local sync, fallback poll, and resume sync',
    () async {
      var now = DateTime.utc(2026, 7, 15);
      final timers = FakeRealtimeTimers();
      final connector = FakeRealtimeSocketConnector()..failuresRemaining = 10;
      var localMutationCommitted = false;
      var syncRuns = 0;
      final scheduler = RealtimeSyncScheduler(
        runSync: () async {
          syncRuns += 1;
        },
        timerFactory: timers.create,
        now: () => now,
      );
      final controller = RealtimeConnectionController(
        fetchTicket: () async => RealtimeTicketView(
          websocketUrl: 'wss://realtime.example/v1/connect',
          ticket: 'public-test-ticket',
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
        connector: connector,
        onChanged: scheduler.trigger,
        onConnectionChanged: scheduler.setConnected,
        timerFactory: timers.create,
        now: () => now,
        jitter: () => 0,
      );
      addTearDown(scheduler.dispose);
      addTearDown(controller.dispose);

      scheduler.setEnabled(true);
      await controller.start();
      await _pumpAsync();
      syncRuns = 0;

      localMutationCommitted = true;
      scheduler.trigger();
      now = now.add(realtimeMutationDebounce);
      timers.activeWithDelay(realtimeMutationDebounce).fire();
      await _pumpAsync();
      expect(localMutationCommitted, isTrue);
      expect(syncRuns, 1);
      expect(scheduler.isConnected, isFalse);

      now = now.add(realtimeDisconnectedPolling);
      timers.activeWithDelay(realtimeDisconnectedPolling).fire();
      await _pumpAsync();
      expect(syncRuns, 2);

      scheduler.setForeground(false);
      scheduler.setForeground(true);
      await scheduler.syncNow();
      expect(syncRuns, 3);
    },
  );

  test('structured observations expose only the public metric allowlist', () {
    final observations = <RealtimeObservation>[
      const RealtimeObservation(RealtimeEvent.connectionFailed),
      const RealtimeObservation(
        RealtimeEvent.syncStarted,
        connectionState: 'disconnected',
        latencyMs: 250,
        triggerKind: RealtimeTriggerKind.remoteHint,
      ),
    ];
    for (final observation in observations) {
      expect(
        observation.toJson().keys,
        everyElement(
          isIn(<String>{
            'event',
            'connection_state',
            'latency_ms',
            'trigger_kind',
          }),
        ),
      );
      final serialized = jsonEncode(observation.toJson());
      for (final forbidden in <String>[
        'public-test-ticket',
        'tenant_id',
        'device_id',
        'channel',
        'record',
        'websocket_url',
      ]) {
        expect(serialized, isNot(contains(forbidden)));
      }
    }
  });
}

Future<void> _pumpAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
