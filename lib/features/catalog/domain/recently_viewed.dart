import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import 'catalog_models.dart';

/// What the customer recently opened (services and grocery items), newest first, kept on the phone.
///
/// Works for guests too, and is wiped on logout with the rest of the person's data (see `SecureStorage.clearAll`).
/// Only a slim snapshot is stored (no long description / FAQs); the Home tile looks the live record up again when it is
/// tapped, the same way "Book Again" does.
class RecentlyViewedNotifier extends StateNotifier<List<ServiceItem>> {
  RecentlyViewedNotifier(this._storage) : super(const []) {
    _ready = _restore();
  }

  final SecureStorage _storage;
  late final Future<void> _ready;
  bool _touched = false;

  /// Most items kept per kind (services / groceries), so a heavy grocery browser does not push every service out.
  static const int perKind = 20;

  static bool isGrocery(ServiceItem s) =>
      s.flowType == CatalogFlowType.grocery ||
      (s.vegetableCategorySlug?.isNotEmpty ?? false) ||
      (s.vegetableCategoryName?.isNotEmpty ?? false) ||
      s.id >= 800000000;

  Future<void> _restore() async {
    try {
      final raw = await _storage.getRecentlyViewedJson();
      if (raw == null || _touched || !mounted) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      final items = <ServiceItem>[];
      for (final e in list) {
        if (e is Map) {
          try {
            items.add(ServiceItem.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
      state = items;
    } catch (_) {
      // A damaged copy just means an empty history.
    }
  }

  /// Puts [item] first. Opening the same thing again moves it to the front instead of listing it twice.
  Future<void> record(ServiceItem item) async {
    await _ready;
    if (!mounted || item.id <= 0 || item.title.trim().isEmpty) return;
    _touched = true;
    final grocery = isGrocery(item);
    final next = <ServiceItem>[item, ...state.where((s) => !(s.id == item.id && isGrocery(s) == grocery))];
    var g = 0, s = 0;
    state = [
      for (final e in next)
        if (isGrocery(e) ? ++g <= perKind : ++s <= perKind) e,
    ];
    try {
      await _storage.setRecentlyViewedJson(jsonEncode([for (final e in state) _slim(e)]));
    } catch (_) {}
  }

  static Map<String, dynamic> _slim(ServiceItem e) => e.toJson()
    ..remove('description')
    ..remove('inclusions')
    ..remove('exclusions')
    ..remove('faqs')
    ..remove('ready')
    ..remove('tools');
}

final recentlyViewedProvider = StateNotifierProvider<RecentlyViewedNotifier, List<ServiceItem>>(
  (ref) => RecentlyViewedNotifier(ref.read(secureStorageProvider)),
);

/// Wrap a detail page's content in this to count it as "viewed": it records [item] once the page is on screen.
class RecordRecentView extends ConsumerStatefulWidget {
  const RecordRecentView({super.key, required this.item, required this.child});

  final ServiceItem item;
  final Widget child;

  @override
  ConsumerState<RecordRecentView> createState() => _RecordRecentViewState();
}

class _RecordRecentViewState extends ConsumerState<RecordRecentView> {
  @override
  void initState() {
    super.initState();
    _record();
  }

  @override
  void didUpdateWidget(covariant RecordRecentView old) {
    super.didUpdateWidget(old);
    // The page may first show a bare snapshot and then the full record: keep the fuller one.
    if (old.item.id != widget.item.id || old.item.imageUrl != widget.item.imageUrl) _record();
  }

  void _record() {
    final item = widget.item;
    if (item.isGoodsTransport) return; // Goods & Transport is booked on its own page, not browsed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(recentlyViewedProvider.notifier).record(item);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
