import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../data/marketplace_catalog_repository.dart';
import '../../domain/catalog_models.dart';
import '../../domain/catalog_providers.dart';
import '../widgets/product_card.dart';
import '../widgets/service_card.dart';

/// Which products an offer page lists. Set by the admin (Home Studio ->
/// destination "Offers page"):
///   percent - at least [value]% off
///   amount  - saves at least ₹[value]
///   under   - priced at or under ₹[value]
enum OfferMode { percent, amount, under }

/// The pool of items to filter (scope + optional category). The rule itself
/// (mode / value) is applied on screen, so changing sort never refetches.
typedef OfferPool = ({String scope, int? cat, String slug});

/// Every product / service in the pool, live. Prices and stock are never
/// copied anywhere; they come straight from the catalogue each time.
final offerPoolProvider = FutureProvider.autoDispose.family<List<ServiceItem>, OfferPool>((ref, pool) async {
  final out = <ServiceItem>[];
  final seen = <int>{};
  void add(Iterable<ServiceItem> items) {
    for (final i in items) {
      if (seen.add(i.id)) out.add(i);
    }
  }

  if (pool.scope == 'services') {
    Future<List<ServiceItem>> forCategory(int? id, String slug) async {
      try {
        return await ref.watch(categoryServicesProvider(CategoryServicesParam(categoryId: id, categorySlug: slug)).future);
      } catch (_) {
        return const <ServiceItem>[];
      }
    }

    if (pool.slug.isNotEmpty || pool.cat != null) {
      add(await forCategory(pool.cat, pool.slug));
    } else {
      final cats = await ref.watch(categoriesProvider.future);
      final lists = await Future.wait([for (final c in cats.take(20)) forCategory(c.id, c.slug)]);
      for (final l in lists) {
        add(l);
      }
    }
    return out;
  }

  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  var page = 1;
  var totalPages = 1;
  do {
    final result = await repo.getProducts(
      categoryId: pool.cat,
      categorySlug: pool.cat == null ? pool.slug : null,
      page: page,
      pageSize: 100,
    );
    if (result is! Success<MarketplaceProductPage>) break;
    totalPages = result.data.totalPages;
    add(result.data.products.map((p) => p.toServiceItem()));
    page++;
  } while (page <= totalPages && page <= 8);
  return out;
});

String _money(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

class OfferListingScreen extends ConsumerStatefulWidget {
  const OfferListingScreen({super.key, required this.params});

  /// Query parameters of /offers?mode=percent&v=60&cat=12&slug=snacks&scope=grocery&title=...
  final Map<String, String> params;

  @override
  ConsumerState<OfferListingScreen> createState() => _OfferListingScreenState();
}

enum _Sort { bestDeal, priceLow, priceHigh }

class _OfferListingScreenState extends ConsumerState<OfferListingScreen> {
  _Sort _sort = _Sort.bestDeal;

  OfferMode get _mode {
    switch (widget.params['mode']) {
      case 'amount':
        return OfferMode.amount;
      case 'under':
        return OfferMode.under;
      default:
        return OfferMode.percent;
    }
  }

  double get _value => double.tryParse(widget.params['v'] ?? '') ?? 0;
  String get _scope => widget.params['scope'] == 'services' ? 'services' : 'grocery';

  String get _title {
    final t = (widget.params['title'] ?? '').trim();
    if (t.isNotEmpty) return t;
    switch (_mode) {
      case OfferMode.percent:
        return '${_money(_value)}% off & more';
      case OfferMode.amount:
        return 'Save ₹${_money(_value)} or more';
      case OfferMode.under:
        return 'Under ₹${_money(_value)}';
    }
  }

  bool _matches(ServiceItem s) {
    switch (_mode) {
      case OfferMode.percent:
        return (s.discountPercent ?? 0) >= _value;
      case OfferMode.amount:
        if (!s.hasDiscount) return false;
        return (s.price - s.discountedPrice!) >= Decimal.parse(_value.toString());
      case OfferMode.under:
        return s.effectivePrice <= Decimal.parse(_value.toString()) && s.effectivePrice > Decimal.zero;
    }
  }

  List<ServiceItem> _sorted(List<ServiceItem> items) {
    final out = [...items];
    switch (_sort) {
      case _Sort.priceLow:
        out.sort((a, b) => a.effectivePrice.compareTo(b.effectivePrice));
      case _Sort.priceHigh:
        out.sort((a, b) => b.effectivePrice.compareTo(a.effectivePrice));
      case _Sort.bestDeal:
        if (_mode == OfferMode.under) {
          out.sort((a, b) => (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0));
        } else if (_mode == OfferMode.amount) {
          out.sort((a, b) {
            final sa = a.hasDiscount ? a.price - a.discountedPrice! : Decimal.zero;
            final sb = b.hasDiscount ? b.price - b.discountedPrice! : Decimal.zero;
            return sb.compareTo(sa);
          });
        } else {
          out.sort((a, b) => (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0));
        }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pool = (
      scope: _scope,
      cat: int.tryParse(widget.params['cat'] ?? ''),
      slug: widget.params['slug'] ?? '',
    );
    final async = ref.watch(offerPoolProvider(pool));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text(_title, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 17)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't load offers right now.", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => ref.invalidate(offerPoolProvider(pool)), child: const Text('Try again')),
              ],
            ),
          ),
        ),
        data: (all) {
          final items = _sorted(all.where(_matches).toList());
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(offerPoolProvider(pool));
              await ref.read(offerPoolProvider(pool).future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items.length} ${items.length == 1 ? 'item' : 'items'} · live prices',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _chip('Best deal', _Sort.bestDeal),
                              _chip('Price: low to high', _Sort.priceLow),
                              _chip('Price: high to low', _Sort.priceHigh),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No items match this offer right now. Check back soon.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                        ),
                      ),
                    ),
                  )
                else if (_scope == 'services')
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => ServiceCard(service: items[i]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    sliver: SliverList.separated(
                      itemCount: (items.length + 1) ~/ 2,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, row) {
                        final a = items[row * 2];
                        final hasB = row * 2 + 1 < items.length;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: RepaintBoundary(child: ProductCard(service: a))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: hasB ? RepaintBoundary(child: ProductCard(service: items[row * 2 + 1])) : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, _Sort sort) {
    final on = _sort == sort;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.navy)),
        selected: on,
        showCheckmark: false,
        selectedColor: AppColors.navy,
        backgroundColor: Colors.white,
        side: BorderSide(color: on ? AppColors.navy : const Color(0xFFD1D5DB)),
        onSelected: (_) => setState(() => _sort = sort),
      ),
    );
  }
}
