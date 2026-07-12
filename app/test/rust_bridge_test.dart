import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        'rust/target/release/libtodori_app_bridge.dylib',
      ),
    );
  });

  tearDownAll(RustLib.dispose);

  test('greet calls Rust through flutter_rust_bridge', () async {
    final message = await greet(name: 'Todori');

    expect(message, 'Hello Todori from todori-core');
  });

  test('createDraftTask returns a todori-domain task JSON string', () async {
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
