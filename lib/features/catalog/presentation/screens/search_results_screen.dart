import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../domain/catalog_models.dart';
import '../../domain/search_keywords.dart';
import '../widgets/product_card.dart';
import '../widgets/service_card.dart';

/// The search-box "pill" at the top of a results page: shows what was
/// searched; tapping it goes back to the suggestions page to refine it.
PreferredSizeWidget _resultsAppBar(BuildContext context, String query) {
  return AppBar(
    titleSpacing: 0,
    backgroundColor: Colors.white,
    elevation: 0.5,
    title: GestureDetector(
      onTap: () => context.pop(),
      child: Container(
        height: 44,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ),
            const Icon(Icons.edit_outlined, size: 17, color: AppColors.textHint),
          ],
        ),
      ),
    ),
  );
}

Widget _resultsHeader(int shown, int total, String query, String noun) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: total > shown
                  ? '$shown of $total ${noun}s for '
                  : '$shown $noun${shown == 1 ? '' : 's'} for ',
              style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
            TextSpan(
              text: '"$query"',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );

String _errorText(Object err) =>
    err.toString().replaceFirst(RegExp(r'^[A-Za-z]+Error: '), '');

typedef _Key = ({String q, SearchMode mode});

// ── Sort & filter UI ────────────────────────────────────────────────────────

class _RefineBar extends ConsumerWidget {
  const _RefineBar({required this.keyArg, required this.items, required this.brands});

  final _Key keyArg;
  final List<ServiceItem> items;
  final Map<int, String> brands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refine = ref.watch(searchRefineProvider(keyArg));
    final notifier = ref.read(searchRefineProvider(keyArg).notifier);
    final n = refine.activeFilters;

    Widget chip(String label, {required bool on, required VoidCallback onTap, IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            avatar: icon == null
                ? null
                : Icon(icon, size: 16, color: on ? Colors.white : AppColors.navy),
            label: Text(label),
            selected: on,
            showCheckmark: false,
            onSelected: (_) => onTap(),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : AppColors.navy,
            ),
            backgroundColor: Colors.white,
            selectedColor: AppColors.primary,
            side: BorderSide(color: on ? AppColors.primary : AppColors.border),
          ),
        );

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
        children: [
          chip(
            n > 0 ? 'Filter · $n' : 'Filter',
            icon: Icons.tune_rounded,
            on: n > 0,
            onTap: () => _showFilterSheet(context, ref),
          ),
          chip(
            refine.sort == SearchSort.relevance ? 'Sort' : refine.sort.label,
            icon: Icons.swap_vert_rounded,
            on: refine.sort != SearchSort.relevance,
            onTap: () => _showSortSheet(context, ref),
          ),
          chip('In stock',
              on: refine.inStockOnly,
              onTap: () => notifier.state = refine.copyWith(inStockOnly: !refine.inStockOnly)),
          chip('Deals',
              on: refine.dealsOnly,
              onTap: () => notifier.state = refine.copyWith(dealsOnly: !refine.dealsOnly)),
          if (!refine.isDefault)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => notifier.state = const SearchRefine(),
                child: const Text('Clear all'),
              ),
            ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(searchRefineProvider(keyArg).notifier);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy)),
              ),
            ),
            for (final s in SearchSort.values)
              ListTile(
                title: Text(s.label),
                trailing: ref.read(searchRefineProvider(keyArg)).sort == s
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  notifier.state = ref.read(searchRefineProvider(keyArg)).copyWith(sort: s);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(searchRefineProvider(keyArg).notifier);
    var draft = ref.read(searchRefineProvider(keyArg));

    final prices = items.map((e) => e.effectivePrice.toDouble()).toList();
    final lo = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a < b ? a : b).floorToDouble();
    var hi = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a > b ? a : b).ceilToDouble();
    if (hi <= lo) hi = lo + 1;
    final departments = {for (final s in items) if ((s.categoryName ?? '').isNotEmpty) s.categoryName!}.toList()
      ..sort();
    final brandNames = {for (final b in brands.values) if (b.isNotEmpty) b}.toList()..sort();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget title(String t) => Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(t,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
              );

          Widget multi(List<String> options, Set<String> selected, void Function(Set<String>) set) =>
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final o in options)
                    FilterChip(
                      label: Text(o),
                      selected: selected.contains(o),
                      onSelected: (on) {
                        final next = {...selected};
                        on ? next.add(o) : next.remove(o);
                        setSheet(() => set(next));
                      },
                    ),
                ],
              );

          final range = RangeValues(
            (draft.minPrice ?? lo).clamp(lo, hi),
            (draft.maxPrice ?? hi).clamp(lo, hi),
          );

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                      shrinkWrap: true,
                      children: [
                        const Text('Filter',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy)),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('In stock only'),
                          value: draft.inStockOnly,
                          onChanged: (v) => setSheet(() => draft = draft.copyWith(inStockOnly: v)),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Discounted only'),
                          value: draft.dealsOnly,
                          onChanged: (v) => setSheet(() => draft = draft.copyWith(dealsOnly: v)),
                        ),
                        if (hi > lo + 1) ...[
                          title('Price  ₹${range.start.round()} – ₹${range.end.round()}'),
                          RangeSlider(
                            values: range,
                            min: lo,
                            max: hi,
                            labels: RangeLabels('₹${range.start.round()}', '₹${range.end.round()}'),
                            onChanged: (v) => setSheet(() {
                              draft = draft.copyWith(
                                minPrice: v.start <= lo ? null : v.start,
                                maxPrice: v.end >= hi ? null : v.end,
                                clearPrice: v.start <= lo && v.end >= hi,
                              );
                            }),
                          ),
                        ],
                        if (departments.length > 1) ...[
                          title('Department'),
                          multi(departments, draft.departments,
                              (s) => draft = draft.copyWith(departments: s)),
                        ],
                        if (brandNames.length > 1) ...[
                          title('Brand'),
                          multi(brandNames, draft.brands, (s) => draft = draft.copyWith(brands: s)),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setSheet(() => draft = SearchRefine(sort: draft.sort)),
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () {
                              notifier.state = draft;
                              Navigator.pop(ctx);
                            },
                            child: const Text('Show results'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Footer under the list: spinner while the next page loads, otherwise a
/// button (the list also loads the next page by itself when scrolled near the end).
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.state, required this.onMore});

  final SearchPageState state;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: TextButton.icon(
            onPressed: onMore,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text("Couldn't load more · Retry"),
          ),
        ),
      );
    }
    if (state.hasNext) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: OutlinedButton(onPressed: onMore, child: const Text('Show more results')),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}

