import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The SEVO splash as a living illustration instead of one flat picture.
///
/// Everything the old splash image showed is drawn here and moves: the logo
/// springs in and catches a passing glint, the tagline rises, the four service
/// tiles pop in one after another and then take turns bouncing, the script line
/// draws its underline, the skyline sits on rolling hills, a delivery truck
/// drives across them and the map pin bobs on the right.
///
/// With the system's "reduce motion" on, it shows the finished still frame.
class AnimatedSplashArt extends StatefulWidget {
  const AnimatedSplashArt({super.key});

  @override
  State<AnimatedSplashArt> createState() => _AnimatedSplashArtState();
}

class _AnimatedSplashArtState extends State<AnimatedSplashArt> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
      _loop.value = 0.3;
    } else {
      _intro.forward();
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  Animation<double> _step(double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, end, curve: curve));

  static const _tiles = [
    (icon: Icons.shopping_cart_rounded, label: 'Groceries', color: Color(0xFF2FB457)),
    (icon: Icons.home_rounded, label: 'Home Services', color: Color(0xFF1668E3)),
    (icon: Icons.engineering_rounded, label: 'Experts', color: Color(0xFFF59A1B)),
    (icon: Icons.local_shipping_rounded, label: 'Fast Delivery', color: Color(0xFFE23B65)),
  ];

  @override
  Widget build(BuildContext context) {
    final logoIn = _step(0.0, 0.42, Curves.easeOutBack);
    final taglineIn = _step(0.28, 0.58);
    final scriptIn = _step(0.78, 1.0);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        return AnimatedBuilder(
          animation: Listenable.merge([_intro, _loop]),
          builder: (context, _) {
            final loop = _loop.value;
            final truckX = -70 + (w + 140) * ((loop * 1.0) % 1.0);
            final pinBob = math.sin(loop * 2 * math.pi * 2) * 4;
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _BackdropPainter(t: loop, intro: _intro.value)),
                // Map pin on the right hill.
                Positioned(
                  right: w * 0.13,
                  bottom: h * 0.098 + 6 + pinBob.abs(),
                  child: Opacity(
                    opacity: _step(0.6, 0.9).value,
                    child: const Icon(Icons.location_on_rounded, size: 46, color: Color(0xFF6FA8F2)),
                  ),
                ),
                // Delivery truck crossing the hills.
                Positioned(
                  left: truckX,
                  bottom: h * 0.058 + math.sin(loop * 2 * math.pi * 6) * 1.2,
                  child: const _MiniTruck(),
                ),
                // Main content.
                Positioned.fill(
                  top: h * 0.2,
                  bottom: h * 0.2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.scale(
                        scale: 0.7 + 0.3 * logoIn.value,
                        child: Opacity(
                          opacity: logoIn.value.clamp(0.0, 1.0),
                          child: _GlintLogo(width: w * 0.7, glint: loop),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: taglineIn.value,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - taglineIn.value)),
                          child: const Text(
                            'Everything You Need\nin One Place',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 19,
                              height: 1.45,
                              letterSpacing: 3.2,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1F3B73),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 34),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _tiles.length; i++) ...[
                            if (i > 0)
                              Container(
                                width: 1,
                                height: 54,
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                color: const Color(0xFFDDE5F0),
                              ),
                            _ServiceTile(
                              icon: _tiles[i].icon,
                              label: _tiles[i].label,
                              color: _tiles[i].color,
                              pop: _step(0.46 + i * 0.07, 0.74 + i * 0.07, Curves.easeOutBack).value,
                              // Each tile takes a turn to bounce, round and round.
                              bounce: _bounce(loop, i),
                              isTruck: i == 3,
                              phase: loop,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 36),
                      Opacity(
                        opacity: scriptIn.value,
                        child: _ScriptLine(progress: scriptIn.value),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 0..1..0 hump while it is tile [i]'s turn in the loop, else 0.
  double _bounce(double loop, int i) {
    final slot = (loop * _tiles.length) - i;
    final local = slot - slot.floorToDouble();
    final turn = (loop * _tiles.length).floor() % _tiles.length;
    if (turn != i) return 0;
    return math.sin(local * math.pi);
  }
}

class _GlintLogo extends StatelessWidget {
  const _GlintLogo({required this.width, required this.glint});

  final double width;

  /// 0..1 loop position; the glint sweeps across during the first half.
  final double glint;

  @override
  Widget build(BuildContext context) {
    final sweep = (glint * 2).clamp(0.0, 1.0); // moves, then rests
    final image = Image.asset(
      'assets/images/sevo_logo.png',
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Text(
        'SEVO',
        style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Color(0xFF1668E3)),
      ),
    );
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (rect) {
        final x = -0.4 + 1.8 * sweep;
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
          stops: [(x - 0.12).clamp(0.0, 1.0), x.clamp(0.0, 1.0), (x + 0.12).clamp(0.0, 1.0)],
        ).createShader(rect);
      },
      child: image,
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.pop,
    required this.bounce,
    required this.isTruck,
    required this.phase,
  });

  final IconData icon;
  final String label;
  final Color color;
  final double pop;
  final double bounce;
  final bool isTruck;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final p = pop.clamp(0.0, 1.2);
    final lift = -9 * bounce;
    final scale = (0.4 + 0.6 * p) * (1 + 0.16 * bounce);
    // The truck's icon shudders forward a little, like it is pulling away.
    final shudder = isTruck ? math.sin(phase * 2 * math.pi * 9) * 1.4 : 0.0;
    return SizedBox(
      width: 74,
      child: Opacity(
        opacity: pop.clamp(0.0, 1.0),
        child: Column(
          children: [
            SizedBox(
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 44 + 10 * bounce,
                    height: 44 + 10 * bounce,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.12 * bounce),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(shudder, lift),
                    child: Transform.scale(scale: scale, child: Icon(icon, size: 36, color: color)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: bounce > 0.4 ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF3A4A66),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Simpler. Faster. Better." in a handwritten style with a green swoosh that
/// draws itself underneath.
class _ScriptLine extends StatelessWidget {
  const _ScriptLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 64,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          const Text(
            'Simpler. Faster. Better.',
            style: TextStyle(
              fontFamily: 'cursive',
              fontStyle: FontStyle.italic,
              fontSize: 25,
              color: Color(0xFF7D9AD9),
            ),
          ),
          Positioned.fill(
            top: 36,
            child: CustomPaint(painter: _SwooshPainter(progress)),
          ),
        ],
      ),
    );
  }
}

