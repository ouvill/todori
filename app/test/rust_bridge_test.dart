import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:taskveil/src/rust/api.dart';
import 'package:taskveil/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        'rust/target/release/libtaskveil_app_bridge.dylib',
      ),
    );
  });

  tearDownAll(RustLib.dispose);

  test('greet calls Rust through flutter_rust_bridge', () async {
    final message = await greet(name: 'Taskveil');

    expect(message, 'Hello Taskveil from taskveil-core');
  });

  test('createDraftTask returns a taskveil-domain task JSON string', () async {
    final json = await createDraftTask(title: 'Write bridge test');
    final task = jsonDecode(json) as Map<String, Object?>;

    expect(task['title'], 'Write bridge test');
    expect(task['status'], 'todo');
    expect(task['note'], '');
    expect(task['sort_order'], 'a0');
    expect(task['id'], isA<String>());
    expect(task['list_id'], isA<String>());
  });
}
