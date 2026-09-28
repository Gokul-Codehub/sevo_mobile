import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/booking_notification_watcher.dart';
import 'core/utils/app_logger.dart';
import 'core/utils/restart_widget.dart';
import 'routing/app_router.dart';
import 'shared/theme/app_theme.dart';

/// P0 DIAGNOSTIC INSTRUMENTATION — see docs/CalServices_Cart_Catalog_RootCause_Audit.md
///
/// The reported bug ("category list goes blank after adding a cart item, only
/// the AppBar renders") is consistent with a widget subtree throwing during
/// build and Flutter's *default* ErrorWidget swallowing the exception into a
/// blank/grey box in release builds (this only shows visible red error text
/// in debug mode, by default).
///
/// This override makes that failure VISIBLE instead of blank, in every build
/// mode, so the next reproduction tells us exactly what threw and where —
/// instead of guessing. It does not change app logic, does not catch/hide
/// anything that was previously working, and does not alter what data is
/// fetched or displayed when there is no error. It is intentionally loud:
/// once we have a real stack trace from the device we can fix the actual
/// throwing line and remove this (or leave it, since surfacing build errors
/// instead of blank boxes is strictly better than the framework default).
void _installDiagnosticErrorHandlers() {
  final defaultBuilder = ErrorWidget.builder;
  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLogger.d('[P0-CRASH]', 'Widget build threw: ${details.exceptionAsString()}');
    AppLogger.d('[P0-CRASH]', 'Library: ${details.library}, context: ${details.context}');
    if (kReleaseMode) {
      // In release mode, show the real error instead of a blank box so it
      // can be screenshotted and reported — never silently blank.
      return Material(
        color: const Color(0xFFFFF3F3),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Text(
              'Screen error (please screenshot this):\n\n'
              '${details.exceptionAsString()}',
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 12),
            ),
          ),
        ),
      );
    }
    return defaultBuilder(details);
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.d('[P0-CRASH]', 'FlutterError: ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.d('[P0-CRASH]', 'Uncaught async error: $error');
    return false; // still forward to the default platform handler
  };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installDiagnosticErrorHandlers();

  // Lock to portrait orientation for mobile
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const RestartWidget(
      child: ProviderScope(
        child: CalServicesApp(),
      ),
    ),
  );
}

class CalServicesApp extends ConsumerWidget {
  const CalServicesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'SEVO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      // Mounted once, above every routed screen, so it keeps watching
      // booking status changes and posting real device notifications
      // (see BookingNotificationWatcher's doc comment) no matter which
      // screen the customer is currently on.
      builder: (context, child) =>
          BookingNotificationWatcher(child: child ?? const SizedBox.shrink()),
    );
  }
}
