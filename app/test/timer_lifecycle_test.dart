import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/rust/api.dart';

import 'support/fake_bridge_service.dart';

void main() {
  testWidgets(
    'resume settlement failure is never an unhandled lifecycle error',
    (tester) async {
      final bridge = _FailingRestoreBridge();
      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(bridge)]),
      );
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(tester.takeException(), isNull);
    },
  );
}

class _FailingRestoreBridge extends FakeBridgeService {
  @override
  Future<ActiveTimerSessionDto?> getActiveTimerSession() {
    throw StateError('simulated restore failure');
  }
}