/// "Explore other" — products from the other categories inside the parent of
/// what was found, each category introduced by its name at the top of its own
/// list, so the customer keeps browsing the same aisle (a "baby soap" search
/// ends with more of Baby Care).
class _ExploreOtherSection extends ConsumerWidget {
  const _ExploreOtherSection({required this.keyArg});

  final _Key keyArg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(exploreOtherProvider(keyArg));
    if (async.isLoading && !async.hasValue) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        color: Colors.white,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Explore other',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy)),
            SizedBox(height: 14),
            ShimmerCard(height: 150),
          ],
        ),
      );
    }
    final data = async.valueOrNull;
    if (data == null || data.sections.isEmpty) return const SizedBox.shrink();
    final groceries = keyArg.mode == SearchMode.groceries;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 16, bottom: 20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Explore other',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy),
                  ),
                  if (data.parent != null)
                    TextSpan(
                      text: '  in ${data.parent}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          for (final section in data.sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(section.route, extra: section.extra),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('See all', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            if (groceries)
              LayoutBuilder(
                builder: (context, c) {
                  const cardWidth = 150.0;
                  final cardHeight = ProductCard.groceryCardHeight(
                    cardWidth: cardWidth,
                    showImage: true,
                    showPrice: true,
                    showAddButton: true,
                  );
                  return SizedBox(
                    height: cardHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: section.items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => SizedBox(
                        width: cardWidth,
                        child: RepaintBoundary(child: ProductCard(service: section.items[i])),
                      ),
                    ),
                  );
                },
              )
            else
              for (final s in section.items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: ServiceCard(service: s),
                ),
          ],
        ],
      ),
    );
  }
}

/// "Did you mean ...?" line shown above an empty result.
class _DidYouMean extends ConsumerWidget {
  const _DidYouMean({required this.query, required this.mode});

