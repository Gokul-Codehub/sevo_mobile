import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/image_url_helper.dart';
import 'app_remote_image.dart';
import 'common_widgets.dart';

/// Renders a single admin-uploaded banner/advertisement asset — either a
/// still image (the existing behavior, via [AppRemoteImage]) or a short
/// looping video — chosen by [mediaType].
///
/// Added 2026-09-21 per explicit request ("the banners and advertisement
/// could allow admin to upload video and images... and that should be
/// reflected in mobile application"): the admin's Mobile App ▸ Banners /
/// Advertisement tabs now accept a video file in addition to an image
/// (see HomePageImageUploadAPIView.post's video branch on the backend),
/// tagged with a `mediaType` field that homepage_repository.dart parses
/// onto [MobileMediaItem]/[HomeOffer]. This widget is the one place that
/// decides how to actually render whichever kind the admin uploaded, so
/// both banner call sites in home_screen.dart (_PromoBannerSlide and
/// _MobileAdCard) stay in sync automatically instead of duplicating this
/// logic twice.
///
/// A video banner autoplays muted and loops silently, like a real ad
/// banner or a social app's "photo mode" video — no controls, no sound,
/// since this is decorative promotional content, not something the
/// customer is meant to scrub through. Falls back to the same semantic
/// placeholder [AppRemoteImage] uses if the video fails to load, so a bad
/// upload (wrong codec, dead URL) can never leave the carousel visibly
/// broken.
class BannerMedia extends StatefulWidget {
  const BannerMedia({
    super.key,
    required this.url,
    this.mediaType = 'image',
    this.title,
    this.semanticIcon,
    this.fit = BoxFit.cover,
  });

  /// Resolved image or video URL. Null/empty is handled by the caller
  /// (both current call sites only construct this widget once they know
  /// they have a real URL) but is tolerated here too, falling through to
  /// [AppRemoteImage]'s own null-safe placeholder behavior.
  final String? url;

  /// 'image' or 'video' — anything else is treated as 'image'.
  final String mediaType;

  final String? title;
  final IconData? semanticIcon;
  final BoxFit fit;

  bool get _isVideo => mediaType == 'video';

  @override
  State<BannerMedia> createState() => _BannerMediaState();
}

// Fixed 2026-09-21 per explicit report ("the video should not pause it
// should autoplay automatically"): a plain `controller.play()` right
// after `initialize()` only starts playback once — it does nothing to
// recover if the OS/plugin pauses the underlying player later (the
// documented Android behavior when the app is backgrounded and the
// video's surface texture is torn down, or a transient platform-channel
// hiccup), so the banner could end up sitting on a frozen frame with no
// way to resume on its own. Now a WidgetsBindingObserver resumes playback
// whenever the app returns to the foreground, and a value listener on the
// controller itself re-asserts play() any time video_player reports the
// video as paused while this widget is still showing it — since this is a
// decorative, no-controls autoplay loop, there's never a legitimate
// "the user meant to pause this" state to respect.
/// App-wide cache of banner video players, keyed by resolved URL.
///
/// Added 2026-10-09 ("the loading of the video in the banner is getting
/// the API each time of page switching ... make it one time loader"):
/// every [BannerMedia] used to create and dispose its own
/// [VideoPlayerController], so each switch between Home / Groceries /
/// Services (or any rebuild that remounted the banner) re-downloaded and
/// re-initialised the same video. Controllers now outlive the widgets:
/// the first mount initialises one controller per URL, later mounts reuse
/// it instantly (already decoded, no network), and unmounting only pauses
/// it. A small cap evicts the least recently used unreferenced players.
class _BannerVideoEntry {
  _BannerVideoEntry(this.controller);

  final VideoPlayerController controller;
  int refs = 0;
  bool failed = false;
  bool initializing = true;
  Future<void>? initFuture;
  int lastUsed = 0;
}

class _BannerVideoCache {
  static final Map<String, _BannerVideoEntry> _entries = {};
  static const int _maxEntries = 4;
  static int _tick = 0;