class _SwooshPainter extends CustomPainter {
  _SwooshPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.85)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.1, size.width * 0.95, size.height * 0.3);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));
    canvas.drawPath(
      drawn,
      Paint()
        ..color = const Color(0xFF38B65A)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SwooshPainter old) => old.progress != progress;
}

class _MiniTruck extends StatelessWidget {
  const _MiniTruck();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // speed lines trailing behind
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 18, height: 2.5, child: ColoredBox(color: Color(0x55E23B65))),
            SizedBox(height: 4),
            SizedBox(width: 11, height: 2.5, child: ColoredBox(color: Color(0x44E23B65))),
          ],
        ),
        SizedBox(width: 3),
        Icon(Icons.local_shipping_rounded, size: 30, color: Color(0xFFE23B65)),
      ],
    );
  }
}

/// Soft blue shapes, the city skyline and the rolling green / blue hills.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.t, required this.intro});

  final double t;
  final double intro;

  static const _buildings = [
    (x: 0.10, w: 0.07, h: 0.060),
    (x: 0.18, w: 0.05, h: 0.045),
    (x: 0.23, w: 0.06, h: 0.095),
    (x: 0.31, w: 0.05, h: 0.055),
    (x: 0.40, w: 0.045, h: 0.075),
    (x: 0.46, w: 0.06, h: 0.040),
    (x: 0.52, w: 0.05, h: 0.085),
    (x: 0.60, w: 0.055, h: 0.050),
    (x: 0.78, w: 0.05, h: 0.062),
    (x: 0.88, w: 0.045, h: 0.100),
    (x: 0.93, w: 0.04, h: 0.058),
  ];

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;

    // Top-left soft blue blob.
    final blob = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.42, 0)
      ..cubicTo(w * 0.40, h * 0.10, w * 0.22, h * 0.17, 0, h * 0.18)
      ..close();
    canvas.drawPath(
      blob,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF9CCBFA), Color(0x00BEDDFB)],
        ).createShader(Rect.fromLTWH(0, 0, w * 0.45, h * 0.2)),
    );

    // Skyline, rising into place as the splash opens.
    final base = h * 0.925;
    final rise = Curves.easeOut.transform(intro.clamp(0.0, 1.0));
    final city = Paint()..color = const Color(0xFFDCE8FA);
    for (final b in _buildings) {
      final bh = h * b.h * (0.4 + 0.6 * rise) * 0.95;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * b.x, base - bh, w * b.w, bh + 8),
          const Radius.circular(2),
        ),
        city,
      );
    }

    double wave(double x, double amp, double phase, double freq) =>
        math.sin((x / w) * 2 * math.pi * freq + phase) * amp;

    Path hill(double top, double amp, double phase, double freq) {
      final p = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += 6) {
        p.lineTo(x, top + wave(x, amp, phase, freq));
      }
      p
        ..lineTo(w, h)
        ..close();
      return p;
    }

    final drift = t * 2 * math.pi;
    // Back hill, pale blue.
    canvas.drawPath(
      hill(h * 0.935, h * 0.010, drift * 0.5 + 1.0, 1.2),
      Paint()..color = const Color(0xFFC9DEFA),
    );
    // Middle hill, green.
    canvas.drawPath(
      hill(h * 0.955, h * 0.012, -drift * 0.5, 0.9),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8EDB9A), Color(0xFF3FB46E)],
        ).createShader(Rect.fromLTWH(0, h * 0.93, w, h * 0.07)),
    );
    // Front hill, deep blue.
    canvas.drawPath(
      hill(h * 0.985, h * 0.008, drift * 0.5 + 2.4, 1.1),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2F7BE6), Color(0xFF22A6A1)],
        ).createShader(Rect.fromLTWH(0, h * 0.97, w, h * 0.03)),
    );

    // A few little trees that sway.
    void tree(double x, double treeH) {
      final sway = math.sin(drift * 2 + x * 9) * 1.6;
      final cx = w * x;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + sway, base - treeH * 0.55), width: treeH * 0.55, height: treeH),
        Paint()..color = const Color(0xFFA9CCF5),
      );
    }

    tree(0.045, h * 0.06);
    tree(0.80, h * 0.04);
    tree(0.835, h * 0.05);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t || old.intro != intro;
}

/// A line of status text under the splash that changes while it waits —
/// "Fetching fresh groceries…" and so on — so a long load still feels alive.
class SplashStatusLine extends StatefulWidget {
  const SplashStatusLine({super.key});

  @override
  State<SplashStatusLine> createState() => _SplashStatusLineState();
}

class _SplashStatusLineState extends State<SplashStatusLine> {
  static const _lines = [
    'Fetching fresh groceries…',
    'Finding trusted experts near you…',
    'Lining up fast delivery…',
    'Almost there…',
  ];
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _lines.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: Text(
        _lines[_i],
        key: ValueKey(_i),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4A5B7A),
        ),
      ),
    );
  }
}
