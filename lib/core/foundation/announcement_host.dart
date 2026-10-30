import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'foundation_controller.dart';
import 'foundation_models.dart';

/// Remembers dismissed announcement ids on this device.
class AnnouncementStore {
  AnnouncementStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final FlutterSecureStorage _storage;
  static const _key = 'sevo_dismissed_announcements';

  Future<Set<int>> read() async {
    try {
      final text = await _storage.read(key: _key) ?? '';
      return {for (final p in text.split(',')) ?int.tryParse(p)};
    } catch (_) {
      return {};
    }
  }

  Future<void> write(Set<int> ids) async {
    try {
      final recent = ids.toList()..sort();
      await _storage.write(key: _key, value: recent.reversed.take(50).join(','));
    } catch (_) {}
  }
}

final announcementStoreProvider = Provider<AnnouncementStore>((ref) => AnnouncementStore());

class DismissedAnnouncements extends StateNotifier<Set<int>> {
  DismissedAnnouncements(this._store) : super(const {}) {
    _store.read().then((ids) {
      if (mounted) state = {...state, ...ids};
    });
  }
  final AnnouncementStore _store;

  void dismiss(int id) {
    state = {...state, id};
    _store.write(state);
  }
}

final dismissedAnnouncementsProvider =
    StateNotifierProvider<DismissedAnnouncements, Set<int>>((ref) => DismissedAnnouncements(ref.watch(announcementStoreProvider)));

/// Announcements the customer should currently see (server already applied schedule + audience).
final visibleAnnouncementsProvider = Provider<List<AppAnnouncement>>((ref) {
  final all = ref.watch(foundationControllerProvider.select((s) => s.config.announcements));
  final dismissed = ref.watch(dismissedAnnouncementsProvider);
  return [for (final a in all) if (!a.dismissible || !dismissed.contains(a.id)) a];
});

/// A slim banner at the top of the app. It never covers content with a modal, so it can never
/// block a booking or payment screen.
class AnnouncementBanner extends ConsumerWidget {
  const AnnouncementBanner({super.key, this.onNavigate});
  final void Function(String route)? onNavigate;

  static Color _bg(String severity) => switch (severity) {
        'critical' => const Color(0xFFB3261E),
        'warning' => const Color(0xFFB26A00),
        _ => const Color(0xFF0D253A),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(visibleAnnouncementsProvider);
    if (list.isEmpty) return const SizedBox.shrink();
    final a = list.first;
    return Material(
      color: _bg(a.severity),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    if (a.body.isNotEmpty) Text(a.body, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              if (a.ctaLabel != null && a.ctaRoute != null && onNavigate != null)
                TextButton(
                  onPressed: () => onNavigate!(a.ctaRoute!),
                  child: Text(a.ctaLabel!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              if (a.dismissible)
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => ref.read(dismissedAnnouncementsProvider.notifier).dismiss(a.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
