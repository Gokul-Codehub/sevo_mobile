import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show ImageConfiguration;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';
import '../../addresses/domain/address_notifier.dart' show selectedAddressProvider;

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

  /// Optional uploaded image shown instead of the title text, and the
  /// admin-chosen title font key (see studio_title.dart).
  String get titleImage => (settings['title_image'] ?? '').toString();
  String get titleFont => (settings['title_font'] ?? '').toString();
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

  /// What is visible right now (section + banner ids). The server switches scheduled sections/banners on and off
  /// without changing [version], so this is what tells us the page really changed.
  String get signature => sections.map((s) => '${s.id}:${s.slides.map((x) => x.id).join(',')}').join('|');

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
  // The saved copy is per city: a banner targeted at one city must not be replayed to another.
  String _cacheKey(String pageKey, String city) => 'sevo_home_studio_v1_${pageKey}_${city.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}';

  /// Latest published page. Network first; on any failure falls back to the
  /// last good copy stored on this phone. Returns null when there is nothing
  /// to show, in which case Home keeps its legacy layout.
  Future<StudioPage?> load(String pageKey, {String city = '', void Function()? onLateFresh}) async {
    // Fast path: when a saved copy exists, show it if the network is slow
    // (> 1.5 s) instead of making the customer wait, then refresh quietly
    // once the real answer arrives ([onLateFresh]).
    // Start the network request FIRST: reading the saved copy (encrypted storage) must not delay it.
    final fetch = _fetch(pageKey, city);
    final cached = await _readCache(pageKey, city);
    if (cached == null) {
      return (await fetch) ?? _readCache(pageKey, city);
    }
    try {
      final fresh = await fetch.timeout(const Duration(milliseconds: 1500));
      return fresh ?? cached;
    } on TimeoutException {
      unawaited(fetch.then((fresh) {
        // Only refresh when the server really has something newer.
        if (fresh != null && (fresh.version != cached.version || fresh.signature != cached.signature)) onLateFresh?.call();
      }).catchError((_) {}));
      return cached;
    }
  }

  /// Network fetch; saves/clears the cache. Null on any failure.
  Future<StudioPage?> _fetch(String pageKey, String city) async {
    // One quick retry: the very first request after install often fails while the connection warms up.
    final first = await _fetchOnce(pageKey, city);
    if (first != null) return first;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _fetchOnce(pageKey, city);
  }

  /// Starts downloading the first banner images into the app's image cache so they are on screen the moment the
  /// sections build, instead of popping in one by one. Fire-and-forget; failures are ignored.
  void _warmImages(StudioPage page) {
    var budget = 8;
    for (final section in page.sections) {
      final urls = <String>[
        if (section.titleImage.isNotEmpty) section.titleImage,
        for (final slide in section.slides) slide.imageUrl,
      ];
      for (final url in urls) {
        if (budget == 0) return;
        if (!url.startsWith('http')) continue;
        budget--;
        try {
          CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
        } catch (_) {}
      }
    }
  }

  Future<StudioPage?> _fetchOnce(String pageKey, String city) async {
    try {
      final response = await api.get('/home/pages/$pageKey/', queryParameters: {if (city.isNotEmpty) 'city': city}).timeout(const Duration(seconds: 7));
      final body = response.data;
      if (body is Map) {
        final inner = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : Map<String, dynamic>.from(body);
        final page = StudioPage.fromJson(inner);
        if (page.useLegacy) {
          await _clear(pageKey, city);
        } else {
          _warmImages(page);
          // Saving the copy is not needed to show the page - do not make the customer wait for the disk.
          unawaited(_save(pageKey, city, inner));
        }
        return page;
      }
    } catch (e) {
      debugPrint('[HomeStudio] fetch failed for $pageKey: $e');
    }
    return null;
  }

  Future<void> _save(String pageKey, String city, Map<String, dynamic> raw) async {
    try {
      await _storage.write(key: _cacheKey(pageKey, city), value: jsonEncode(raw));
    } catch (_) {}
  }

  Future<void> _clear(String pageKey, String city) async {
    try {
      await _storage.delete(key: _cacheKey(pageKey, city));
    } catch (_) {}
  }

  Future<StudioPage?> _readCache(String pageKey, String city) async {
    try {
      final raw = await _storage.read(key: _cacheKey(pageKey, city));
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
  var disposed = false;
  ref.onDispose(() => disposed = true);
  // Targeting: the server hides city-targeted sections/banners unless it knows the customer's city.
  final city = ref.watch(selectedAddressProvider.select((a) => (a?.city ?? '').trim()));
  final page = await ref.watch(homeStudioRepositoryProvider).load(
    pageKey,
    city: city,
    onLateFresh: () {
      if (!disposed) ref.invalidateSelf();
    },
  );
  // A failed first load (null: no network answer and nothing saved) must NOT stay for 90 s - that left Home on the
  // old layout until the customer pulled to refresh. Retry quickly (3 s, 6 s, 12 s ...) until it arrives.
  if (page == null) {
    final n = (_studioFailures[pageKey] ?? 0) + 1;
    _studioFailures[pageKey] = n;
    final wait = Duration(seconds: (3 * n).clamp(3, 15));
    final retry = Timer(wait, ref.invalidateSelf);
    ref.onDispose(retry.cancel);
  } else {
    _studioFailures.remove(pageKey);
    final timer = Timer(const Duration(seconds: 90), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return page;
});

final Map<String, int> _studioFailures = {};
