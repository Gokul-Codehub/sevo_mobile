import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';

/// Where a Home Studio banner / link goes when tapped.
class StudioDestination {
  const StudioDestination({this.type = 'none', this.value = '', this.slug = ''});

  final String type;
  final String value;
  final String slug;

  factory StudioDestination.fromJson(dynamic raw) {
    if (raw is! Map) return const StudioDestination();
    return StudioDestination(
      type: (raw['type'] ?? 'none').toString(),
      value: (raw['value'] ?? '').toString().trim(),
      slug: (raw['slug'] ?? '').toString().trim(),
    );
  }
}

class StudioSlide {
  const StudioSlide({
    required this.id,
    required this.imageUrl,
    this.alt = '',
    this.title = '',
    this.destination = const StudioDestination(),
  });

  final String id;
  final String imageUrl;
  final String alt;
  final String title;
  final StudioDestination destination;

  factory StudioSlide.fromJson(Map<String, dynamic> j) => StudioSlide(
        id: (j['id'] ?? '').toString(),
        imageUrl: (j['image_url'] ?? '').toString(),
        alt: (j['alt_text'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        destination: StudioDestination.fromJson(j['destination']),
      );
}

/// One section of a Home Studio page, as resolved by the server.
class StudioSection {
  const StudioSection({
    required this.id,
    required this.template,
    this.name = '',
    this.settings = const {},
    this.slides = const [],
    this.content = const {},
  });

  final String id;
  final String template;
  final String name;
  final Map<String, dynamic> settings;
  final List<StudioSlide> slides;

  /// Product / category / service source descriptor (type, ids, category_id,
  /// rule, limit …). Resolved against live catalog data in the app so prices
  /// and stock are never frozen into a published page.
  final Map<String, dynamic> content;

  String get title => (settings['title'] ?? '').toString();
  bool flag(String key, {bool fallback = false}) {
    final v = settings[key];
    return v is bool ? v : fallback;
  }

  int intSetting(String key, int fallback) =>
      int.tryParse(settings[key]?.toString() ?? '') ?? fallback;

  factory StudioSection.fromJson(Map<String, dynamic> j) => StudioSection(
        id: (j['id'] ?? '').toString(),
        template: (j['template'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        settings: j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : const {},
        slides: (j['slides'] is List)
            ? (j['slides'] as List)
                .whereType<Map>()
                .map((m) => StudioSlide.fromJson(Map<String, dynamic>.from(m)))
                .where((s) => s.imageUrl.isNotEmpty)
                .toList()
            : const [],
        content: j['content'] is Map ? Map<String, dynamic>.from(j['content'] as Map) : const {},
      );
}

class StudioPage {
  const StudioPage({
    required this.pageKey,
    this.version = 0,
    this.useLegacy = true,
    this.sections = const [],
  });

  final String pageKey;
  final int version;

  /// True when the server says this page is not (yet) served from Home Studio.
  final bool useLegacy;
  final List<StudioSection> sections;

  factory StudioPage.fromJson(Map<String, dynamic> j) => StudioPage(
        pageKey: (j['page'] ?? '').toString(),
        version: int.tryParse(j['version']?.toString() ?? '') ?? 0,
        useLegacy: j['use_legacy'] != false,
        sections: (j['sections'] is List)
            ? (j['sections'] as List)
                .whereType<Map>()
                .map((m) => StudioSection.fromJson(Map<String, dynamic>.from(m)))
                .where((s) => s.id.isNotEmpty && s.template.isNotEmpty)
                .toList()
            : const [],
      );
}

class HomeStudioRepository {
  HomeStudioRepository({required this.api});

  final ApiClient api;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  String _cacheKey(String pageKey) => 'sevo_home_studio_v1_$pageKey';

  /// Latest published page. Network first; on any failure falls back to the
  /// last good copy stored on this phone. Returns null when there is nothing
  /// to show, in which case Home keeps its legacy layout.
  Future<StudioPage?> load(String pageKey) async {
    try {
      final response = await api.get('/home/pages/$pageKey/').timeout(const Duration(seconds: 6));
      final body = response.data;
      if (body is Map) {
        final inner = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : Map<String, dynamic>.from(body);
        final page = StudioPage.fromJson(inner);
        if (page.useLegacy) {
          await _clear(pageKey);
        } else {
          await _save(pageKey, inner);
        }
        return page;
      }
    } catch (e) {
      debugPrint('[HomeStudio] fetch failed for $pageKey: $e');
    }
    return _readCache(pageKey);
  }

  Future<void> _save(String pageKey, Map<String, dynamic> raw) async {
    try {
      await _storage.write(key: _cacheKey(pageKey), value: jsonEncode(raw));
    } catch (_) {}
  }

  Future<void> _clear(String pageKey) async {
    try {
      await _storage.delete(key: _cacheKey(pageKey));
    } catch (_) {}
  }

  Future<StudioPage?> _readCache(String pageKey) async {
    try {
      final raw = await _storage.read(key: _cacheKey(pageKey));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return StudioPage.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

final homeStudioRepositoryProvider = Provider<HomeStudioRepository>((ref) {
  return HomeStudioRepository(api: ref.watch(apiClientProvider));
});

/// Home Studio page for `grocery_home` / `services_home`. Never throws: a
/// failure resolves to the cached copy or null, and Home then keeps the
/// layout it already had.
final homeStudioPageProvider =
    FutureProvider.family<StudioPage?, String>((ref, pageKey) async {
  ref.keepAlive();
  // Re-fetch every 90s while the app is open so a page published (or switched
  // on/off) in the admin reaches phones that are already running, instead of
  // keeping the answer from app start. While refreshing, the previous value
  // stays on screen (no flicker).
  final timer = Timer(const Duration(seconds: 90), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(homeStudioRepositoryProvider).load(pageKey);
});
