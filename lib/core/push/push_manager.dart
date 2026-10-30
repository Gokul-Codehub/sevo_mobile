import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/app_update/data/app_version_repository.dart' show InstalledAppReader;
import '../../features/app_update/domain/app_update_controller.dart'
    show appUpdateControllerProvider, appUpdateStoreProvider, installedAppReaderProvider;
import '../../features/app_update/domain/app_update_models.dart' show CheckReason;
import '../../features/booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../routing/app_router.dart' show rootNavigatorKey;
import '../foundation/foundation_repository.dart' show FoundationRepository;
import '../network/api_client.dart' show apiClientProvider;
import '../services/notification_service.dart';
import '../utils/app_logger.dart';
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

  Future<bool> register({required String? token, required bool notificationsEnabled, required String version, required int build}) async {
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
  })  : _messaging = messaging,
        _repo = repository,
        _reader = installedReader;

  final PushMessaging _messaging;
  final PushRepository _repo;
  final InstalledAppReader _reader;
  final void Function() onAppUpdate;
  final void Function(String route) onNavigate;
  final Future<void> Function(String title, String body, String? route) showLocal;

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _started = false;
  bool available = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    available = await _messaging.initialize();
    if (!available) {
      AppLogger.d('[PUSH]', 'Firebase unavailable - push disabled');
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
      final token = await _messaging.getToken();
      final allowed = await _messaging.notificationsAllowed();
      final installed = await _reader.read();
      await _repo.register(token: token, notificationsEnabled: allowed, version: installed.versionName, build: installed.buildNumber);
    } catch (_) {}
  }

  /// After sign-in: links the device to the user and refreshes the permission state.
  Future<void> onSignedIn() async {
    if (available) await _register();
  }

  Future<void> onSignedOut() async {
    if (available) await _repo.detachUser();
  }

  void _onForeground(PushMessage m) {
    if (m.type == 'APP_UPDATE') {
      onAppUpdate(); // the update dialog appears in the app; no duplicate system notification
      return;
    }
    final title = m.title, body = m.body;
    if (title != null && title.isNotEmpty) unawaited(showLocal(title, body ?? '', safeRoute(m.route)));
  }

  void handleTap(PushMessage m) {
    if (m.type == 'APP_UPDATE') {
      onAppUpdate();
      return;
    }
    final route = safeRoute(m.route);
    if (route != null) onNavigate(route);
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
      if (context != null) GoRouter.of(context).push(route);
    },
    showLocal: (title, body, route) => NotificationService.instance.show(title: title, body: body, routePayload: route),
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
      if (next && previous != true) unawaited(manager.onSignedIn());
      if (!next && previous == true) unawaited(manager.onSignedOut());
    });
    return widget.child;
  }
}
