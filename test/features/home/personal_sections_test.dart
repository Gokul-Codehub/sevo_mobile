import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/domain/recently_viewed.dart';
import 'package:calservices_customer/features/home/data/home_studio_repository.dart';
import 'package:calservices_customer/features/home/presentation/widgets/book_again_section.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage extends SecureStorage {
  String? saved;
  @override
  Future<String?> getRecentlyViewedJson() async => saved;
  @override
  Future<void> setRecentlyViewedJson(String json) async => saved = json;
}

ServiceItem service(int id, String title, {String slug = 'ac-deep-clean', String categorySlug = 'ac_appliance', String price = '499'}) => ServiceItem(
      id: id,
      title: title,
      slug: slug,
      price: Decimal.parse(price),
      categoryId: 1,
      categoryName: 'AC & Appliance',
      categorySlug: categorySlug,
    );

// A Seller Hub product: its id sits in the marketplace range, which is how the app tells groceries from services.
ServiceItem grocery(int n, String title) => service(800000000 + n, title, slug: 'veg-$n', categorySlug: 'vegetables_groceries', price: '37');

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('RecentlyViewedNotifier', () {
    test('newest first, and opening something again moves it to the front instead of listing it twice', () async {
      final n = RecentlyViewedNotifier(_MemoryStorage());
      await n.record(service(1, 'AC clean'));
      await n.record(service(2, 'Plumber'));
      await n.record(service(1, 'AC clean'));
      expect(n.state.map((s) => s.id).toList(), [1, 2]);
    });

    test('keeps at most 20 of each kind, so groceries never push every service out', () async {
      final n = RecentlyViewedNotifier(_MemoryStorage());
      await n.record(service(1, 'AC clean'));
      for (var i = 1; i <= 25; i++) {
        await n.record(grocery(i, 'Veg $i'));
      }
      expect(n.state.where(RecentlyViewedNotifier.isGrocery).length, 20);
      expect(n.state.where((s) => !RecentlyViewedNotifier.isGrocery(s)).length, 1);
      expect(n.state.first.title, 'Veg 25');
    });

    test('is remembered by the next launch, and long text is not stored', () async {
      final store = _MemoryStorage();
      final first = RecentlyViewedNotifier(store);
      await first.record(ServiceItem(
        id: 7, title: 'Pest control', slug: 'pest', price: Decimal.parse('999'), categoryId: 2, categoryName: 'Pest', categorySlug: 'pest',
        description: 'x' * 5000,
      ));
      expect(store.saved, isNot(contains('xxxxxxxx')));

      final second = RecentlyViewedNotifier(store);
      await settle();
      expect(second.state.single.title, 'Pest control');
    });

    test('ignores an item with no id or title, and survives a damaged saved copy', () async {
      final n = RecentlyViewedNotifier(_MemoryStorage()..saved = 'not json');
      await settle();
      expect(n.state, isEmpty);
      await n.record(service(0, 'No id'));
      await n.record(service(5, '  '));
      expect(n.state, isEmpty);
    });
  });

  group('Recently Viewed section', () {
    StudioSection section({Map<String, dynamic> settings = const {'title': 'Pick up where you left off', 'max_items': 3}}) =>
        StudioSection(id: 'r1', template: 'recently_viewed', settings: settings);

    Future<void> pump(WidgetTester tester, String pageKey, {List<ServiceItem> viewed = const []}) async {
      final store = _MemoryStorage();
      await tester.pumpWidget(ProviderScope(
        overrides: [recentlyViewedProvider.overrideWith((ref) => RecentlyViewedNotifier(store)..state = viewed)],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StudioRecentlyViewed(section: section(), pageKey: pageKey)))),
      ));
      await tester.pump();
    }

    testWidgets('shows nothing at all until something has been viewed', (tester) async {
      await pump(tester, 'services_home');
      expect(find.text('Pick up where you left off'), findsNothing);
      expect(tester.getSize(find.byType(StudioRecentlyViewed)).height, 0);
    });

    testWidgets('each page lists only its own kind, newest first, capped by the admin\'s item count', (tester) async {
      final viewed = [grocery(1, 'Beetroot'), service(1, 'AC clean'), service(2, 'Plumber'), service(3, 'Electrician'), service(4, 'Painter'), grocery(2, 'Carrot')];
      await pump(tester, 'services_home', viewed: viewed);
      expect(find.text('Pick up where you left off'), findsOneWidget);
      expect(find.text('AC clean'), findsOneWidget);
      expect(find.text('Painter'), findsNothing); // beyond max_items 3
      expect(find.text('Beetroot'), findsNothing); // a grocery item never shows on the Services page

      // Let the image placeholders' timers run out before the test ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('Book Again section', () {
    testWidgets('is hidden for a guest', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioBookAgain(section: const StudioSection(id: 'b1', template: 'book_again', settings: {'title': 'Book again'}), pageKey: 'services_home'),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Book again'), findsNothing);
    });

    test('the list builder honours the admin\'s item limit and returns nothing for no bookings', () {
      expect(recentBookAgainItems(const [], limit: 3), isEmpty);
    });
  });
}
