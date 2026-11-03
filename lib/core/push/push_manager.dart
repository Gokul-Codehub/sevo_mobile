import '../../features/booking/domain/booking_providers.dart' show myBookingsProvider;
import '../../features/notifications/domain/notification_providers.dart' show notificationsControllerProvider;
import '../navigation/web_link_mapper.dart';
import '../../features/app_update/domain/store_info.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/app_update/data/app_version_repository.dart' show InstalledAppReader;
import '../../features/app_update/domain/app_update_controller.dart'
    show appUpdateControllerProvider, appUpdateStoreProvider, installedAppReaderProvider;
import '../../features/app_update/domain/app_update_models.dart' show CheckReason;
import '../../features/auth/domain/auth_notifier.dart' show authProvider;
import '../../features/booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../routing/app_router.dart' show rootNavigatorKey;
import '../foundation/foundation_repository.dart' show FoundationRepository;
import '../network/api_client.dart' show apiClientProvider;
import '../network/session_interceptors.dart' show SessionNotice;
import '../storage/secure_storage.dart' show secureStorageProvider;
import '../services/notification_service.dart';
import '../navigation/pending_link.dart';
import '../utils/app_logger.dart';
import 'device_facts.dart';
import 'push_messaging.dart';

/// `POST/PATCH /api/app/devices/` - tells the server this install and its push token.
class PushRepository {
  PushRepository({required this.api, this.installId, this.appKey = 'customer'});
  final dynamic api; // ApiClient (dynamic keeps tests light)
  final Future<String?> Function()? installId;
  final String appKey;

  static final _opts = Options(
    sendTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    extra: {'skipRetry': true},
  );