  final String query;
  final SearchMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = ref.watch(didYouMeanProvider((q: query, mode: mode))).valueOrNull;
    if (suggestion == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Did you mean ',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          GestureDetector(
            onTap: () => context.pushReplacement(
                '/search/${mode.wire}?q=${Uri.encodeQueryComponent(suggestion)}'),
            child: Text(
              suggestion,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const Text(' ?', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

Widget _noMatchAfterFilter(VoidCallback onClear) => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Text('🔎', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          const Text('No results match these filters',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );

// ── Services ────────────────────────────────────────────────────────────────

/// Results for a search made in the Services tab: the matching packages as
/// full service cards (sortable / filterable, loading more as you scroll),
/// plus matching categories / services / vehicles as quick chips.
class ServiceSearchResultsScreen extends ConsumerStatefulWidget {
  const ServiceSearchResultsScreen({super.key, required this.query});

  final String query;

  @override
  ConsumerState<ServiceSearchResultsScreen> createState() => _ServiceSearchResultsState();
}

class _ServiceSearchResultsState extends ConsumerState<ServiceSearchResultsScreen> {
  final _scroll = ScrollController();
  late final _Key _key = (q: widget.query.trim(), mode: SearchMode.services);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 600) {
        ref.read(searchPagerProvider(_key).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _linkChip(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          avatar: Icon(icon, size: 16, color: AppColors.serviceBlue),
          label: Text(label),
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          onPressed: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _key.q;
    final st = ref.watch(searchPagerProvider(_key));
    final refine = ref.watch(searchRefineProvider(_key));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _resultsAppBar(context, q),
      body: Builder(builder: (context) {
        if (st.loading) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, __) => const ShimmerCard(height: 150),
          );
        }
        if (st.error != null && st.page <= 1 && st.packages.isEmpty && st.categories.isEmpty) {
          return ErrorStateWidget(
            message: _errorText(st.error!),
            onRetry: () => ref.read(searchPagerProvider(_key).notifier).retry(),
          );
        }
        if (st.isEmptyResult) {
          return ListView(
            children: [
              _DidYouMean(query: q, mode: SearchMode.services),
              SizedBox(
                height: 420,
                child: EmptyStateWidget(
                  title: 'No services found',
                  subtitle:
                      'Nothing matched "$q". Try a shorter word like "AC", "cleaning" or "wiring".',
                  emoji: '🔍',
                  actionLabel: 'Search again',
                  action: () => context.pop(),
                ),
              ),
            ],
          );
        }

        final chips = <Widget>[
          for (final c in st.categories)
            if (c.categorySlug != null)
              _linkChip(Icons.grid_view_rounded, c.title,
                  () => context.push('/categories/${c.categorySlug}')),
          for (final s in st.services)
            if (s.categorySlug != null)
              _linkChip(Icons.build_circle_outlined, s.title,
                  () => context.push('/categories/${s.categorySlug}')),
          for (final g in st.goods)
            _linkChip(Icons.local_shipping_outlined, g.title,
                () => context.push(AppRoutes.goodsTransportBooking)),
        ];
        final shown = refine.apply(st.packages);

        return ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (chips.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text('Related',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
              ),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: chips,
                ),
              ),
            ],
            if (st.packages.isNotEmpty) ...[
              _RefineBar(keyArg: _key, items: st.packages, brands: const {}),
              if (shown.isNotEmpty)
                _resultsHeader(
                    shown.length, st.total > st.packages.length ? st.total : shown.length, q, 'service'),
              for (final s in shown)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: ServiceCard(service: s),
                ),
              if (shown.isEmpty)
                _noMatchAfterFilter(
                    () => ref.read(searchRefineProvider(_key).notifier).state = const SearchRefine()),
            ],
            _LoadMoreFooter(
              state: st,
              onMore: () => ref.read(searchPagerProvider(_key).notifier).loadMore(),
            ),
            _ExploreOtherSection(keyArg: _key),
          ],
        );
      }),
    );
  }
}

// ── Groceries ───────────────────────────────────────────────────────────────

/// Results for a search made in the Groceries tab: matching products in the
/// same two-column grid used across the grocery pages, sortable / filterable
/// and loading more as you scroll.
class GrocerySearchResultsScreen extends ConsumerStatefulWidget {
  const GrocerySearchResultsScreen({super.key, required this.query});

  final String query;

  @override
  ConsumerState<GrocerySearchResultsScreen> createState() => _GrocerySearchResultsState();
}

class _GrocerySearchResultsState extends ConsumerState<GrocerySearchResultsScreen> {
  final _scroll = ScrollController();
  late final _Key _key = (q: widget.query.trim(), mode: SearchMode.groceries);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 600) {
        ref.read(searchPagerProvider(_key).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _key.q;
    final st = ref.watch(searchPagerProvider(_key));
    final refine = ref.watch(searchRefineProvider(_key));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _resultsAppBar(context, q),
      body: Builder(builder: (context) {
        if (st.loading) {
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: 6,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (_, __) => const ShimmerCard(height: 240),
          );
        }
        if (st.error != null && st.products.isEmpty) {
          return ErrorStateWidget(
            message: _errorText(st.error!),
            onRetry: () => ref.read(searchPagerProvider(_key).notifier).retry(),
          );
        }
        if (st.isEmptyResult) {
          return ListView(
            children: [
              _DidYouMean(query: q, mode: SearchMode.groceries),
              SizedBox(
                height: 420,
                child: EmptyStateWidget(
                  title: 'No products found',
                  subtitle:
                      'Nothing matched "$q". Try a simpler word like "milk", "atta" or "banana".',
                  emoji: '🛒',
                  actionLabel: 'Search again',
                  action: () => context.pop(),
                ),
              ),
            ],
          );
        }

        final items = refine.apply(st.products, brandOf: st.brands);
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: _RefineBar(keyArg: _key, items: st.products, brands: st.brands),
            ),
            if (items.isNotEmpty)
              SliverToBoxAdapter(
                child: _resultsHeader(
                    items.length, st.total > st.products.length ? st.total : items.length, q, 'product'),
              ),
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: _noMatchAfterFilter(
                    () => ref.read(searchRefineProvider(_key).notifier).state = const SearchRefine()),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final cellWidth = (constraints.crossAxisExtent - spacing) / 2;
                  final cellHeight = ProductCard.groceryCardHeight(
                    cardWidth: cellWidth,
                    showImage: true,
                    showPrice: true,
                    showAddButton: true,
                  );
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: 14,
                      childAspectRatio: cellWidth / cellHeight,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => RepaintBoundary(child: ProductCard(service: items[i])),
                      childCount: items.length,
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: _LoadMoreFooter(
                state: st,
                onMore: () => ref.read(searchPagerProvider(_key).notifier).loadMore(),
              ),
            ),
            SliverToBoxAdapter(child: _ExploreOtherSection(keyArg: _key)),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        );
      }),
    );
  }
}
