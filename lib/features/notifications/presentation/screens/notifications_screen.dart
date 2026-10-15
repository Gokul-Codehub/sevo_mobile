import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/notification_models.dart';
import '../../domain/notification_providers.dart';
import '../../../../core/navigation/safe_back.dart';

/// The customer's notification inbox (opened from the bell on Home).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Fresh data every time the inbox is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(notificationsControllerProvider.notifier).refresh(silent: true);
    });
  }

  Future<void> _open(CustomerNotification n) async {
    final controller = ref.read(notificationsControllerProvider.notifier);
    controller.markRead(n.id);
    final target = n.target;
    if (target == null || n.isExpired) return;
    final opened = await openNotificationLink(ref, context, target, claimExpiresAt: n.expiresAt);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("There's nothing to open for this notification.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsControllerProvider);
    final controller = ref.read(notificationsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.goBack(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: controller.markAllRead,
              child: const Text('Mark all read', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(silent: true),
        child: Builder(builder: (context) {
          if (!state.loadedOnce && state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state.error != null
                                ? Icons.cloud_off_rounded
                                : Icons.notifications_none_rounded,
                            size: 54,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            state.error != null ? "Couldn't load notifications" : "You're all caught up",
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            state.error ??
                                'Booking updates, appointment openings and offers will show up here.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: 14),
                            OutlinedButton(
                              onPressed: () => controller.refresh(),
                              child: const Text('Try again'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: state.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final n = state.items[i];
              return _NotificationTile(notification: n, onTap: () => _open(n));
            },
          );
        }),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final CustomerNotification notification;
  final VoidCallback onTap;

  ({IconData icon, Color color}) get _style {
    final color = switch (notification.level) {
      'SUCCESS' => AppColors.groceryGreen,
      'WARNING' => AppColors.warning,
      'CRITICAL' => AppColors.error,
      _ => AppColors.serviceBlue,
    };
    final icon = switch (notification.category) {
      'BOOKING' => Icons.event_available_rounded,
      'ORDER' => Icons.shopping_bag_rounded,
      'PAYMENT' => Icons.account_balance_wallet_rounded,
      'SUPPORT' => Icons.support_agent_rounded,
      'ACCOUNT' => Icons.shield_rounded,
      'OFFER' => Icons.local_offer_rounded,
      _ => Icons.notifications_rounded,
    };
    return (icon: icon, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final style = _style;
    final expired = n.isExpired;
    final showAction = n.actionLabel.isNotEmpty && n.target != null && !expired;

    return Opacity(
      opacity: expired ? 0.6 : 1,
      child: Material(
        color: n.isRead ? Colors.white : const Color(0xFFF1F7FF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: n.requiresAction && !expired ? style.color.withValues(alpha: 0.5) : AppColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, size: 21, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: n.isRead ? FontWeight.w700 : FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                          if (!n.isRead)
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(left: 8, top: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (n.body.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          n.body,
                          style: const TextStyle(
                              fontSize: 12, height: 1.35, color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            expired ? 'Expired' : _ago(n.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: expired ? AppColors.error : AppColors.textHint,
                              fontWeight: expired ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          if (n.requiresAction && !expired && n.expiresAt != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '· ${_left(n.expiresAt!)}',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: style.color),
                            ),
                          ],
                        ],
                      ),
                      if (showAction) ...[
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: onTap,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          child: Text(n.actionLabel),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  static String _left(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.inMinutes < 1) return 'less than a minute left';
    if (d.inMinutes < 60) return '${d.inMinutes} min left';
    return '${d.inHours} h left';
  }
}
