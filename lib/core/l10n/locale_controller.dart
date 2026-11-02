import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';

/// `context.l10n.signOut` - falls back to English when no localization is installed (tests, early start-up).
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this) ?? AppLocalizationsEn();
}

/// Languages offered in Profile -> Language: code -> name written in its own script.
/// English only for now: Hindi and Tamil were removed, and every notification the server sends is in English too.
/// Adding a language later means adding its `app_<code>.arb`, regenerating, and listing it here.
const Map<String, String> kLanguages = {'en': 'English'};

class LocaleStore {
  LocaleStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final FlutterSecureStorage _storage;
  static const _key = 'sevo_locale';

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String code) async {
    try {
      await _storage.write(key: _key, value: code);
    } catch (_) {}
  }
}

/// The customer's chosen language. English until they choose, then remembered.
class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._store) : super(const Locale('en')) {
    _load();
  }
  final LocaleStore _store;

  Future<void> _load() async {
    final code = await _store.read();
    if (code != null && kLanguages.containsKey(code) && mounted) state = Locale(code);
    // A language chosen in an older version (Hindi / Tamil) is no longer offered: forget it, the app stays in English.
    if (code != null && !kLanguages.containsKey(code)) await _store.write('en');
  }

  Future<void> choose(String code) async {
    if (!kLanguages.containsKey(code)) return;
    state = Locale(code);
    await _store.write(code);
  }
}

final localeStoreProvider = Provider<LocaleStore>((ref) => LocaleStore());
final localeProvider = StateNotifierProvider<LocaleController, Locale>((ref) => LocaleController(ref.watch(localeStoreProvider)));

/// Profile -> Language.
Future<void> showLanguageSheet(BuildContext context, WidgetRef ref) {
  final current = ref.read(localeProvider).languageCode;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(ctx.l10n.languageSheetTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final e in kLanguages.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == current ? const Icon(Icons.check_rounded) : null,
              onTap: () {
                ref.read(localeProvider.notifier).choose(e.key);
                Navigator.of(ctx).pop();
              },
            ),
          // One language only, for now: say so instead of leaving a one-item list unexplained.
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(
              'English is the only language available right now. Notifications are sent in English too.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.35),
            ),
          ),
        ],
      ),
    ),
  );
}
