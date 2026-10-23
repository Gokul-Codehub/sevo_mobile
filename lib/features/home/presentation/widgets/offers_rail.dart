import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../booking/data/coupon_repository.dart';
import '../../data/home_studio_repository.dart';
import 'studio_title.dart';
import '../../../../shared/utils/date_utils.dart';

/// Home Studio "Offers & Coupons" carousel: ticket-style cards for real,
/// admin-published coupons only (the live /customer/coupons/ list), so an
/// expired or paused coupon disappears by itself. The admin chooses which
/// coupons appear and in what order (settings.coupons), gives each one an
/// optional background image, and controls autoplay / indicators.
class OffersRail extends ConsumerStatefulWidget {
  const OffersRail({super.key, required this.section});

  final StudioSection section;

  @override
  ConsumerState<OffersRail> createState() => _OffersRailState();
}

class _OffersRailState extends ConsumerState<OffersRail> {
  PageController? _controller;
  Timer? _timer;
  int _page = 0;
  int _count = 0;
  bool _single = false;

  static Color _hex(dynamic raw, Color fallback) {
    final h = (raw ?? '').toString().trim().replaceAll('#', '');
    if (h.length != 6 && h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return fallback;
    return Color(h.length == 6 ? (0xFF000000 | v) : v);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// (Re)builds the page controller / autoplay timer when the number of
  /// cards changes, without touching state during build.
  void _sync(int count) {
    final single = count <= 1;
    if (_controller != null && count == _count && single == _single) return;
    _count = count;
    _single = single;
    _timer?.cancel();
    final old = _controller;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _page = 0;
    _controller = PageController(viewportFraction: single ? 1.0 : 0.9);
    final auto = widget.section.flag('autoplay', fallback: true);
    if (auto && count > 1) {
      final secs = widget.section.intSetting('interval_seconds', 4).clamp(2, 15).toInt();
      _timer = Timer.periodic(Duration(seconds: secs), (_) {
        final c = _controller;
        if (!mounted || c == null || !c.hasClients) return;
        final next = (_page + 1) % _count;
        c.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final st = section.settings;
    final showAll = section.flag('show_all');
    final picked = <Map<String, dynamic>>[
      if (st['coupons'] is List)
        for (final c in st['coupons'] as List)
          if (c is Map) Map<String, dynamic>.from(c),
    ];
    if (!showAll && picked.isEmpty) return const SizedBox.shrink();

    final async = ref.watch(availableCouponsProvider);
    return async.maybeWhen(
      data: (all) {
        // Each card = a coupon + the admin's optional background image.
        final cards = <({Coupon coupon, String image})>[];
        if (showAll) {
          for (final c in all) {
            cards.add((coupon: c, image: ''));
          }
        } else {
          for (final p in picked) {
            final id = (p['id'] ?? '').toString();
            final code = (p['code'] ?? '').toString().toUpperCase();
            final match = all.where((c) => (id.isNotEmpty && c.id == id) || (code.isNotEmpty && c.code.toUpperCase() == code));
            if (match.isEmpty) continue;
            if (cards.any((x) => x.coupon == match.first)) continue;
            cards.add((coupon: match.first, image: (p['image'] ?? '').toString().trim()));
          }
        }
        if (cards.isEmpty) return const SizedBox.shrink();
        _sync(cards.length);

        final cardColor = _hex(st['card_color'], const Color(0xFFE6F2FD));
        final accent = _hex(st['accent_color'], const Color(0xFF0B3A6B));
        final lightText = (st['image_text_color'] ?? 'light').toString() != 'dark';
        final overlay = section.flag('image_overlay', fallback: true);
        final dots = section.flag('indicators', fallback: true) && cards.length > 1;
        final title = section.title.isNotEmpty ? section.title : 'Offers For You';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: StudioTitle(text: title, imageUrl: section.titleImage, font: section.titleFont, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            ),
            SizedBox(
              height: 96,
              child: PageView.builder(
                controller: _controller,
                padEnds: _single,
                itemCount: cards.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: _single ? 16 : 5),
                  child: _OfferTicket(
                    coupon: cards[i].coupon,
                    image: cards[i].image,
                    color: cardColor,
                    accent: accent,
                    lightText: lightText,
                    overlay: overlay,
                  ),
                ),
              ),
            ),
            if (dots)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < cards.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page ? accent : accent.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _OfferTicket extends StatelessWidget {
  const _OfferTicket({
    required this.coupon,
    required this.image,
    required this.color,
    required this.accent,
    required this.lightText,
    required this.overlay,
  });

  final Coupon coupon;
  final String image;
  final Color color;
  final Color accent;
  final bool lightText;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final hasImage = image.isNotEmpty;
    final hasMin = coupon.minBooking > Decimal.zero;
    final detail = hasMin ? 'Code ${coupon.code} · On orders above \u20b9${coupon.minBooking}' : 'Code ${coupon.code}';
    final head = hasImage ? (lightText ? Colors.white : const Color(0xFF111827)) : const Color(0xFF111827);
    final sub = hasImage ? (lightText ? Colors.white.withOpacity(0.9) : const Color(0xFF374151)) : const Color(0xFF4B5563);
    return GestureDetector(
      onTap: () => _showCouponDetails(context, coupon, accent),
      child: ClipPath(
        clipper: _TicketClipper(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: color),
            if (hasImage) ...[
              AppRemoteImage(imageUrl: image, fit: BoxFit.cover),
              if (overlay)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: lightText
                          ? [Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.15)]
                          : [Colors.white.withOpacity(0.7), Colors.white.withOpacity(0.15)],
                    ),
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coupon.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w800, color: head),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: sub),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 24, color: hasImage ? head : accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded rectangle with a half-circle bite out of the middle of the left and
/// right edges, like a ticket.
class _TicketClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const r = 9.0;
    final body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, size.height / 2), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(size.width, size.height / 2), radius: r));
    return Path.combine(PathOperation.difference, body, holes);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Terms built only from what the coupon really says; nothing is invented.
List<String> _termsFor(Coupon c) {
  final out = <String>[];
  if (c.description.trim().isNotEmpty) out.add(c.description.trim());
  if (c.minBooking > Decimal.zero) out.add('Valid on orders above ₹${c.minBooking}.');
  if (c.isPercentage && c.maxDiscount > Decimal.zero) out.add('Maximum discount ₹${c.maxDiscount} per order.');
  final cust = c.customerEligibility.trim();
  if (cust.isNotEmpty && cust.toLowerCase() != 'all customers') out.add('Applicable for: $cust.');
  final svc = c.serviceEligibility.trim();
  if (svc.isNotEmpty && svc.toLowerCase() != 'all services') out.add('Applicable on: $svc.');
  final e = c.expiresAt;
  if (e != null) out.add('Valid till ${formatDmy(e)}.');
  return out;
}

void _showCouponDetails(BuildContext context, Coupon coupon, Color accent) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CouponDetailsSheet(coupon: coupon, accent: accent),
  );
}

class _CouponDetailsSheet extends StatelessWidget {
  const _CouponDetailsSheet({required this.coupon, required this.accent});

  final Coupon coupon;
  final Color accent;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: coupon.code));
    AppToast.show(context, 'Code ${coupon.code} copied', type: AppToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final terms = _termsFor(coupon);
    final min = coupon.minBooking > Decimal.zero ? 'Valid on orders above ₹${coupon.minBooking}' : 'No minimum order';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(color: Color(0xFF1F2937), shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
          ),
        ),
        Flexible(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
                              child: Icon(coupon.isPercentage ? Icons.percent_rounded : Icons.local_offer_rounded, color: Colors.white, size: 34),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              coupon.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20, height: 1.2, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(child: Text(min, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)))),
                          const SizedBox(height: 12),
                          Center(
                            child: GestureDetector(
                              onTap: () => _copy(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFD1D5DB)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(coupon.code, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Color(0xFF374151))),
                                    const SizedBox(width: 10),
                                    Icon(Icons.copy_rounded, size: 15, color: accent),
                                    const SizedBox(width: 4),
                                    Text('Copy', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (terms.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            const Text('Terms & Conditions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                            const SizedBox(height: 10),
                            for (final t in terms)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('•  ', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                                    Expanded(child: Text(t, style: const TextStyle(fontSize: 14, height: 1.3, color: Color(0xFF374151)))),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _copy(context),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copy Code'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF111827),
                              side: const BorderSide(color: Color(0xFFD1D5DB)),
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                            child: const Text('Got it'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