  static _BannerVideoEntry acquire(Uri uri) {
    final key = uri.toString();
    var entry = _entries[key];
    if (entry == null || entry.failed) {
      if (entry != null) {
        _entries.remove(key);
        entry.controller.dispose();
      }
      // Banner videos are always silent: mixWithOthers stops the player from
      // taking audio focus, so it can never pause the user's music either.
      final controller = VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      controller.setLooping(true);
      controller.setVolume(0);
      entry = _BannerVideoEntry(controller);
      final created = entry;
      created.initFuture = controller.initialize().then((_) {
        created.initializing = false;
        controller.setVolume(0);
      }).catchError((Object error) {
        created.initializing = false;
        created.failed = true;
        if (kDebugMode) {
          debugPrint('[BANNER-VIDEO] Failed to initialize $uri: $error');
        }
      });
      _entries[key] = created;
      _evict();
    }
    entry.refs++;
    entry.lastUsed = ++_tick;
    return entry;
  }

  static void release(_BannerVideoEntry entry) {
    entry.refs = entry.refs > 0 ? entry.refs - 1 : 0;
    entry.lastUsed = ++_tick;
    if (entry.refs == 0 && entry.controller.value.isInitialized) {
      // Keep it warm for the next mount; just stop decoding while hidden.
      entry.controller.pause();
    }
    if (entry.failed && entry.refs == 0) {
      _entries.removeWhere((_, e) => identical(e, entry));
      entry.controller.dispose();
    }
  }

  static void _evict() {
    while (_entries.length > _maxEntries) {
      final idle = _entries.entries.where((e) => e.value.refs == 0).toList()
        ..sort((x, y) => x.value.lastUsed.compareTo(y.value.lastUsed));
      if (idle.isEmpty) return;
      final victim = idle.first;
      _entries.remove(victim.key);
      victim.value.controller.dispose();
    }
  }
}

class _BannerMediaState extends State<BannerMedia> with WidgetsBindingObserver {
  _BannerVideoEntry? _entry;
  bool _failed = false;

  VideoPlayerController? get _controller => _entry?.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maybeInitVideo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeIfNeeded();
    }
  }

  void _resumeIfNeeded() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isPlaying) {
      controller
        ..setVolume(0)
        ..play();
    }
  }

  void _onControllerValueChanged() {
    // Video is meant to loop forever with no user-facing pause control —
    // if video_player's own state ever drifts to "paused" while this
    // widget is still mounted and showing it, put it back to playing.
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.isInitialized && !value.isPlaying && !value.isBuffering) {
      controller
        ..setVolume(0)
        ..play();
    }
  }

  void _detach() {
    final entry = _entry;
    if (entry == null) return;
    entry.controller.removeListener(_onControllerValueChanged);
    _entry = null;
    _BannerVideoCache.release(entry);
  }

  @override
  void didUpdateWidget(covariant BannerMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.mediaType != widget.mediaType) {
      _detach();
      _failed = false;
      _maybeInitVideo();
    }
  }

  void _maybeInitVideo() {
    if (!widget._isVideo || widget.url == null || widget.url!.isEmpty) {
      return;
    }
    // [widget.url] can be a bare storage path rather than a full URL —
    // resolve it the same way [AppRemoteImage] does for stills.
    final resolvedUrl = ImageUrlHelper.resolve(widget.url);
    final uri = resolvedUrl == null ? null : Uri.tryParse(resolvedUrl);
    if (uri == null) {
      if (kDebugMode) {
        debugPrint('[BANNER-VIDEO] Could not parse a playable URL from "${widget.url}" (resolved: "$resolvedUrl")');
      }
      _failed = true;
      return;
    }
    final entry = _BannerVideoCache.acquire(uri);
    _entry = entry;
    final controller = entry.controller;
    controller.addListener(_onControllerValueChanged);
    if (controller.value.isInitialized) {
      // Cache hit: already decoded — show immediately and resume.
      controller
        ..setVolume(0)
        ..play();
      return;
    }
    entry.initFuture?.then((_) {
      if (!mounted || _entry != entry) return;
      if (entry.failed) {
        setState(() => _failed = true);
        return;
      }
      setState(() {});
      controller
        ..setVolume(0)
        ..play();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget._isVideo && !_failed && widget.url != null && widget.url!.isNotEmpty) {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        return SizedBox.expand(
          child: FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        );
      }
      // First frame hasn't decoded yet — same loading look AppRemoteImage
      // shows for a still-loading image, never a blank gap.
      return const ShimmerBox(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
      );
    }

    return AppRemoteImage(
      imageUrl: widget.url,
      rawPath: widget.url,
      title: widget.title,
      semanticIcon: widget.semanticIcon,
      width: double.infinity,
      height: double.infinity,
      fit: widget.fit,
    );
  }
}
