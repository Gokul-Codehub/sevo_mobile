import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_review/in_app_review.dart';

/// Seam over the store's in-app review dialog (so the rules are testable).
abstract class ReviewPlatform {
  Future<bool> isAvailable();
  Future<void> requestReview();
}

class InAppReviewPlatform implements ReviewPlatform {
  const InAppReviewPlatform();
  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();
  @override
  Future<void> requestReview() => InAppReview.instance.requestReview();
}

class RatingPromptStore {
  RatingPromptStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final FlutterSecureStorage _storage;
  static const _kLastPrompt = 'sevo_rating_last_prompt';
  static const _kRatings = 'sevo_rating_submissions';

  Future<DateTime?> lastPrompt() async {
    try {
      return DateTime.tryParse(await _storage.read(key: _kLastPrompt) ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastPrompt(DateTime t) async {
    try {
      await _storage.write(key: _kLastPrompt, value: t.toIso8601String());
    } catch (_) {}
  }

  Future<int> submissions() async {
    try {
      return int.tryParse(await _storage.read(key: _kRatings) ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setSubmissions(int n) async {
    try {
      await _storage.write(key: _kRatings, value: '$n');
    } catch (_) {}
  }
}

/// Asks for a store rating only at a good moment: right after the customer gave 4 or 5 stars, never after
/// their first rating, at most once every 90 days, and only while the remote flag allows it.
/// A low rating never leads to the store - the customer's own feedback is the right place for it.
class RatingPromptManager {
  RatingPromptManager({ReviewPlatform? platform, RatingPromptStore? store, DateTime Function()? clock})
      : _platform = platform ?? const InAppReviewPlatform(),
        _store = store ?? RatingPromptStore(),
        _clock = clock ?? DateTime.now;

  static final RatingPromptManager instance = RatingPromptManager();
  static const Duration minGap = Duration(days: 90);

  final ReviewPlatform _platform;
  final RatingPromptStore _store;
  final DateTime Function() _clock;

  /// Call after a rating was submitted. Returns true if the store dialog was requested.
  Future<bool> afterRating({required int stars, bool enabled = true}) async {
    try {
      final count = (await _store.submissions()) + 1;
      await _store.setSubmissions(count);
      if (!enabled || stars < 4 || count < 2) return false;
      final last = await _store.lastPrompt();
      final now = _clock();
      if (last != null && now.difference(last) < minGap) return false;
      if (!await _platform.isAvailable()) return false;
      await _store.setLastPrompt(now);
      await _platform.requestReview();
      return true;
    } catch (_) {
      return false;
    }
  }
}
