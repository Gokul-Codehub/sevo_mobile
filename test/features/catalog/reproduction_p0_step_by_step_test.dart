import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/presentation/screens/category_detail_screen.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCatalogRepo extends CatalogRepository {
  MockCatalogRepo(this.services, this.categories, this.subcategories)
      : super(api: ApiClient.withDio(Dio()));

  final List<ServiceItem> services;
  final List<Category> categories;
  final List<Subcategory> subcategories;

  @override
  Future<Result<List<Category>>> getCategories() async {
    return Success(categories);
  }

  @override
  Future<Result<List<Subcategory>>> getSubServicesByCategory({required String categorySlug}) async {
    return Success(subcategories);
  }

  @override
  Future<Result<List<ServiceItem>>> getServicesByCategory({
    int? categoryId,
    String? categorySlug,
    String? subcategorySlug,
  }) async {
    return Success(services);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  final amla = ServiceItem(
    id: 800000244,
    categoryId: 18,
    title: 'Amlaa (Nellikaai)',
    slug: 'veg-amla',
    price: Decimal.fromInt(64),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final beetroot = ServiceItem(
    id: 800000228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final bitterGourd = ServiceItem(
    id: 800000224,
    categoryId: 18,
    title: 'Bitter Gourd (Pavakkai)',
    slug: 'veg-bitter-gourd',
    price: Decimal.fromInt(17),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final bottleGourd = ServiceItem(
    id: 800000225,
    categoryId: 18,
    title: 'Bottle Gourd (Suraikkai)',
    slug: 'veg-bottle-gourd',
    price: Decimal.fromInt(25),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final allProducts = [amla, beetroot, bitterGourd, bottleGourd];

  final vegCategory = Category(
    id: 18,
    name: 'Farm-Fresh Vegetables & Groceries',
    slug: 'vegetables_groceries',
  );

  final subcats = [
    const Subcategory(id: 50, name: 'Farm-Fresh Vegetable', slug: 'vegetables'),
    const Subcategory(id: 51, name: 'Groceries', slug: 'groceries'),
  ];

}
