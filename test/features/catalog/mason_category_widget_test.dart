import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_providers.dart';
import 'package:calservices_customer/features/catalog/presentation/screens/category_detail_screen.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/service_card.dart';

void main() {
  testWidgets('CategoryDetailScreen mounts Mason and renders ServiceCards', (tester) async {
    final mockServices = [
      ServiceItem(
        id: 400,
        title: 'Block Wall Construction',
        slug: 'brick-block',
        price: Decimal.fromInt(1799),
        categoryId: 17,
        categorySlug: 'mason_construction',
      ),
    ];

    final mockSubcategories = [
      const Subcategory(
        id: 35,
        name: 'Brick & Block Work',
        slug: 'brick-block-work',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryServicesProvider.overrideWith((ref, param) async => mockServices),
          subServicesProvider.overrideWith((ref, slug) async => mockSubcategories),
        ],
        child: const MaterialApp(
          home: CategoryDetailScreen(
            categorySlug: 'mason',
            initialCategory: Category(
              id: 17,
              name: 'Mason & Construction',
              slug: 'mason_construction',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Mason & Construction'), findsOneWidget);
    expect(find.text('All Services'), findsOneWidget);
    expect(find.text('Brick & Block Work'), findsOneWidget);
    expect(find.text('Block Wall Construction'), findsOneWidget);
    expect(find.byType(ServiceCard), findsOneWidget);
  });
}
