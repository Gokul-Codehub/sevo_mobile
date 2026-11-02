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

/// Announcements hidden for this app session only (a non-dismissible one is never remembered across launches,
/// but must never trap the customer either).
final sessionHiddenAnnouncementsProvider = StateProvider<Set<int>>((ref) => const {});

/// Announcements the customer should currently see (server already applied schedule + audience).
final visibleAnnouncementsProvider = Provider<List<AppAnnouncement>>((ref) {
  final all = ref.watch(foundationControllerProvider.select((s) => s.config.announcements));
  final dismissed = ref.watch(dismissedAnnouncementsProvider);
  final hidden = ref.watch(sessionHiddenAnnouncementsProvider);
  return [for (final a in all) if ((!a.dismissible || !dismissed.contains(a.id)) && !hidden.contains(a.id)) a];
});

/// The visible announcements of one `kind` (banner | modal | info). Each kind has its own look:
///  * banner - a slim strip at the very top
///  * modal  - a centred pop-up card over the app
///  * info   - a floating card above the bottom navigation
final announcementsOfKindProvider = Provider.family<List<AppAnnouncement>, String>((ref, kind) {
  return [for (final a in ref.watch(visibleAnnouncementsProvider)) if (a.kind == kind) a];
});

/// Closes an announcement: remembered on this phone when it is dismissible, otherwise only until the app restarts.
void closeAnnouncement(WidgetRef ref, AppAnnouncement a) {
  if (a.dismissible) {
    ref.read(dismissedAnnouncementsProvider.notifier).dismiss(a.id);
  } else {
    ref.read(sessionHiddenAnnouncementsProvider.notifier).update((s) => {...s, a.id});
  }
}

Color announcementAccent(String severity) => switch (severity) {
      'critical' => const Color(0xFFB3261E),
      'warning' => const Color(0xFFB26A00),
      _ => const Color(0xFF1565C0),
    };

IconData announcementIcon(String severity) => switch (severity) {
      'critical' => Icons.error_outline_rounded,
      'warning' => Icons.warning_amber_rounded,
      _ => Icons.info_outline_rounded,
    };

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
    final list = ref.watch(announcementsOfKindProvider('banner'));
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
                // No `tooltip:` here - this banner sits above the app's Navigator where there is no Overlay,
                // and a Tooltip needs one (that crashed the red screen). Semantics keeps it accessible.
                Semantics(
                  button: true,
                  label: 'Dismiss',
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => closeAnnouncement(ref, a),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pop-up card in the middle of the screen for an announcement of kind `modal`. Drawn inside the app's own widget
/// tree (not a route), so it works above the Navigator, and it always has a way out ("Got it").
class AnnouncementModal extends ConsumerWidget {
  const AnnouncementModal({super.key, this.onNavigate});
  final void Function(String route)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(announcementsOfKindProvider('modal'));
    if (list.isEmpty) return const SizedBox.shrink();
    final a = list.first;
    final accent = announcementAccent(a.severity);
    return Positioned.fill(
      child: Material(
        color: const Color(0x99000000),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(announcementIcon(a.severity), color: accent, size: 30),
                    ),
                    const SizedBox(height: 16),
                    Text(a.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF0D253A))),
                    if (a.body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(a.body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF475569))),
                    ],
                    const SizedBox(height: 20),
                    if (a.ctaLabel != null && a.ctaRoute != null && onNavigate != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size(0, 46)),
                          onPressed: () {
                            closeAnnouncement(ref, a);
                            onNavigate!(a.ctaRoute!);
                          },
                          child: Text(a.ctaLabel!),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(0, 42)),
                      onPressed: () => closeAnnouncement(ref, a),
                      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A floating card above the bottom navigation for an announcement of kind `info`: softer than a banner, never
/// covers anything the customer is doing.
class AnnouncementInfoCard extends ConsumerWidget {
  const AnnouncementInfoCard({super.key, this.onNavigate});
  final void Function(String route)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(announcementsOfKindProvider('info'));
    if (list.isEmpty) return const SizedBox.shrink();
    final a = list.first;
    final accent = announcementAccent(a.severity);
    return Positioned(
      left: 14,
      right: 14,
      bottom: 96 + MediaQuery.paddingOf(context).bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(announcementIcon(a.severity), color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0D253A))),
                    if (a.body.isNotEmpty) Text(a.body, style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF475569))),
                    if (a.ctaLabel != null && a.ctaRoute != null && onNavigate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: () => onNavigate!(a.ctaRoute!),
                          child: Text(a.ctaLabel!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: accent)),
                        ),
                      ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Dismiss',
                child: IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFF64748B)),
                  onPressed: () => closeAnnouncement(ref, a),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
