import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../domain/catalog_providers.dart';
import '../widgets/service_card.dart';

/// Screen enabling customers to search across all services and categories.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 46,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search services, AC repair, cleaning...',
              hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
              prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                    )
                  : null,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (val) {
              ref.read(searchQueryProvider.notifier).state = val;
            },
          ),
        ),
      ),
      body: query.trim().isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Popular Categories',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  categoriesAsync.when(
                    data: (categories) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories
                          .map(
                            (cat) => ActionChip(
                              avatar: const Icon(
                                Icons.trending_up_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              label: Text(cat.name),
                              onPressed: () {
                                // Fixed 2026-09-01: pass the real, live
                                // Category straight through so the detail
                                // screen never has to guess/re-match it.
                                context.push('/categories/${cat.slug}',
                                    extra: cat);
                              },
                            ),
                          )
                          .toList(),
                    ),
                    loading: () => const ShimmerCard(height: 80),
                    error: (error, stackTrace) => const SizedBox.shrink(),
                  ),
                ],
              ),
            )
          : resultsAsync.when(
              loading: () => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 4,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) => const ShimmerCard(height: 120),
              ),
              error: (err, _) => ErrorStateWidget(
                message: err.toString(),
                onRetry: () => ref.refresh(searchResultsProvider),
              ),
              data: (results) {
                if (results.isEmpty) {
                  return EmptyStateWidget(
                    title: 'No Services Found',
                    subtitle: 'Try searching with different keywords like "AC", "Cleaning", or "Wiring".',
                    emoji: '🔍',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: results.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return ServiceCard(service: results[index]);
                  },
                );
              },
            ),
    );
  }
}
