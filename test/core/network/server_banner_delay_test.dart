import 'package:calservices_customer/core/network/network_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _state = StateProvider<NetworkState>((ref) => NetworkState.online);

ProviderContainer container() {
  final c = ProviderContainer(overrides: [networkStateProvider.overrideWith((ref) => ref.watch(_state))]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a slow or failed first check does not show the banner straight away', () {
    fakeAsync((async) {
      final c = container();
      c.read(serverBannerVisibleProvider.notifier); // start listening
      c.read(_state.notifier).state = NetworkState.serverUnreachable;
      expect(c.read(serverBannerVisibleProvider), isFalse);
      async.elapse(const Duration(seconds: 19));
      expect(c.read(serverBannerVisibleProvider), isFalse);
    });
  });

  test('a sustained outage shows the banner after the delay', () {
    fakeAsync((async) {
      final c = container();
      c.read(serverBannerVisibleProvider.notifier);
      c.read(_state.notifier).state = NetworkState.serverUnreachable;
      async.elapse(serverBannerDelay + const Duration(seconds: 1));
      expect(c.read(serverBannerVisibleProvider), isTrue);
    });
  });

  test('the banner disappears the moment the server answers again', () {
    fakeAsync((async) {
      final c = container();
      c.read(serverBannerVisibleProvider.notifier);
      c.read(_state.notifier).state = NetworkState.serverUnreachable;
      async.elapse(serverBannerDelay + const Duration(seconds: 1));
      expect(c.read(serverBannerVisibleProvider), isTrue);
      c.read(_state.notifier).state = NetworkState.online;
      expect(c.read(serverBannerVisibleProvider), isFalse);
    });
  });

  test('a blip that recovers before the delay never shows the banner', () {
    fakeAsync((async) {
      final c = container();
      c.read(serverBannerVisibleProvider.notifier);
      c.read(_state.notifier).state = NetworkState.serverUnreachable;
      async.elapse(const Duration(seconds: 10));
      c.read(_state.notifier).state = NetworkState.online;
      async.elapse(const Duration(seconds: 30));
      expect(c.read(serverBannerVisibleProvider), isFalse);
    });
  });

  test('an outage that restarts the clock: unreachable again needs the full delay again', () {
    fakeAsync((async) {
      final c = container();
      c.read(serverBannerVisibleProvider.notifier);
      c.read(_state.notifier).state = NetworkState.serverUnreachable;
      async.elapse(const Duration(seconds: 15));
      c.read(_state.notifier).state = NetworkState.online;
      expect(c.read(serverBannerVisibleProvider), isFalse); // the recovery is seen before it fails again
      c.read(_state.notifier).state = NetworkState.serverUnreachable;
      async.elapse(const Duration(seconds: 15));
      expect(c.read(serverBannerVisibleProvider), isFalse);
      async.elapse(const Duration(seconds: 6));
      expect(c.read(serverBannerVisibleProvider), isTrue);
    });
  });
}
