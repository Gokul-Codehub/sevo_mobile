import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/navigation/web_link_mapper.dart';
import '../../booking/domain/cart_notifier.dart';
import '../../catalog/domain/catalog_providers.dart';
import '../../home/domain/home_flow_mode.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/local_inbox_store.dart';
import '../data/notification_repository.dart';
import 'capacity_claim.dart';
import 'notification_models.dart';

/// The inbox as the bell and the notifications screen see it.
class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.loadedOnce = false,
    this.error,
  });

  final List<CustomerNotification> items;
  final int unreadCount;
  final bool isLoading;
  final bool loadedOnce;
  final String? error;

  NotificationsState copyWith({
    List<CustomerNotification>? items,
    int? unreadCount,
    bool? isLoading,
    bool? loadedOnce,
    String? error,
    bool clearError = false,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        isLoading: isLoading ?? this.isLoading,
        loadedOnce: loadedOnce ?? this.loadedOnce,
        error: clearError ? null : (error ?? this.error),
      );
}

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(
    this._repo, {
    required this.signedIn,
    this.userId,
    LocalInboxStore store = const LocalInboxStore(),
  })  : _store = store,
        super(const NotificationsState()) {
    if (signedIn) {
      _loadLocal().then((_) => refresh());
    }
  }

  final NotificationRepository _repo;
  final LocalInboxStore _store;
  final bool signedIn;
  final int? userId;

  /// Rows the server returned (the source of truth) ...
  List<CustomerNotification> _server = const [];
  int _serverUnread = 0;

  /// ... and alerts this phone showed itself (kept as a fallback history).
  List<CustomerNotification> _local = const [];

  /// A local row and a server row with the same title this close in time are
  /// the same event, so only one is shown.
  static const _sameEventWindow = Duration(minutes: 20);

  bool _dupOfServer(CustomerNotification l) => _server.any(
        (s) => s.title == l.title && s.createdAt.difference(l.createdAt).abs() < _sameEventWindow,
      );

  void _publish({bool? isLoading, bool? loadedOnce, String? error, bool clearError = false}) {
    if (!mounted) return;
    final visibleLocal = _local.where((l) => !_dupOfServer(l)).toList();
    final items = [..._server, ...visibleLocal]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final unread = _serverUnread + visibleLocal.where((n) => !n.isRead).length;
    state = state.copyWith(
      items: items,
      unreadCount: unread,
      isLoading: isLoading,
      loadedOnce: loadedOnce,
      error: error,
      clearError: clearError,
    );
  }

  Future<void> _loadLocal() async {
    final uid = userId;
    if (uid == null) return;
    final saved = await _store.load(uid);
    if (!mounted) return;
    _local = saved;
    if (_local.isNotEmpty) _publish();
  }

  void _saveLocal() {
    final uid = userId;
    if (uid != null) _store.save(uid, _local);
  }

  /// True when an alert with this [title] was already recorded recently --
  /// by this phone ([localOnly]) or by the server too. Lets the two alert
  /// watchers avoid showing the same event twice.
  bool hasRecent(String title, {bool localOnly = false}) {
    final now = DateTime.now();
    bool match(CustomerNotification n) =>
        n.title == title && now.difference(n.createdAt).abs() < _sameEventWindow;
    return _local.any(match) || (!localOnly && _server.any(match));
  }

  /// Records an alert this phone just showed, so it stays in the inbox.
  void addLocal({required String title, required String body, String category = 'BOOKING'}) {
    if (!signedIn || userId == null || !mounted) return;
    final now = DateTime.now();
    final entry = CustomerNotification(
      id: -(now.millisecondsSinceEpoch),
      eventKey: 'local:${now.millisecondsSinceEpoch}',
      category: category,
      level: title.contains('Cancel') ? 'WARNING' : 'INFO',
      title: title,
      body: body,
      deepLink: '/bookings',
      actionLabel: '',
      actionUrl: '',
      isRead: false,
      requiresAction: false,
      createdAt: now,
    );
    _local = [entry, ..._local].take(LocalInboxStore.maxItems).toList();
    _saveLocal();
    _publish();
  }

  /// Re-reads the inbox. [silent] keeps the current list on screen (no spinner)
  /// -- used by the background poll.
  Future<void> refresh({bool silent = false}) async {
    if (!signedIn || !mounted) return;
    if (!silent) _publish(isLoading: true, clearError: true);
    final result = await _repo.getNotifications();
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        _server = data.items;
        _serverUnread = data.unreadCount;
        _publish(isLoading: false, loadedOnce: true, clearError: true);
      case Failure(:final error):
        _publish(
          isLoading: false,
          loadedOnce: true,
          error: silent && state.items.isNotEmpty ? null : error.message,
        );
    }
  }

  /// Marks one read right away on screen, then tells the server (rolled back
  /// by the next refresh if that fails). Rows kept only on this phone (negative
  /// id) are updated locally.
  Future<void> markRead(int id) async {
    if (id < 0) {
      _local = [for (final n in _local) n.id == id ? n.copyWith(isRead: true) : n];
      _saveLocal();
      _publish();
      return;
    }
    final target = _server.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;
    _server = [for (final n in _server) n.id == id ? n.copyWith(isRead: true) : n];
    _serverUnread = (_serverUnread - 1).clamp(0, 1 << 30);
    _publish();
    final result = await _repo.markRead(id);
    if (result is Failure) refresh(silent: true);
  }

  Future<void> markAllRead() async {
    final unread = _server.where((n) => !n.isRead).map((n) => n.id).toList();
    final hadLocalUnread = _local.any((n) => !n.isRead);
    if (unread.isEmpty && !hadLocalUnread) return;
    _server = [for (final n in _server) n.copyWith(isRead: true)];
    _serverUnread = 0;
    _local = [for (final n in _local) n.copyWith(isRead: true)];
    _saveLocal();
    _publish();
    if (unread.isEmpty) return;
    // There is no bulk endpoint; the inbox is small (<= 50), so mark each.
    await Future.wait(unread.map(_repo.markRead));
    refresh(silent: true);
  }
}

