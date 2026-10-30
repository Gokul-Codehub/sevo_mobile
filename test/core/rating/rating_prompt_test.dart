import 'package:calservices_customer/core/rating/rating_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform implements ReviewPlatform {
  bool available = true;
  int requests = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> requestReview() async => requests++;
}

class MemStore extends RatingPromptStore {
  DateTime? last;
  int count = 0;
  @override
  Future<DateTime?> lastPrompt() async => last;
  @override
  Future<void> setLastPrompt(DateTime t) async => last = t;
  @override
  Future<int> submissions() async => count;
  @override
  Future<void> setSubmissions(int n) async => count = n;
}

void main() {
  late FakePlatform platform;
  late MemStore store;
  late DateTime now;
  late RatingPromptManager manager;

  setUp(() {
    platform = FakePlatform();
    store = MemStore();
    now = DateTime(2026, 11, 1);
    manager = RatingPromptManager(platform: platform, store: store, clock: () => now);
  });

  test('never on the very first rating, even with 5 stars', () async {
    expect(await manager.afterRating(stars: 5), isFalse);
    expect(platform.requests, 0);
  });

  test('second good rating asks for a store review', () async {
    await manager.afterRating(stars: 5);
    expect(await manager.afterRating(stars: 4), isTrue);
    expect(platform.requests, 1);
  });

  test('a low rating never reaches the store', () async {
    await manager.afterRating(stars: 5);
    expect(await manager.afterRating(stars: 3), isFalse);
    expect(await manager.afterRating(stars: 1), isFalse);
    expect(platform.requests, 0);
  });

  test('at most once every 90 days', () async {
    await manager.afterRating(stars: 5);
    await manager.afterRating(stars: 5);
    expect(platform.requests, 1);
    now = now.add(const Duration(days: 30));
    expect(await manager.afterRating(stars: 5), isFalse);
    now = now.add(const Duration(days: 61));
    expect(await manager.afterRating(stars: 5), isTrue);
    expect(platform.requests, 2);
  });

  test('the remote flag switches it off', () async {
    await manager.afterRating(stars: 5, enabled: false);
    expect(await manager.afterRating(stars: 5, enabled: false), isFalse);
    expect(platform.requests, 0);
  });

  test('store dialog unavailable: no prompt, no crash, and it is not counted as prompted', () async {
    platform.available = false;
    await manager.afterRating(stars: 5);
    expect(await manager.afterRating(stars: 5), isFalse);
    expect(store.last, isNull);
  });
}
