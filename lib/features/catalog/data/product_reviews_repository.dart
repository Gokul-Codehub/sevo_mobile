import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';

class ProductReview {
  const ProductReview({required this.id, required this.rating, required this.headline, required this.comment, required this.reviewerName, required this.photos, required this.isMine, this.createdAt});
  final int id;
  final int rating;
  final String headline;
  final String comment;
  final String reviewerName;
  final List<String> photos;
  final bool isMine;
  final DateTime? createdAt;

  static ProductReview? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse(raw['id']?.toString() ?? '');
    final rating = int.tryParse(raw['rating']?.toString() ?? '');
    if (id == null || rating == null) return null;
    final photos = raw['photos'];
    return ProductReview(
      id: id,
      rating: rating.clamp(1, 5),
      headline: (raw['headline'] ?? '').toString(),
      comment: (raw['comment'] ?? '').toString(),
      reviewerName: (raw['reviewer_name'] ?? '').toString(),
      photos: [
        if (photos is List)
          for (final p in photos)
            if (p is Map && (p['image_url'] ?? '').toString().isNotEmpty) p['image_url'].toString(),
      ],
      isMine: raw['is_mine'] == true,
      createdAt: DateTime.tryParse((raw['created_at'] ?? '').toString())?.toLocal(),
    );
  }
}

class ReviewSummary {
  const ReviewSummary({this.average = 0, this.count = 0, this.distribution = const {}});
  final double average;
  final int count;

  /// stars (1..5) -> how many reviews
  final Map<int, int> distribution;

  static ReviewSummary parse(Object? raw) {
    if (raw is! Map) return const ReviewSummary();
    final d = raw['distribution'];
    return ReviewSummary(
      average: double.tryParse(raw['average']?.toString() ?? '') ?? 0,
      count: int.tryParse(raw['count']?.toString() ?? '') ?? 0,
      distribution: {
        if (d is Map)
          for (final e in d.entries)
            if (int.tryParse(e.key.toString()) != null) int.parse(e.key.toString()): int.tryParse(e.value.toString()) ?? 0,
      },
    );
  }
}

class ReviewsPage {
  const ReviewsPage({required this.summary, required this.results, this.mine, this.numPages = 1});
  final ReviewSummary summary;
  final List<ProductReview> results;
  final ProductReview? mine;
  final int numPages;
}

/// Whether this customer may review the product (they must have received it), and any review they already left.
class ReviewEligibility {
  const ReviewEligibility({required this.eligible, this.reason = '', this.existing});
  final bool eligible;
  final String reason;
  final ProductReview? existing;

  bool get canWrite => eligible && existing == null;

  /// What to tell a customer who cannot review yet.
  String get explanation => switch (reason.toUpperCase()) {
        'NOT_LOGGED_IN' => 'Sign in to review this product.',
        'NOT_PURCHASED' || 'NO_DELIVERED_ORDER' || 'NOT_ELIGIBLE' => 'Only customers who received this product can review it.',
        _ => 'You can review this product after it is delivered to you.',
      };
}

class ProductReviewsRepository {
  ProductReviewsRepository({required this.api});
  final ApiClient api;

  /// `GET /api/marketplace/products/<id>/reviews/`
  Future<Result<ReviewsPage>> list(int productId, {int page = 1}) async {
    try {
      final response = await api.get('/marketplace/products/$productId/reviews/', queryParameters: {'page': page, 'page_size': 10});
      final m = response.data is Map ? response.data as Map : const {};
      final results = m['results'];
      return Success(ReviewsPage(
        summary: ReviewSummary.parse(m['summary']),
        results: [if (results is List) for (final r in results) ?ProductReview.tryParse(r)],
        mine: ProductReview.tryParse(m['mine']),
        numPages: int.tryParse(m['num_pages']?.toString() ?? '') ?? 1,
      ));
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// `GET /api/marketplace/products/<id>/review-eligibility/`
  Future<Result<ReviewEligibility>> eligibility(int productId) async {
    try {
      final response = await api.get('/marketplace/products/$productId/review-eligibility/');
      final m = response.data is Map ? response.data as Map : const {};
      return Success(ReviewEligibility(eligible: m['eligible'] == true, reason: (m['reason'] ?? '').toString(), existing: ProductReview.tryParse(m['existing_review'])));
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// Uploads one review photo and returns its URL. Photos go up first; the review then carries their URLs.
  Future<Result<String>> uploadPhoto(int productId, XFile file) async {
    try {
      final form = FormData.fromMap({'file': MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name.isEmpty ? 'review.jpg' : file.name)});
      final response = await api.post('/marketplace/products/$productId/reviews/photos/', data: form);
      final url = (response.data is Map ? (response.data as Map)['image_url'] : null)?.toString() ?? '';
      return url.isEmpty ? const Failure(ValidationError('Could not upload the photo.')) : Success(url);
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// Creates the customer's review, or updates it when [update] (they have one already).
  Future<Result<void>> submit(int productId, {required int rating, required String headline, required String comment, required List<String> photoUrls, bool update = false}) async {
    final body = {'rating': rating, 'headline': headline.trim(), 'comment': comment.trim(), 'photo_urls': photoUrls};
    try {
      if (update) {
        await api.patch('/marketplace/products/$productId/reviews/mine/', data: body);
      } else {
        await api.post('/marketplace/products/$productId/reviews/', data: body);
      }
      return const Success(null);
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// `DELETE /api/marketplace/products/<id>/reviews/mine/`
  Future<Result<void>> deleteMine(int productId) async {
    try {
      await api.delete('/marketplace/products/$productId/reviews/mine/');
      return const Success(null);
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  ApiError _err(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) return e.error! as ApiError;
    return const NetworkError();
  }
}

final productReviewsRepositoryProvider = Provider<ProductReviewsRepository>((ref) => ProductReviewsRepository(api: ref.watch(apiClientProvider)));

final productReviewsProvider = FutureProvider.autoDispose.family<ReviewsPage, int>((ref, id) async {
  final r = await ref.watch(productReviewsRepositoryProvider).list(id);
  return switch (r) {
    Success(:final data) => data,
    Failure() => const ReviewsPage(summary: ReviewSummary(), results: []), // no reviews showing beats an error on the product page
  };
});

final reviewEligibilityProvider = FutureProvider.autoDispose.family<ReviewEligibility, int>((ref, id) async {
  final r = await ref.watch(productReviewsRepositoryProvider).eligibility(id);
  return switch (r) {
    Success(:final data) => data,
    Failure() => const ReviewEligibility(eligible: false, reason: 'UNKNOWN'),
  };
});