/// Recreated whenever the customer signs in or out, so one account never sees
/// another's inbox and a guest has none.
final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
  final signedIn = ref.watch(isUserAuthenticatedProvider);
  final userId = ref.watch(currentUserProvider)?.id;
  return NotificationsController(
    ref.watch(notificationRepositoryProvider),
    signedIn: signedIn,
    userId: userId,
  );
});

final unreadNotificationCountProvider =
    Provider<int>((ref) => ref.watch(notificationsControllerProvider).unreadCount);

// ── Opening a notification's link ───────────────────────────────────────────

/// Opens the page a notification (or its action button) points to: maps the
/// web path onto an app screen, holds a capacity claim if the link carries one
/// and marks the notification read. Returns false when it had nowhere to go.
Future<bool> openNotificationLink(
  WidgetRef ref,
  BuildContext context,
  String rawUrl, {
  DateTime? claimExpiresAt,
}) async {
  final known = ref.read(categoriesProvider).valueOrNull?.map((c) => c.slug).toSet();
  final link = resolveWebLink(rawUrl, knownCategorySlugs: known);

  if (link.external != null) {
    await launchUrl(link.external!, mode: LaunchMode.externalApplication);
    return true;
  }
  if (link.claimToken != null) {
    ref.read(capacityClaimProvider.notifier).state = CapacityClaim(
      token: link.claimToken!,
      serviceSlug: link.claimServiceSlug,
      expiresAt: claimExpiresAt,
    );
  }
  if (!context.mounted) return false;
  if (link.groceriesHome) {
    ref.read(homeFlowModeProvider.notifier).state = HomeFlowMode.groceries;
    GoRouter.of(context).go('/');
    return true;
  }
  if (link.route != null) {
    GoRouter.of(context).push(link.route!);
    return true;
  }
  return false;
}
