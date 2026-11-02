import 'dart:async';

import 'package:calservices_customer/core/network/network_state.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_providers.dart';
import 'package:calservices_customer/features/home/data/homepage_repository.dart';
import 'package:calservices_customer/features/home/presentation/widgets/home_load_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _tagline = 'Everything you need, delivered at your doorstep';

Category cat() => const Category(id: 1, name: 'AC', slug: 'ac');

class _Harness {
  _Harness({this.config, this.categories, this.configFails = false, this.categoriesFail = false});
  HomepageConfig? config;
  List<Category>? categories;
  bool configFails;
  bool categoriesFail;
  int configCalls = 0;
  int categoryCalls = 0;

  List<Override> get overrides => [
        homepageConfigProvider.overrideWith((ref) async {
          configCalls++;
          if (configFails) throw Exception('offline');
          return config ?? (throw Exception('none'));
        }),
        categoriesProvider.overrideWith((ref) async {
          categoryCalls++;
          if (categoriesFail) throw Exception('offline');
          return categories ?? const <Category>[];
        }),
      ];

  Future<void> pump(WidgetTester tester, {Duration slowAfter = const Duration(seconds: 20), ProviderContainer? container}) async {
    final app = MaterialApp(
        home: Scaffold(
          body: HomeLoadGate(slowAfter: slowAfter, child: const Center(child: Text('HOME PAGE'))),
        ),
    );
    await tester.pumpWidget(container == null ? ProviderScope(overrides: overrides, child: app) : UncontrolledProviderScope(container: container, child: app));
  }
}

void main() {
  test('rule: only when BOTH are missing is nothing loaded', () {
    expect(homeHasNothingLoaded(hasHomepageConfig: false, hasCategories: false), isTrue);
    expect(homeHasNothingLoaded(hasHomepageConfig: true, hasCategories: false), isFalse);
    expect(homeHasNothingLoaded(hasHomepageConfig: false, hasCategories: true), isFalse);
    expect(homeHasNothingLoaded(hasHomepageConfig: true, hasCategories: true), isFalse);
  });

  testWidgets('nothing loaded: the splash loader covers the screen', (tester) async {
    final h = _Harness(configFails: true, categoriesFail: true);
    await h.pump(tester);
    await tester.pump();
    expect(find.text(_tagline), findsOneWidget);
    final overlay = tester.getRect(find.byType(Material).last);
    expect(overlay.size, tester.view.physicalSize / tester.view.devicePixelRatio); // the whole screen
    // clear the pending timer
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('part loaded (categories arrived): no splash, the page shows with its own skeletons', (tester) async {
    final h = _Harness(configFails: true, categories: [cat()]);
    await h.pump(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text(_tagline), findsNothing);
    expect(find.text('HOME PAGE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('everything loaded: no splash', (tester) async {
    final h = _Harness(config: HomepageConfig(offers: const []), categories: [cat()]);
    await h.pump(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text(_tagline), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('still nothing after the wait: it says so and offers Try again, which asks again', (tester) async {
    final h = _Harness(configFails: true, categoriesFail: true);
    await h.pump(tester, slowAfter: const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Try again'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(find.textContaining('Still trying to reach SEVO'), findsOneWidget);
    final before = h.categoryCalls;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(h.categoryCalls, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the app shell is told while the splash is up, so the unreachable banner steps aside', (tester) async {
    final h = _Harness(configFails: true, categoriesFail: true);
    final container = ProviderContainer(overrides: h.overrides);
    addTearDown(container.dispose);
    await h.pump(tester, container: container);
    await tester.pump();
    await tester.pump();
    expect(container.read(fullScreenLoaderActiveProvider), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(container.read(fullScreenLoaderActiveProvider), isFalse);
  });
}
