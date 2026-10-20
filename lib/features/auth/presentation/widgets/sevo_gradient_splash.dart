import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/widgets/sevo_logo.dart';

/// SEVO launch splash: light blue fading into white, the SEVO logo in its own
/// colours rises as the tagline types in letter by letter (in the logo's blue
/// gradient).
///
/// Pure presentation: the caller ([SplashScreen]) keeps all loading and
/// navigation logic.
class SevoGradientSplash extends StatefulWidget {
  const SevoGradientSplash({super.key});

  static const String tagline = 'Everything you need,\nin one place';

  /// Length of the whole intro animation.
  static const Duration duration = Duration(milliseconds: 2800);

  @override
  State<SevoGradientSplash> createState() => _SevoGradientSplashState();
}

class _SevoGradientSplashState extends State<SevoGradientSplash>
    with SingleTickerProviderStateMixin {
  // animationBehavior.preserve is the actual fix for "the splash has no
  // animation": by default a controller jumps almost straight to its end
  // whenever Android's "Remove animations" / animator-duration-scale 0 /
  // battery-saver setting is on, so the intro was over in a few milliseconds.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SevoGradientSplash.duration,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Always play the intro. (It used to jump straight to the finished frame
    // when the OS "remove animations" / battery-saver setting was on, which
    // made the splash look like it had no animation at all on those phones.)
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Timeline (fractions of the 2.8 s run).
  static const _logoIn = Interval(0.00, 0.20, curve: Curves.easeOutCubic);
  static const _rise = Interval(0.22, 0.42, curve: Curves.easeInOutCubic);
  static const _type = Interval(0.34, 0.70, curve: Curves.linear);

  @override
  Widget build(BuildContext context) {
    // Rounded, even-stroke geometric face to sit with the SEVO wordmark, in
    // the wordmark's own blue (top #066CEB -> bottom #01439D, see ShaderMask).
    final tagStyle = GoogleFonts.quicksand(
      fontSize: 19,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.2,
    );
    final tagline = SevoGradientSplash.tagline;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blue at the top melting into white.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF6FB1FF),
                  Color(0xFFA9D0FF),
                  Color(0xFFD8EAFF),
                  Colors.white,
                ],
                stops: [0.0, 0.34, 0.62, 0.88],
              ),
            ),
          ),
          // Soft white glow behind the logo so its blue stays crisp.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 0),
                radius: 0.75,
                colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
          ),
          // Logo + tagline.
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final logoT = _logoIn.transform(_c.value);
              final riseT = _rise.transform(_c.value);
              final typeT = _type.transform(_c.value);
              final shown = (tagline.length * typeT).floor().clamp(0, tagline.length);
              return Align(
                alignment: Alignment.center,
                child: Transform.translate(
                  // Starts lower (logo alone near the middle), then rises.
                  offset: Offset(0, 24 * (1 - riseT)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: logoT,
                        child: Transform.scale(
                          scale: 0.88 + 0.12 * logoT,
                          child: const SevoLogo(height: 46),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Full text reserved invisibly so nothing reflows while typing.
                      Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Opacity(
                            opacity: 0,
                            child: Text(tagline, textAlign: TextAlign.center, style: tagStyle),
                          ),
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (r) => const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF066CEB), Color(0xFF01439D)],
                            ).createShader(r),
                            child: Text(tagline.substring(0, shown), textAlign: TextAlign.center, style: tagStyle),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
