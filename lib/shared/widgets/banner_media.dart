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
class _BannerMediaState extends State<BannerMedia> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _failed = false;

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
      controller.play();
    }
  }

  void _onControllerValueChanged() {
    // Video is meant to loop forever with no user-facing pause control —
    // if video_player's own state ever drifts to "paused" while this
    // widget is still mounted and showing it, put it back to playing
    // rather than leaving a static banner on screen.
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.isInitialized && !value.isPlaying && !value.isBuffering) {
      controller.play();
    }
  }

  @override
  void didUpdateWidget(covariant BannerMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A carousel page can be rebuilt with a different banner at the same
    // widget slot (PageView.builder reuses element positions) — re-init
    // the player whenever the actual source changes instead of silently
    // keeping the previous video playing behind new content.
    if (oldWidget.url != widget.url || oldWidget.mediaType != widget.mediaType) {
      final oldController = _controller;
      _controller = null;
      _failed = false;
      oldController?.removeListener(_onControllerValueChanged);
      oldController?.dispose();
      _maybeInitVideo();
    }
  }

  void _maybeInitVideo() {
    if (!widget._isVideo || widget.url == null || widget.url!.isEmpty) {
      return;
    }
    // Fixed 2026-09-21 — root cause of "video not playing, shows the
    // default icon": [widget.url] can be a bare Supabase Storage path
    // (e.g. "homepage/mobile-banners/abc123.mp4") rather than a full
    // URL — the same raw-path-vs-resolved-URL bug fixed in
    // homepage_repository.dart's fromJson methods, kept here too as a
    // second line of defense since [ImageUrlHelper.resolve] is exactly
    // the same "make this fetchable" step [AppRemoteImage] already runs
    // for the image branch below; skipping it only for video was the gap.
    final resolvedUrl = ImageUrlHelper.resolve(widget.url);
    final uri = resolvedUrl == null ? null : Uri.tryParse(resolvedUrl);
    if (uri == null) {
      if (kDebugMode) {
        debugPrint('[BANNER-VIDEO] Could not parse a playable URL from "${widget.url}" (resolved: "$resolvedUrl")');
      }
      _failed = true;
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.setLooping(true);
    controller.setVolume(0);
    controller.addListener(_onControllerValueChanged);
    controller.initialize().then((_) {
      if (!mounted || _controller != controller) return;
      setState(() {});
      controller.play();
    }).catchError((Object error) {
      if (kDebugMode) {
        debugPrint('[BANNER-VIDEO] Failed to initialize $uri: $error');
      }
      if (!mounted || _controller != controller) return;
      setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerValueChanged);
    _controller?.dispose();
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
