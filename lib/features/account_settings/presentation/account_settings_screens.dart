import '../../../core/l10n/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../../../core/services/notification_service.dart';
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;

import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../core/navigation/safe_back.dart';
import '../../auth/domain/auth_return.dart';
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../../shared/widgets/login_required_view.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/app_toast.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../data/account_settings_repository.dart';

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 2) return 'Active now';
  if (d.inHours < 1) return 'Active ${d.inMinutes} min ago';
  if (d.inDays < 1) return 'Active ${d.inHours} h ago';
  return 'Active ${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
}

AppBar _bar(BuildContext context, String title) => AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
      leading: BackButton(onPressed: context.goBack),
      backgroundColor: Colors.white,
      foregroundColor: AppColors.navy,
      elevation: 0,
    );

Widget _error(String text, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('Try again')),
        ]),
      ),
    );

/// Profile -> Your devices: phones signed in to this account, with Sign out.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref, DeviceSession d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out ${d.model}?'),
        content: const Text('That phone will be signed out and will need to log in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.signOut)),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ref.read(accountSettingsRepositoryProvider).signOutDevice(d.deviceId);
    if (!context.mounted) return;
    AppToast.show(context, done ? 'Device signed out.' : 'Could not sign out that device. Try again.',
        type: done ? AppToastType.success : AppToastType.error);
    ref.invalidate(deviceSessionsProvider);
  }

  Future<void> _signOutOthers(BuildContext context, WidgetRef ref) async {
    final done = await ref.read(accountSettingsRepositoryProvider).signOutOthers();
    if (!context.mounted) return;
    AppToast.show(context, done ? 'Other devices signed out.' : 'Could not sign out other devices. Try again.',
        type: done ? AppToastType.success : AppToastType.error);
    ref.invalidate(deviceSessionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceSessionsProvider);
    return Scaffold(
      backgroundColor: AppColors.swatchF6F8FA,
      appBar: _bar(context, context.l10n.devicesTitle),
      body: devices.when(
        loading: () => const LoadingState(),
        error: (e, _) => _error('We could not load your devices.', () => ref.invalidate(deviceSessionsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No other devices found.', style: TextStyle(color: Colors.black54)));
          }
          final others = list.where((d) => !d.current).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FadeSlideIn(
                child: Text(context.l10n.devicesIntro, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < list.length; i++)
                FadeSlideIn(
                  index: i + 1,
                  child: PressScale(
                    scale: 0.985,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.swatchE3E8EE)),
                      child: ListTile(
                        leading: const Icon(Icons.smartphone_rounded, color: AppColors.navy),
                        title: Text(list[i].model, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([if (list[i].osVersion.isNotEmpty) list[i].osVersion, if (list[i].current) context.l10n.thisDevice else _ago(list[i].lastSeen)].join(' - ')),
                        trailing: list[i].current
                            ? null
                            : TextButton(onPressed: () => _signOut(context, ref, list[i]), child: const Text('Sign out')),
                      ),
                    ),
                  ),
                ),
              if (others > 0)
                FadeSlideIn(
                  index: list.length + 1,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: PressScale(
                      child: OutlinedButton(
                        onPressed: () => _signOutOthers(context, ref),
                        child: Text(context.l10n.signOutAllOthers),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Profile -> Notification settings: one switch per kind of notification.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> with WidgetsBindingObserver {
  final Map<String, bool> _pending = {}; // optimistic values while saving
  bool? _osAllowed; // is the phone's own notification permission on?

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission(); // back from the phone's settings
  }

  Future<void> _checkPermission() async {
    try {
      final granted = await ph.Permission.notification.isGranted;
      if (mounted) setState(() => _osAllowed = granted);
    } catch (_) {}
  }

  /// Shows the Android "Allow notifications" prompt; once the phone stops asking, opens the app's settings page.
  Future<void> _allowOnPhone() async {
    await NotificationService.instance.requestPermission();
    await _checkPermission();
    if (_osAllowed != true) await ph.openAppSettings();
  }

  Future<void> _toggle(String field, bool value) async {
    setState(() => _pending[field] = value);
    final ok = await ref.read(accountSettingsRepositoryProvider).setPreference(field, value, signedIn: ref.read(isUserAuthenticatedProvider));
    if (!mounted) return;
    if (!ok) AppToast.show(context, 'Could not save that change. Check your connection.', type: AppToastType.error);
    setState(() => _pending.remove(field));
    ref.invalidate(notificationPreferencesProvider);
  }

  @override
  Widget build(BuildContext context) {
    // The switches are saved on the customer's account, so a guest has nothing to load: say so instead of showing a
    // load error, and still give them the phone's own notification switch.
    if (!ref.watch(isUserAuthenticatedProvider)) {
      return Scaffold(
        backgroundColor: AppColors.swatchF6F8FA,
        appBar: _bar(context, context.l10n.notifSettingsTitle),
        body: Column(
          children: [
            Expanded(
              child: LoginRequiredView(
                title: 'Log in to choose your alerts',
                subtitle: 'Your notification choices (booking updates, offers, order status) are saved to your account. '
                    'Log in or sign up to turn each one on or off.',
                buttonLabel: 'Login / Sign Up',
                icon: Icons.notifications_active_outlined,
                onPressed: () => requireLogin(context, ref),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: TextButton.icon(
                onPressed: () => ph.openAppSettings(),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Phone notification settings'),
              ),
            ),
          ],
        ),
      );
    }
    final prefs = ref.watch(notificationPreferencesProvider);
    return Scaffold(
      backgroundColor: AppColors.swatchF6F8FA,
      appBar: _bar(context, context.l10n.notifSettingsTitle),
      body: prefs.when(
        loading: () => const LoadingState(),
        error: (e, _) => _error('We could not load your settings.', () => ref.invalidate(notificationPreferencesProvider)),
        data: (map) {
          final entries = kNotificationToggles.entries.toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FadeSlideIn(
                child: Text(context.l10n.notifSettingsIntro, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              ),
              const SizedBox(height: 8),
              if (_osAllowed == false)
                Container(
                  margin: const EdgeInsets.only(bottom: 8, top: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_off_outlined, color: Color(0xFFB45309)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Notifications are turned off for SEVONIQ on this phone, so you will not receive any.',
                          style: TextStyle(fontSize: 12.5, height: 1.3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _allowOnPhone,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                        child: const Text('Allow'),
                      ),
                    ],
                  ),
                ),
              for (var i = 0; i < entries.length; i++)
                FadeSlideIn(
                  index: i + 1,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.navy,
                    title: Text(entries[i].value.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(entries[i].value.hint, style: const TextStyle(fontSize: 12)),
                    value: _pending[entries[i].key] ?? map[entries[i].key] ?? true,
                    onChanged: (v) {
                      AppHaptics.selection();
                      _toggle(entries[i].key, v);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
