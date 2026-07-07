import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/providers.dart';

import 'support/fake_bridge_service.dart';

void main() {
  test('uiModeProvider defaults to simple when unset', () async {
    final fake = FakeBridgeService();
    final container = ProviderContainer(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(await container.read(uiModeProvider.future), defaultUiMode);
  });

  test(
    'uiModeProvider persists and reloads reserved ui_mode setting',
    () async {
      final fake = FakeBridgeService();
      final container = ProviderContainer(
        overrides: [bridgeServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(uiModeProvider.notifier).setUiMode(advancedUiMode);

      expect(await fake.getSetting(key: uiModeSettingKey), advancedUiMode);
      expect(await container.read(uiModeProvider.future), advancedUiMode);
    },
  );

  test('SettingsRepository rejects unsupported UI modes', () async {
    final fake = FakeBridgeService();
    final repository = SettingsRepository(fake);

    expect(
      () => repository.setUiMode('unsupported'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
