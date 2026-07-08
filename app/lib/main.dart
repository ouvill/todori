import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:todori/src/core/bridge_service.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/notifications/reminder_notifications.dart';
import 'package:todori/src/router.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/rust/frb_generated.dart';
import 'package:todori/src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? initializationError;
  try {
    await RustLib.init();
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory('${supportDir.path}/todori-db');
    await dbDir.create(recursive: true);
    final defaultInboxName = lookupAppLocalizations(
      _resolveStartupLocale(PlatformDispatcher.instance.locale),
    ).defaultInboxName;
    await initCore(dbDir: dbDir.path, defaultInboxName: defaultInboxName);
    final startupL10n = lookupAppLocalizations(
      _resolveStartupLocale(PlatformDispatcher.instance.locale),
    );
    final notificationContent = ReminderNotificationContent(
      title: startupL10n.reminderNotificationTitle,
      body: startupL10n.reminderNotificationBody,
      snoozeActionTitle: startupL10n.reminderSnoozeOneHourAction,
    );
    final notificationService = ReminderNotificationService(
      bridge: const FrbBridgeService(),
      gateway: FlutterLocalReminderNotificationGateway(),
    );
    await notificationService.initialize(notificationContent);
    await notificationService.reschedulePending(notificationContent);
  } catch (error, stackTrace) {
    initializationError = error;
    debugPrint('Todori native core initialization failed: $error\n$stackTrace');
  }

  runApp(TodoriApp(initializationError: initializationError));
}

Locale _resolveStartupLocale(Locale platformLocale) {
  for (final supportedLocale in AppLocalizations.supportedLocales) {
    if (supportedLocale.languageCode == platformLocale.languageCode) {
      return supportedLocale;
    }
  }
  return AppLocalizations.supportedLocales.first;
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: buildTodoriTheme(Brightness.light),
        darkTheme: buildTodoriTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Builder(
                builder: (context) => Text(
                  AppLocalizations.of(
                    context,
                  )!.failedToStartTodori(error.toString()),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ProviderScope(
      overrides: overrides,
      child: _TodoriAppShell(router: router),
    );
  }
}

class _TodoriAppShell extends ConsumerStatefulWidget {
  const _TodoriAppShell({required this.router});

  final GoRouter router;

  @override
  ConsumerState<_TodoriAppShell> createState() => _TodoriAppShellState();
}

class _TodoriAppShellState extends ConsumerState<_TodoriAppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(syncStatusProvider.notifier).syncOnResume());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncStatusProvider);
    return MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: buildTodoriTheme(Brightness.light),
      darkTheme: buildTodoriTheme(Brightness.dark),
      routerConfig: widget.router,
    );
  }
}
