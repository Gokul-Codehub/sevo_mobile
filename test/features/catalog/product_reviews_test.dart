import 'dart:typed_data';
import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/catalog/data/product_reviews_repository.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/product_reviews_section.dart';
import 'package:calservices_customer/shared/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _Repo extends ProductReviewsRepository {
  _Repo({this.page = const ReviewsPage(summary: ReviewSummary(), results: []), this.eligible = const ReviewEligibility(eligible: false)}) : super(api: ApiClient.withDio(Dio()));
  final ReviewsPage page;
  final ReviewEligibility eligible;
  final submitted = <({int rating, String headline, String comment, List<String> photos, bool update})>[];
  final uploaded = <String>[];
  var deleted = 0;

  @override
  Future<Result<ReviewsPage>> list(int productId, {int page = 1}) async => Success(this.page);
  @override
  Future<Result<ReviewEligibility>> eligibility(int productId) async => Success(eligible);
  @override
  Future<Result<String>> uploadPhoto(int productId, XFile file) async {
    uploaded.add(file.name);
    return Success('https://cdn.test/${file.name}');
  }

  @override
  Future<Result<void>> submit(int productId, {required int rating, required String headline, required String comment, required List<String> photoUrls, bool update = false}) async {
    submitted.add((rating: rating, headline: headline, comment: comment, photos: photoUrls, update: update));
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteMine(int productId) async {
    deleted++;
    return const Success(null);
  }
}

ReviewsPage reviews({int count = 3}) => ReviewsPage(
      summary: ReviewSummary(average: 4.3, count: count, distribution: const {5: 2, 4: 0, 3: 1, 2: 0, 1: 0}),
      results: [
        ProductReview.tryParse({'id': 1, 'rating': 5, 'headline': 'Fresh!', 'comment': 'Great bread', 'reviewer_name': 'Asha K.', 'photos': [], 'is_mine': false})!,
        ProductReview.tryParse({'id': 2, 'rating': 3, 'headline': '', 'comment': 'Okay', 'reviewer_name': 'Ravi', 'photos': [{'image_url': 'https://cdn.test/a.webp'}], 'is_mine': true})!,
      ],
    );

Future<void> pump(WidgetTester tester, _Repo repo, {Widget? child}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [productReviewsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: child ?? const ProductReviewsSection(productId: 5)))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('parsing: reviews, photos and the summary distribution', () {
    final r = ProductReview.tryParse({'id': 9, 'rating': 7, 'photos': [{'image_url': 'u1'}, {'image_url': ''}, 'junk']})!;
    expect(r.rating, 5); // rating is kept within 1..5
    expect(r.photos, ['u1']);
    expect(ProductReview.tryParse({'rating': 4}), isNull);
    final s = ReviewSummary.parse({'average': '4.5', 'count': 4, 'distribution': {'5': 3, '4': 1}});
    expect((s.average, s.count, s.distribution[5], s.distribution[4]), (4.5, 4, 3, 1));
    expect(ReviewSummary.parse(null).count, 0);
  });

  test('who may write: only an eligible customer without a review yet', () {
    expect(const ReviewEligibility(eligible: true).canWrite, isTrue);
    expect(ReviewEligibility(eligible: true, existing: ProductReview.tryParse({'id': 1, 'rating': 4})).canWrite, isFalse);
    expect(const ReviewEligibility(eligible: false, reason: 'NOT_LOGGED_IN').explanation, contains('Sign in'));
  });

  group('section', () {
    testWidgets('a product with no reviews and a customer who cannot review shows nothing', (tester) async {
      await pump(tester, _Repo());
      expect(find.text('Ratings & reviews'), findsNothing);
    });

    testWidgets('shows the summary and what customers wrote; my own review has Edit', (tester) async {
      await pump(tester, _Repo(page: reviews(), eligible: const ReviewEligibility(eligible: false)));
      expect(find.text('Ratings & reviews'), findsOneWidget);
      expect(find.text('4.3'), findsOneWidget);
      expect(find.text('3 reviews'), findsOneWidget);
      expect(find.text('Great bread'), findsOneWidget);
      expect(find.text('Asha K.'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('an eligible customer with no review of their own is offered Write a review', (tester) async {
      await pump(tester, _Repo(page: reviews(), eligible: const ReviewEligibility(eligible: true)));
      expect(find.text('Write a review'), findsOneWidget);
    });

    testWidgets('a product nobody reviewed still offers a first review to someone who received it', (tester) async {
      await pump(tester, _Repo(eligible: const ReviewEligibility(eligible: true)));
      expect(find.text('Write a review'), findsOneWidget);
    });
  });

  group('review form', () {
    testWidgets('a star rating is required', (tester) async {
      final repo = _Repo();
      await pump(tester, repo, child: ReviewFormSheet(productId: 5));
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(repo.submitted, isEmpty);
    });

    testWidgets('submits stars, headline, comment and the uploaded photo urls', (tester) async {
      final repo = _Repo();
      await pump(tester, repo, child: ReviewFormSheet(productId: 5, pickPhoto: (_) async => XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'pic.jpg')));
      await tester.tap(find.byKey(const ValueKey('star-4')));
      await tester.enterText(find.widgetWithText(TextField, 'Headline (optional)'), 'Good');
      await tester.enterText(find.widgetWithText(TextField, 'Your review (optional)'), 'Fresh and soft');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      final s = repo.submitted.single;
      expect((s.rating, s.headline, s.comment, s.update), (4, 'Good', 'Fresh and soft', false));
    });

    testWidgets('editing keeps the stars and text and saves as an update', (tester) async {
      final repo = _Repo();
      final mine = ProductReview.tryParse({'id': 2, 'rating': 3, 'headline': 'Meh', 'comment': 'Okay', 'photos': [{'image_url': 'https://cdn.test/a.webp'}], 'is_mine': true})!;
      await pump(tester, repo, child: ReviewFormSheet(productId: 5, existing: mine));
      expect(find.text('Edit your review'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final s = repo.submitted.single;
      expect((s.rating, s.headline, s.update), (3, 'Meh', true));
      expect(s.photos, ['https://cdn.test/a.webp']);
    });

    testWidgets('delete asks first', (tester) async {
      final repo = _Repo();
      final mine = ProductReview.tryParse({'id': 2, 'rating': 3, 'is_mine': true})!;
      await pump(tester, repo, child: ReviewFormSheet(productId: 5, existing: mine));
      await tester.tap(find.text('Delete review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(repo.deleted, 0);
      await tester.tap(find.text('Delete review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, 1);
    });
  });
}
