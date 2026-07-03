import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:todori/src/router.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? initializationError;
  try {
    await RustLib.init();
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory('${supportDir.path}/todori-db');
    await dbDir.create(recursive: true);
    await initCore(dbDir: dbDir.path);
  } catch (error) {
    initializationError = error;
  }

  runApp(TodoriApp(initializationError: initializationError));
}

/// Top-level app widget.
///
/// This is intentionally separate from the native-initialization logic in
/// [main] so widget tests can build it directly -- with a fake
/// `BridgeService` supplied via [overrides] -- without ever calling
/// `RustLib.init()`, touching the filesystem, or calling `initCore`.
class TodoriApp extends StatelessWidget {
  TodoriApp({
    super.key,
    this.initializationError,
    this.overrides = const [],
    GoRouter? router,
  }) : router = router ?? buildAppRouter();

  /// If non-null, [main] failed to initialize the native core; a minimal
  /// error screen is shown instead of the app so the failure is visible
  /// rather than silently unusable.
  final Object? initializationError;

  /// Riverpod provider overrides. Widget tests use this to replace
  /// [bridgeServiceProvider] with an in-memory fake.
  final List<Override> overrides;

  /// The go_router instance backing this app. Defaults to a freshly built
  /// router (see `src/router.dart`); tests may supply their own if needed.
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final error = initializationError;
    if (error != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to start Todori: $error'),
            ),
          ),
        ),
      );
    }

    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        title: 'Todori',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        routerConfig: router,
      ),
    );
  }
}
