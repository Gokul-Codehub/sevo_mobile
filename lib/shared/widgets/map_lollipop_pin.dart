import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Navy "lollipop" map pin: circle head + thin stem. The stem tip marks the
/// exact map coordinate so the area underneath stays visible for precise
/// placement (address map, drop-location picker, etc.).
class MapLollipopPin extends StatelessWidget {
  const MapLollipopPin({super.key});

  static const double width = 36;
  static const double height = 58;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _MapLollipopPainter()),
    );
  }
}

class _MapLollipopPainter extends CustomPainter {
  const _MapLollipopPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const accent = AppColors.navy;
    final cx = size.width / 2;
    final headCenter = Offset(cx, size.height * 0.28);
    final headRadius = size.width * 0.42;
    final stemBottom = Offset(cx, size.height * 0.92);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.96),
        width: size.width * 0.5,
        height: size.height * 0.06,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );

    canvas.drawLine(
      Offset(cx, headCenter.dy + headRadius * 0.75),
      stemBottom,
      Paint()
        ..color = accent
        ..strokeWidth = size.width * 0.08
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      headCenter,
      headRadius * 1.22,
      Paint()..color = accent.withValues(alpha: 0.18),
    );

    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(headCenter, headRadius, Paint()..color = accent);
    canvas.drawCircle(headCenter, headRadius * 0.62, Paint()..color = Colors.white);
    canvas.drawCircle(headCenter, headRadius * 0.28, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
