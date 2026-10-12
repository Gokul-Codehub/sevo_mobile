import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/notification_providers.dart';

/// The bell beside the delivery location on Home. Shows the unread count and
/// opens the inbox; a guest is sent to sign in first (the inbox is per account).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color = AppColors.navy});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isUserAuthenticatedProvider);
    final unread = signedIn ? ref.watch(unreadNotificationCountProvider) : 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(signedIn ? AppRoutes.notifications : AppRoutes.login),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(
                unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                size: 21,
                color: color,
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 0,
                top: 1,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
