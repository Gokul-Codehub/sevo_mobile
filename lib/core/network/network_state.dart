import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../foundation/foundation_controller.dart';
import '../services/connectivity_service.dart';

/// What the customer can actually rely on right now.
///  * offline            - the phone has no network at all (the existing No Internet screen covers this)
///  * serverUnreachable  - the phone is online but SEVO's server could not be reached (slim banner, app stays usable)
///  * online             - everything normal
enum NetworkState { online, offline, serverUnreachable }

/// True while Home shows its full-screen loader (nothing has loaded yet). That loader already says what is happening, so
/// the top "could not reach SEVO" banner stays out of its way.
final fullScreenLoaderActiveProvider = StateProvider<bool>((ref) => false);

/// How long the server must stay unreachable before the "could not reach SEVO" banner appears. Until then the screens'
/// own loaders + skeletons carry the wait: a slow first answer is not worth a warning, a real outage is.
const Duration serverBannerDelay = Duration(seconds: 20);

/// Whether to show the "could not reach SEVO" banner: only once the server has been unreachable for
/// [serverBannerDelay] without a break, and it goes away the moment the server answers again.
final serverBannerVisibleProvider = StateNotifierProvider<_ServerBannerDelay, bool>((ref) => _ServerBannerDelay(ref));

class _ServerBannerDelay extends StateNotifier<bool> {
  _ServerBannerDelay(Ref ref, {Duration delay = serverBannerDelay}) : super(false) {
    ref.listen<NetworkState>(networkStateProvider, (previous, next) {
      _timer?.cancel();
      if (next == NetworkState.serverUnreachable) {
        _timer = Timer(delay, () {
          if (mounted) state = true;
        });
      } else {
        state = false;
      }
    }, fireImmediately: true);
    ref.onDispose(() => _timer?.cancel());
  }

  Timer? _timer;
}

final networkStateProvider = Provider<NetworkState>((ref) {
  final link = ref.watch(connectivityStatusProvider).valueOrNull;
  if (link == false) return NetworkState.offline;
  final serverOk = ref.watch(foundationControllerProvider.select((s) => s.lastFetchOk));
  if (serverOk == false) return NetworkState.serverUnreachable;
  return NetworkState.online;
});
