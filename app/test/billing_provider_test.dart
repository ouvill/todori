import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/billing/billing_store.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/screens/account_screen.dart';

import 'support/fake_bridge_service.dart';

void main() {
  test(
    'billing uses only the server-issued App User ID and server refresh',
    () async {
      final bridge = _BillingBridge();
      final store = _FakeBillingStore();
      final container = ProviderContainer(
        overrides: [
          bridgeServiceProvider.overrideWithValue(bridge),
          billingStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(accountProvider.notifier)
          .login(email: 'alice@example.com', password: 'correct password');

      final initial = await container.read(billingProvider.future);
      expect(initial?.entitlement.status, 'free');
      expect(store.configuredAppUserId, _appUserId);
      expect(store.configuredEnvironment, 'sandbox');
      expect(initial?.products.single.price, 'Localized monthly price');

      await container
          .read(billingProvider.notifier)
          .purchase('dev.todori.todori.pro.monthly');

      final active = container.read(billingProvider).value;
      expect(bridge.refreshCalls, 1);
      expect(active?.entitlement.status, 'active');
      expect(active?.entitlement.syncAllowed, isTrue);
    },
  );

  for (final outcome in [
    BillingPurchaseOutcome.cancelled,
    BillingPurchaseOutcome.pending,
    BillingPurchaseOutcome.failed,
  ]) {
    test(
      'purchase $outcome does not ask the server to trust a receipt',
      () async {
        final bridge = _BillingBridge();
        final store = _FakeBillingStore()..purchaseOutcome = outcome;
        final container = ProviderContainer(
          overrides: [
            bridgeServiceProvider.overrideWithValue(bridge),
            billingStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(container.dispose);
        await container
            .read(accountProvider.notifier)
            .login(email: 'alice@example.com', password: 'correct password');
        await container.read(billingProvider.future);

        await container
            .read(billingProvider.notifier)
            .purchase('dev.todori.todori.pro.monthly');

        final state = container.read(billingProvider).value!;
        expect(state.lastOutcome, outcome);
        expect(state.busy, isFalse);
        expect(state.entitlement.syncAllowed, isFalse);
        expect(bridge.refreshCalls, 0);
      },
    );
  }

  test('store exception becomes a recoverable failed outcome', () async {
    final bridge = _BillingBridge();
    final store = _FakeBillingStore()..throwOnPurchase = true;
    final container = ProviderContainer(
      overrides: [
        bridgeServiceProvider.overrideWithValue(bridge),
        billingStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(accountProvider.notifier)
        .login(email: 'alice@example.com', password: 'correct password');
    await container.read(billingProvider.future);

    await container
        .read(billingProvider.notifier)
        .purchase('dev.todori.todori.pro.monthly');

    final state = container.read(billingProvider).value!;
    expect(state.lastOutcome, BillingPurchaseOutcome.failed);
    expect(state.busy, isFalse);
    expect(bridge.refreshCalls, 0);
  });

  test('restore activates UI only after a fresh server snapshot', () async {
    final bridge = _BillingBridge();
    final store = _FakeBillingStore();
    final container = ProviderContainer(
      overrides: [
        bridgeServiceProvider.overrideWithValue(bridge),
        billingStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(accountProvider.notifier)
        .login(email: 'alice@example.com', password: 'correct password');
    await container.read(billingProvider.future);

    await container.read(billingProvider.notifier).restore();

    expect(bridge.refreshCalls, 1);
    expect(
      container.read(billingProvider).value?.entitlement.syncAllowed,
      isTrue,
    );
  });

  test(
    'bootstrap failure falls back to the display-only cached snapshot',
    () async {
      final bridge = _BillingBridge()
        ..failBootstrap = true
        ..cachedState = _billingState(
          status: 'in_grace_period',
          syncAllowed: true,
        );
      final store = _FakeBillingStore();
      final container = ProviderContainer(
        overrides: [
          bridgeServiceProvider.overrideWithValue(bridge),
          billingStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(accountProvider.notifier)
          .login(email: 'alice@example.com', password: 'correct password');

      final cached = await container.read(billingProvider.future);

      expect(cached?.entitlement.status, 'in_grace_period');
      expect(cached?.entitlement.syncAllowed, isTrue);
      expect(cached?.products, isEmpty);
      expect(store.configuredAppUserId, isNull);
    },
  );

  testWidgets('Pro section is localized and remains readable at large type', (
    tester,
  ) async {
    final bridge = _BillingBridge();
    final store = _FakeBillingStore();
    await bridge.accountLogin(
      email: 'alice@example.com',
      password: 'correct password',
    );
    tester.platformDispatcher.localeTestValue = const Locale('ja');
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.platformDispatcher.clearLocaleTestValue();
      tester.platformDispatcher.clearLocalesTestValue();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeServiceProvider.overrideWithValue(bridge),
          billingStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pro'), findsOneWidget);
    expect(
      find.text(
        'ProではE2EE同期と暗号化クラウドバックアップを利用できます。Appleのサブスクリプション画面からいつでも解約できます。',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('トライアル'), findsNothing);
    expect(find.text('月額'), findsOneWidget);
    expect(find.text('Localized monthly price'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.semantics.byPredicate((node) {
        final label = node.getSemanticsData().label;
        return label.contains('月額') &&
            label.contains('Localized monthly price') &&
            !label.contains('トライアル');
      }),
      findsWidgets,
    );
    final purchaseSemantics = tester.getSemantics(
      find.widgetWithText(FilledButton, 'Proを始める'),
    );
    final purchaseSemanticsData = purchaseSemantics.getSemanticsData();
    expect(purchaseSemanticsData.label, 'Proを始める');
    expect(purchaseSemanticsData.flagsCollection.isButton, isTrue);
    expect(purchaseSemanticsData.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}

const _appUserId = '00000000-0000-4000-8000-000000000001';

BillingStateDto _billingState({
  String status = 'free',
  bool syncAllowed = false,
}) => BillingStateDto(
  provider: 'revenuecat',
  providerAppUserId: _appUserId,
  lookupKey: 'pro',
  status: status,
  syncAllowed: syncAllowed,
  storeProductIdentifier: syncAllowed ? 'dev.todori.todori.pro.monthly' : null,
  willRenew: syncAllowed,
  environment: 'sandbox',
);

class _BillingBridge extends FakeBridgeService {
  int refreshCalls = 0;
  bool failBootstrap = false;
  BillingStateDto? cachedState;

  @override
  Future<BillingStateDto> billingBootstrap() async {
    if (failBootstrap) throw StateError('billing bootstrap unavailable');
    return _billingState();
  }

  @override
  Future<BillingStateDto?> getCachedBilling() async =>
      cachedState ?? _billingState();

  @override
  Future<BillingStateDto> refreshBilling() async {
    refreshCalls += 1;
    return _billingState(status: 'active', syncAllowed: true);
  }
}

class _FakeBillingStore implements BillingStore {
  String? configuredAppUserId;
  String? configuredEnvironment;
  BillingPurchaseOutcome purchaseOutcome = BillingPurchaseOutcome.purchased;
  bool throwOnPurchase = false;

  @override
  Future<void> configure({
    required String appUserId,
    required String environment,
  }) async {
    configuredAppUserId = appUserId;
    configuredEnvironment = environment;
  }

  @override
  Future<List<BillingProduct>> products() async => const [
    BillingProduct(
      identifier: 'dev.todori.todori.pro.monthly',
      title: 'Todori Pro Monthly',
      description: 'Monthly Pro',
      price: 'Localized monthly price',
      isAnnual: false,
    ),
  ];

  @override
  Future<BillingPurchaseOutcome> purchase(String productIdentifier) async {
    if (throwOnPurchase) throw StateError('store unavailable');
    return purchaseOutcome;
  }

  @override
  Future<BillingPurchaseOutcome> restore() async =>
      BillingPurchaseOutcome.purchased;

  @override
  Future<Uri?> managementUrl() async =>
      Uri.parse('https://apps.apple.com/account/subscriptions');

  @override
  Future<void> accountLoggedOut() async {}
}
