import '../../../core/l10n/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/safe_back.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/app_toast.dart';
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
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _bar(context, context.l10n.devicesTitle),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _error('We could not load your devices.', () => ref.invalidate(deviceSessionsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No other devices found.', style: TextStyle(color: Colors.black54)));
          }
          final others = list.where((d) => !d.current).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(context.l10n.devicesIntro, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 12),
              for (final d in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE3E8EE))),
                  child: ListTile(
                    leading: const Icon(Icons.smartphone_rounded, color: AppColors.navy),
                    title: Text(d.model, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([if (d.osVersion.isNotEmpty) d.osVersion, if (d.current) context.l10n.thisDevice else _ago(d.lastSeen)].join(' - ')),
                    trailing: d.current
                        ? null
                        : TextButton(onPressed: () => _signOut(context, ref, d), child: const Text('Sign out')),
                  ),
                ),
              if (others > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: () => _signOutOthers(context, ref),
                    child: Text(context.l10n.signOutAllOthers),
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

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  final Map<String, bool> _pending = {}; // optimistic values while saving

  Future<void> _toggle(String field, bool value) async {
    setState(() => _pending[field] = value);
    final ok = await ref.read(accountSettingsRepositoryProvider).setPreference(field, value);
    if (!mounted) return;
    if (!ok) AppToast.show(context, 'Could not save that change. Check your connection.', type: AppToastType.error);
    setState(() => _pending.remove(field));
    ref.invalidate(notificationPreferencesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notificationPreferencesProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _bar(context, context.l10n.notifSettingsTitle),
      body: prefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _error('We could not load your settings.', () => ref.invalidate(notificationPreferencesProvider)),
        data: (map) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(context.l10n.notifSettingsIntro, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 8),
            for (final e in kNotificationToggles.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.navy,
                title: Text(e.value.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(e.value.hint, style: const TextStyle(fontSize: 12)),
                value: _pending[e.key] ?? map[e.key] ?? true,
                onChanged: (v) => _toggle(e.key, v),
              ),
          ],
        ),
      ),
    );
  }
}