  Future<bool> register({
    required String? token,
    required bool notificationsEnabled,
    required String version,
    required int build,
    DeviceFacts facts = const DeviceFacts(),
  }) async {
    try {
      final id = await installId?.call();
      if (id == null || id.isEmpty) return false;
      await api.post('/app/devices/', data: {
        'device_id': id,
        'app_key': appKey,
        'platform': FoundationRepository.platformName,
        'app_version': version,
        'build': build,
        'notifications_enabled': notificationsEnabled,
        if (facts.model.isNotEmpty) 'model': facts.model,
        if (facts.osVersion.isNotEmpty) 'os_version': facts.osVersion,
        if (token != null && token.isNotEmpty) 'fcm_token': token,
      }, options: _opts);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Logout: the phone stops receiving the previous user's pushes.
  Future<bool> detachUser() async {
    try {
      final id = await installId?.call();
      if (id == null || id.isEmpty) return false;
      await api.patch('/app/devices/$id/', data: {'detach_user': true}, options: _opts);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Starts Firebase safely, keeps the server informed of this device's push token, and turns
/// incoming / tapped pushes into app actions. Every failure leaves the app working: push is
/// an addition, never a requirement.
class PushManager {
  PushManager({
    required PushMessaging messaging,
    required PushRepository repository,
    required InstalledAppReader installedReader,
    required this.onAppUpdate,
    required this.onNavigate,
    required this.showLocal,
    this.onInboxChanged,
    this.onForceLogout,
    DeviceFactsReader? deviceFacts,
  })  : _messaging = messaging,
        _repo = repository,
        _reader = installedReader,
        _facts = deviceFacts ?? const DeviceInfoFactsReader();

  final PushMessaging _messaging;
  final PushRepository _repo;
  final InstalledAppReader _reader;
  final DeviceFactsReader _facts;
  final void Function() onAppUpdate;
  final void Function(String route) onNavigate;
  final Future<void> Function(String title, String body, String? route, String? eventKey) showLocal;

  /// A push arrived while the app is open: refresh the notification list / bookings so they are up to date.
  final void Function()? onInboxChanged;

  /// The server signed this phone out (admin or another device): clear the session and go to login.
  final void Function()? onForceLogout;

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _started = false;
  bool available = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    available = await _messaging.initialize();
    if (!available) {
      // Push is off, but the device is still listed for admins (no token, notifications not allowed).
      AppLogger.d('[PUSH]', 'Firebase unavailable - push disabled');
      await _register();
      return;
    }
    _subs
      ..add(_messaging.tokenRefresh.listen((_) => unawaited(_register()), onError: (_) {}))
      ..add(_messaging.onForegroundMessage.listen(_onForeground, onError: (_) {}))
      ..add(_messaging.onMessageOpenedApp.listen(handleTap, onError: (_) {}));
    await _register();
    final initial = await _messaging.initialMessage();
    if (initial != null) handleTap(initial);
  }

  Future<void> _register() async {
    try {
      final token = available ? await _messaging.getToken() : null;
      final allowed = available ? await _messaging.notificationsAllowed() : false;
      final installed = await _reader.read();
      final facts = await _facts.read();
      final ok = await _repo.register(
        token: token,
        notificationsEnabled: allowed,
        version: installed.versionName,
        build: installed.buildNumber,
        facts: facts,
      );
      // Debug builds only (AppLogger.d prints nothing in release): lets a developer check push from Logcat
      // and paste the token into Firebase Console > Messaging > "Send test message".
      AppLogger.d('[PUSH]', 'registered=$ok permission=$allowed firebase=$available model=${facts.model}');
      AppLogger.d('[PUSH]', 'fcm_token=${token ?? "none"}');
    } catch (_) {}
  }

  /// After sign-in: links the device to the user and refreshes the permission state.
  Future<void> onSignedIn() => _register();

  Future<void> onSignedOut() async {
    await _repo.detachUser();
  }

  void _onForeground(PushMessage m) {
    if (m.type == 'force_logout') {
      onForceLogout?.call();
      return;
    }
    if (m.type == 'APP_UPDATE') {
      onAppUpdate(); // the update dialog appears in the app; no duplicate system notification
      return;
    }
    final title = m.title, body = m.body;
    // On iOS the system already presented it (see FirebasePushMessaging); only Android needs a local notification.
    if (StoreInfo.isIos) return;
    onInboxChanged?.call();
    if (title != null && title.isNotEmpty) unawaited(showLocal(title, body ?? '', safeRoute(m.route), m.data['event_key']));
  }

  void handleTap(PushMessage m) {
    if (m.type == 'force_logout') {
      onForceLogout?.call();
      return;
    }
    if (m.type == 'APP_UPDATE') {
      onAppUpdate();
      return;
    }
    final route = appRouteFor(m.route);
    if (route != null) onNavigate(route);
  }

  /// App screens a push may open directly. Anything else is a WEBSITE path and goes through [resolveWebLink].
  static const _nativePrefixes = [
    '/bookings', '/track', '/support', '/notifications', '/my-payments', '/my-refunds', '/send-feedback', '/feedback',
    '/cart', '/grocery-orders', '/profile', '/devices', '/notification-settings', '/offers', '/categories', '/search',
  ];

  /// The app route to open for a push `route`: an app screen as-is, a website path mapped to its app screen,
  /// or null when there is no app screen for it.
  static String? appRouteFor(String? route) {
    final safe = safeRoute(route);
    if (safe == null) return null;
    final path = safe.split('?').first;
    // The website's public tracking link is /tracking/<token>; the app's tracking screen is /track/<token>.
    if (path.startsWith('/tracking/') && path.length > '/tracking/'.length) return '/track/${path.substring('/tracking/'.length)}';
    if (_nativePrefixes.any((p) => path == p || path.startsWith('$p/'))) return safe;
    return resolveWebLink(safe).route;
  }

  /// Only in-app paths: never a full URL or a protocol-relative link.
  static String? safeRoute(String? route) {
    if (route == null) return null;
    final r = route.trim();
    if (!r.startsWith('/') || r.startsWith('//') || r.contains('://') || r.contains(r'\')) return null;
    return r;
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

final pushMessagingProvider = Provider<PushMessaging>((ref) => const FirebasePushMessaging());

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => PushRepository(api: ref.watch(apiClientProvider), installId: ref.watch(appUpdateStoreProvider).installId),
);

final pushManagerProvider = Provider<PushManager>((ref) {
  final manager = PushManager(
    messaging: ref.watch(pushMessagingProvider),
    repository: ref.watch(pushRepositoryProvider),
    installedReader: ref.watch(installedAppReaderProvider),
    onAppUpdate: () => unawaited(ref.read(appUpdateControllerProvider.notifier).check(CheckReason.manual)),
    onNavigate: (route) {
      final context = rootNavigatorKey.currentContext;
      if (context == null) return;
      // Account-specific screens while signed out: sign in first, then continue to the screen.
      if (PendingLink.needsSignIn(route) && !ref.read(isUserAuthenticatedProvider)) {
        PendingLink.set(route);
        GoRouter.of(context).push('/login');
        return;
      }
      GoRouter.of(context).push(route);
    },
    showLocal: (title, body, route, eventKey) =>
        NotificationService.instance.show(title: title, body: body, routePayload: route, dedupeKey: eventKey),
    onInboxChanged: () {
      try {
        unawaited(ref.read(notificationsControllerProvider.notifier).refresh(silent: true));
        ref.invalidate(myBookingsProvider(null));
      } catch (_) {}
    },
    onForceLogout: () async {
      try {
        await ref.read(secureStorageProvider).clearAll();
      } catch (_) {}
      SessionNotice.message.value = SessionNotice.revoked;
      ref.read(authProvider.notifier).forceUnauthenticated();
    },
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Mounted once in main.dart: starts push in the background and follows sign-in / sign-out.
class PushGate extends ConsumerStatefulWidget {
  const PushGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PushGate> createState() => _PushGateState();
}

class _PushGateState extends ConsumerState<PushGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(pushManagerProvider).start());
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isUserAuthenticatedProvider, (previous, next) {
      final manager = ref.read(pushManagerProvider);
      if (next && previous != true) {
        unawaited(manager.onSignedIn());
        // Now that the customer has an account (so bookings and orders to be told about), ask to allow notifications.
        // A moment later, so it does not land on top of the sign-in screen's own transition.
        unawaited(Future<void>.delayed(const Duration(milliseconds: 1500), () => NotificationService.instance.requestPermission()));
        final pending = PendingLink.take();
        final context = rootNavigatorKey.currentContext;
        if (pending != null && context != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final c = rootNavigatorKey.currentContext;
            if (c != null) GoRouter.of(c).go(pending);
          });
        }
      }
      if (!next && previous == true) unawaited(manager.onSignedOut());
    });
    return widget.child;
  }
}
