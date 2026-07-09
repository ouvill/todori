import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/providers.dart';

import 'support/fake_bridge_service.dart';

void main() {
  test('sync provider stays idle when signed out', () async {
    final fake = FakeBridgeService();
    final container = ProviderContainer(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    final status = await container.read(syncStatusProvider.future);

    expect(status.loggedIn, isFalse);
    expect(fake.syncNowCalls, 0);
  });

  test('sync provider triggers after login and foreground resume', () async {
    final fake = FakeBridgeService();
    final container = ProviderContainer(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(accountProvider.notifier)
        .login(email: 'alice@example.com', password: 'correct password');
    await container.read(syncStatusProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(fake.syncNowCalls, greaterThanOrEqualTo(1));
    final callsAfterLogin = fake.syncNowCalls;

    await container.read(syncStatusProvider.notifier).syncOnResume();

    expect(fake.syncNowCalls, greaterThan(callsAfterLogin));
  });

  test('sync now refreshes list-scoped tasks', () async {
    final fake = FakeBridgeService();
    final container = ProviderContainer(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(accountProvider.notifier)
        .login(email: 'alice@example.com', password: 'correct password');
    final list = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    expect(await container.read(tasksProvider(list.id).future), isEmpty);

    fake.addRemoteTaskForNextSync(
      listId: list.id,
      title: 'Pulled task without due date',
    );
    await container.read(syncStatusProvider.notifier).syncNow();

    final tasks = await container.read(tasksProvider(list.id).future);
    expect(
      tasks.map((task) => task.title),
      contains('Pulled task without due date'),
    );
  });
}
