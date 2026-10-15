import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/notification_models.dart';

/// On-device copy of the booking alerts this phone has shown, so the in-app
/// notification centre keeps a history even for events the server did not
/// record (and while offline). One list per signed-in account, newest 50 kept.
class LocalInboxStore {
  const LocalInboxStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const maxItems = 50;

  String _key(int userId) => 'sevo_local_inbox_v1_$userId';

  Future<List<CustomerNotification>> load(int userId) async {
    try {
      final raw = await _storage.read(key: _key(userId));
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => CustomerNotification.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(int userId, List<CustomerNotification> items) async {
    try {
      final trimmed = items.take(maxItems).map((n) => n.toJson()).toList();
      await _storage.write(key: _key(userId), value: jsonEncode(trimmed));
    } catch (_) {}
  }
}
