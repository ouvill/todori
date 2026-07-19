import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskveil/src/timer/timer_notifications.dart';

void main() {
  test(
    'Timer adapter never reinitializes the shared notification plugin',
    () async {
      final gateway = FlutterLocalTimerNotificationGateway(
        plugin: FlutterLocalNotificationsPlugin(),
      );

      await expectLater(gateway.initialize(), completes);
    },
  );

  test('Timer payload rejects reminder and malformed ownership', () {
    expect(TimerNotificationPayload.decode(null), isNull);
    expect(
      TimerNotificationPayload.decode(
        '{"owner":"taskveil_reminder_v1","sessionId":"session"}',
      ),
      isNull,
    );
    expect(TimerNotificationPayload.decode('{'), isNull);
  });
}
