import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../domain/catalog_models.dart';

/// A product card's photo. With one image it is just that image; with several
/// (the vendor's gallery) they slide by themselves every few seconds — the same
/// pictures the product page carousel shows — and can be swiped, with small
/// dots underneath.
///
/// Taps are left to the card around it (a horizontal swipe is the only gesture
/// this widget claims), and a card's slide timer is offset from its neighbours
/// so a whole grid doesn't flip in unison.
class ProductImageSlider extends StatefulWidget {
  const ProductImageSlider({
    super.key,
    required this.service,
    this.fit = BoxFit.cover,
    this.interval = const Duration(milliseconds: 3600),
  });

  final ServiceItem service;
  final BoxFit fit;
  final Duration interval;

  @override
  State<ProductImageSlider> createState() => _ProductImageSliderState();
}

class _ProductImageSliderState extends State<ProductImageSlider> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  List<String> get _images {
    final out = <String>[];
    for (final u in [
      if ((widget.service.imageUrl ?? '').isNotEmpty) widget.service.imageUrl!,
      ...widget.service.galleryImages,
    ]) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _scheduleStart();
  }

  @override
  void didUpdateWidget(covariant ProductImageSlider old) {
    super.didUpdateWidget(old);
    if (old.service.id != widget.service.id) {
      _timer?.cancel();
      if (_controller.hasClients) _controller.jumpToPage(0);
      _page = 0;
      _scheduleStart();
    }
  }

  void _scheduleStart() {
    if (_images.length < 2) return;
    // Offset each card a little so neighbours slide at different moments.
    final offset = Duration(milliseconds: (widget.service.id.abs() % 5) * 500);
    _timer = Timer(offset, () {
      _timer = Timer.periodic(widget.interval, (_) => _next());
    });
  }

  void _next() {
    if (!mounted || !_controller.hasClients) return;
    final count = _images.length;
    if (count < 2) return;
    final target = (_page + 1) % count;
    if (target == 0) {
      _controller.animateToPage(0,
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    } else {
      _controller.animateToPage(target,
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _image(String url) => AppRemoteImage(
        imageUrl: url,
        rawPath: url,
        title: widget.service.title,
        categoryName: widget.service.categoryName,
        slug: widget.service.slug,
        semanticIcon:
            ImageUrlHelper.mapCategoryIcon(widget.service.categoryName, widget.service.slug),
        width: double.infinity,
        height: double.infinity,
        fit: widget.fit,
      );

  @override
  Widget build(BuildContext context) {
    final images = _images;
    if (images.length < 2) {
      return _image(images.isEmpty ? (widget.service.imageUrl ?? '') : images.first);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: images.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => _image(images[i]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: i == _page ? 12 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.55),
                      boxShadow: const [
                        BoxShadow(color: Color(0x40000000), blurRadius: 3),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
