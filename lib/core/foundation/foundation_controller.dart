import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/app_update/data/app_version_repository.dart' show InstalledAppReader;
import '../../features/app_update/domain/app_update_controller.dart' show appUpdateStoreProvider, installedAppReaderProvider;
import '../errors/api_error.dart';
import '../network/api_client.dart' show apiClientProvider;
import '../utils/app_logger.dart';
import 'error_reporter.dart';
import 'foundation_models.dart';
import 'foundation_repository.dart';

final foundationRepositoryProvider = Provider<FoundationRepository>(
  (ref) => FoundationRepository(api: ref.watch(apiClientProvider), installId: ref.watch(appUpdateStoreProvider).installId),
);
final foundationCacheProvider = Provider<FoundationCache>((ref) => FoundationCache());
final foundationClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class FoundationState {
  const FoundationState({this.config = FoundationConfig.defaults, this.fromServer = false, this.lastFetchOk});

  final FoundationConfig config;

  /// True once a config from the server (not only the cache) was received this session.
  final bool fromServer;
  final bool? lastFetchOk;

  /// Only an explicit server `maintenance.enabled` for the whole app blocks. A failed fetch never does.
  bool get maintenanceBlocksApp => config.maintenance.blocksApp;

  FoundationState copyWith({FoundationConfig? config, bool? fromServer, bool? lastFetchOk}) => FoundationState(
        config: config ?? this.config,
        fromServer: fromServer ?? this.fromServer,
        lastFetchOk: lastFetchOk ?? this.lastFetchOk,
      );
}

enum FoundationRefresh { startup, resume, maintenancePoll, manual }

class FoundationController extends StateNotifier<FoundationState> {
  FoundationController({
    required FoundationRepository repository,
    required FoundationCache cache,
    required InstalledAppReader installedReader,
    required DateTime Function() clock,
    this.maintenancePollInterval = const Duration(seconds: 30),
  })  : _repo = repository,
        _cache = cache,
        _reader = installedReader,
        _clock = clock,
        super(const FoundationState());

  final FoundationRepository _repo;
  final FoundationCache _cache;
  final InstalledAppReader _reader;
  final DateTime Function() _clock;
  final Duration maintenancePollInterval;

  Timer? _poll;
  bool _fetching = false;
  bool _started = false;
  DateTime? _lastFetch;
  String? _etag;

  /// Cache first (instant, no network), then a background refresh.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final cached = await _cache.read();
    if (cached != null && mounted) {
      _etag = cached.version;
      state = state.copyWith(config: cached);
      _syncPoll();
    }
    await refresh(FoundationRefresh.startup);
  }

  Future<void> refresh(FoundationRefresh reason) async {
    if (_fetching || !mounted) return;
    final now = _clock();
    final minutes = state.config.intSetting('config_refresh_minutes', fallback: 15);
    final throttled = reason == FoundationRefresh.resume &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < Duration(minutes: minutes < 1 ? 1 : minutes);
    if (throttled) return;
    _fetching = true;
    try {
      final installed = await _reader.read();
      final result = await _repo.fetch(version: installed.versionName, build: installed.buildNumber, etag: _etag);
      if (!mounted) return;
      _lastFetch = now;
      switch (result) {
        case Success(:final data):
          if (data.notModified) {
            state = state.copyWith(fromServer: true, lastFetchOk: true);
          } else if (data.config != null) {
            _etag = data.etag;
            state = state.copyWith(config: data.config, fromServer: true, lastFetchOk: true);
            unawaited(_cache.write(data.raw!));
          }
          unawaited(_flushErrors(installed.versionName));
        case Failure(:final error):
          // Fail open: keep whatever config we already have (cache or defaults).
          AppLogger.d('[FOUNDATION]', 'config fetch failed: ${error.message}');
          state = state.copyWith(lastFetchOk: false);
      }
      _syncPoll();
    } finally {
      _fetching = false;
    }
  }

  Future<void> _flushErrors(String version) async {
    final batch = ErrorReporter.drain();
    if (batch.isEmpty) return;
    final sent = await _repo.reportErrors(batch, version: version);
    if (!sent) ErrorReporter.restore(batch);
  }

  /// While the app is blocked for maintenance, or the server is unreachable, re-check every 30 s.
  void _syncPoll() {
    final needed = state.maintenanceBlocksApp || state.lastFetchOk == false;
    if (needed && _poll == null) {
      _poll = Timer.periodic(maintenancePollInterval, (_) => refresh(FoundationRefresh.maintenancePoll));
    } else if (!needed && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

final foundationControllerProvider = StateNotifierProvider<FoundationController, FoundationState>(
  (ref) => FoundationController(
    repository: ref.watch(foundationRepositoryProvider),
    cache: ref.watch(foundationCacheProvider),
    installedReader: ref.watch(installedAppReaderProvider),
    clock: ref.watch(foundationClockProvider),
  ),
);

/// `ref.watch(featureFlagProvider('goods_transport'))` - true unless the server turned it off.
final featureFlagProvider = Provider.family<bool, String>(
  (ref, name) => ref.watch(foundationControllerProvider.select((s) => s.config.flag(name))),
);

/// Typed remote settings, e.g. `ref.watch(remoteConfigProvider).intSetting('max_upload_mb')`.
final remoteConfigProvider = Provider<FoundationConfig>(
  (ref) => ref.watch(foundationControllerProvider.select((s) => s.config)),
);
