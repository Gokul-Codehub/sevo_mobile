import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/booking_notification_watcher.dart';
import 'core/services/customer_notification_watcher.dart';
import 'core/utils/app_logger.dart';
import 'core/utils/restart_widget.dart';
import 'core/analytics/analytics_manager.dart';
import 'core/analytics/performance_monitor.dart';
import 'core/foundation/crash_reporting.dart';
import 'core/foundation/error_reporter.dart';
import 'core/foundation/foundation_gate.dart';
import 'core/push/push_manager.dart';
import 'features/app_update/presentation/app_update_gate.dart';
import 'routing/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/connectivity_gate.dart';
import 'shared/widgets/motion.dart';

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
      // Release: a friendly card (never a stack trace or a blank box). The error is queued and
      // reported to the server (ErrorReporter) when the connection allows.
      ErrorReporter.record(details.exception, screen: details.library ?? '');
      return const Material(
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFF0D253A)),
                SizedBox(height: 10),
                Text('Something went wrong here',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0D253A))),
                SizedBox(height: 6),
                Text('Please go back and try again. We have been notified.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.black54)),
              ],
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
    ErrorReporter.record(error, level: 'fatal');
    return false; // still forward to the default platform handler
  };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installDiagnosticErrorHandlers();
  // Crash reporting (Firebase Crashlytics): wraps the handlers above, in the background, never blocks start-up.
  unawaited(CrashReporting.instance.initFromPlatform());
  // Analytics + API performance (Firebase), also in the background; off in debug builds.
  unawaited(AnalyticsManager.instance.init().then((_) => AnalyticsManager.instance.track(AnalyticsEvents.appOpen)));
  unawaited(PerformanceMonitor.instance.init());

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
      scrollBehavior: const AppScrollBehavior(),
      routerConfig: router,
      // Mounted once, above every routed screen, so it keeps watching
      // booking status changes and posting real device notifications
      // (see BookingNotificationWatcher's doc comment) no matter which
      // screen the customer is currently on. ConnectivityGate wraps that in
      // turn so a dropped network connection overlays the branded "No
      // Internet" screen app-wide (see ConnectivityGate's doc comment)
      // instead of customers only discovering they're offline when an
      // individual screen's API call happens to fail.
      builder: (context, child) => ConnectivityGate(
        // App update management: optional prompt / mandatory update screen
        // (checked in the background; startup never waits on it).
        child: FoundationGate(
          // Server-driven config: maintenance mode, feature flags, remote settings.
          child: AppUpdateGate(
            // Push (Firebase): device token registration + update / booking notifications.
            child: PushGate(
              child: BookingNotificationWatcher(
                child: CustomerNotificationWatcher(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
