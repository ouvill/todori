import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/screens/account_screen.dart';

import 'support/fake_bridge_service.dart';

Future<void> _pumpAccountScreen(
  WidgetTester tester,
  FakeBridgeService fake,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AccountScreen(key: UniqueKey()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(1), 'alice@example.com');
  await tester.enterText(find.byType(TextField).at(2), 'correct password');
}

void main() {
  testWidgets('shows signed-out account form', (tester) async {
    final fake = FakeBridgeService();
    await _pumpAccountScreen(tester, fake);

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Register'), findsOneWidget);
  });

  testWidgets('saves sync server URL', (tester) async {
    final fake = FakeBridgeService();
    await _pumpAccountScreen(tester, fake);

    await tester.enterText(
      find.byType(TextField).first,
      'http://127.0.0.1:4000',
    );
    await tester.tap(find.byTooltip('Save server URL'));
    await tester.pumpAndSettle();

    expect(await fake.getSyncServerUrl(), 'http://127.0.0.1:4000');
  });

  testWidgets('register shows recovery key once', (tester) async {
    final fake = FakeBridgeService();
    await _pumpAccountScreen(tester, fake);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    await _enterCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('account-recovery-key')), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);

    await _pumpAccountScreen(tester, fake);

    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-recovery-key')), findsNothing);
  });

  testWidgets('login shows email and logout returns to signed-out form', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await _pumpAccountScreen(tester, fake);

    await _enterCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('alice@example.com'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Log out'), findsNothing);
  });
}
