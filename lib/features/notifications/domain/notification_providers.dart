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
  NotificationsController(this._repo, {required this.signedIn}) : super(const NotificationsState()) {
    if (signedIn) refresh();
  }

  final NotificationRepository _repo;
  final bool signedIn;

  /// Re-reads the inbox. [silent] keeps the current list on screen (no spinner)
  /// — used by the background poll.
  Future<void> refresh({bool silent = false}) async {
    if (!signedIn || !mounted) return;
    if (!silent) state = state.copyWith(isLoading: true, clearError: true);
    final result = await _repo.getNotifications();
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        state = state.copyWith(
          items: data.items,
          unreadCount: data.unreadCount,
          isLoading: false,
          loadedOnce: true,
          clearError: true,
        );
      case Failure(:final error):
        state = state.copyWith(
          isLoading: false,
          loadedOnce: true,
          error: silent && state.items.isNotEmpty ? null : error.message,
        );
    }
  }

  /// Marks one read right away on screen, then tells the server (rolled back
  /// by the next refresh if that fails).
  Future<void> markRead(int id) async {
    final target = state.items.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;
    state = state.copyWith(
      items: [for (final n in state.items) n.id == id ? n.copyWith(isRead: true) : n],
      unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30),
    );
    final result = await _repo.markRead(id);
    if (result is Failure) refresh(silent: true);
  }

  Future<void> markAllRead() async {
    final unread = state.items.where((n) => !n.isRead).map((n) => n.id).toList();
    if (unread.isEmpty) return;
    state = state.copyWith(
      items: [for (final n in state.items) n.copyWith(isRead: true)],
      unreadCount: 0,
    );
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
  return NotificationsController(ref.watch(notificationRepositoryProvider), signedIn: signedIn);
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
