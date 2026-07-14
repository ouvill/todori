import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/providers.dart';

import 'support/fake_bridge_service.dart';
import 'support/fake_realtime.dart';

void main() {
  test('login and foreground own the socket lifecycle', () async {
    final bridge = FakeBridgeService();
    final timers = FakeRealtimeTimers();
    final connector = FakeRealtimeSocketConnector();
    final container = ProviderContainer(
      overrides: [
        bridgeServiceProvider.overrideWithValue(bridge),
        realtimeTimerFactoryProvider.overrideWithValue(timers.create),
        realtimeSocketConnectorProvider.overrideWithValue(connector),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      realtimeConnectionControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(container.read(realtimeConnectionControllerProvider), isNull);
    await container
        .read(accountProvider.notifier)
        .login(email: 'alice@example.com', password: 'correct password');
    await _pumpAsync();

    expect(container.read(realtimeConnectionControllerProvider), isNotNull);
    expect(bridge.realtimeTicketCalls, 1);
    expect(connector.sockets, hasLength(1));

    container.read(appForegroundProvider.notifier).setForeground(false);
    container.read(syncStatusProvider.notifier).setForeground(false);
    await _pumpAsync();
    expect(container.read(realtimeConnectionControllerProvider), isNull);
    expect(connector.sockets.first.closed, isTrue);

    container.read(appForegroundProvider.notifier).setForeground(true);
    await _pumpAsync();
    expect(bridge.realtimeTicketCalls, 2);
    expect(connector.sockets, hasLength(2));

    await container.read(accountProvider.notifier).logout();
    await _pumpAsync();
    expect(container.read(realtimeConnectionControllerProvider), isNull);
    expect(connector.sockets.last.closed, isTrue);
  });
}

Future<void> _pumpAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
