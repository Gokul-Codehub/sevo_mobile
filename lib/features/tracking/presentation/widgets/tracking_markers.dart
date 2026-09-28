import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Custom marker bitmaps for the live tracking map.
///
/// Added 2026-09-16 per explicit request: the technician marker should read
/// like Rapido's live bike marker — a small directional vehicle badge that
/// visually turns to face its heading — and the customer's exact service
/// address should use a "lollipop" pin: the circle-on-a-stem-with-ground-
/// shadow marker ride-hailing apps (Uber/Ola/Rapido) use to mark a precise
/// drop point, as opposed to a generic teardrop map pin.
///
/// Rotation is applied via `Marker.rotation` (google_maps_flutter turns the
/// whole bitmap around its anchor), not baked into the image — so this same
/// bike bitmap is reused for every heading update instead of redrawing a
/// new bitmap per degree, the way the web app's SVG marker does.
class TrackingMarkers {
  TrackingMarkers._();

  static BitmapDescriptor? _bikeIcon;
  static BitmapDescriptor? _lollipopIcon;

  static Future<BitmapDescriptor> technicianIcon() async {
    return _bikeIcon ??= await _drawBikeMarker();
  }

  static Future<BitmapDescriptor> destinationLollipop() async {
    return _lollipopIcon ??= await _drawLollipopMarker();
  }

  static Future<BitmapDescriptor> _drawBikeMarker() async {
    const double logicalSize = 56;
    const double scale = 3; // render at 3x for crisp edges on hidpi screens
    const double px = logicalSize * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, px, px));
    const center = Offset(px / 2, px / 2);
    const navy = Color(0xFF1E3A5F);
    const blue = Color(0xFF2563EB);

    // Live-tracking halo
    canvas.drawCircle(center, px * 0.46, Paint()..color = blue.withValues(alpha: 0.20));

    // Soft drop shadow behind the badge
    canvas.drawCircle(
      center,
      px * 0.36,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // White badge base + navy ring
    canvas.drawCircle(center, px * 0.36, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      px * 0.36,
      Paint()
        ..color = navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = px * 0.035,
    );

    // Directional pointer — turns with the whole bitmap via Marker.rotation,
    // so it always points the way the technician is actually heading.
    final pointerPath = Path()
      ..moveTo(center.dx, px * 0.02)
      ..lineTo(center.dx - px * 0.09, px * 0.155)
      ..lineTo(center.dx + px * 0.09, px * 0.155)
      ..close();
    canvas.drawPath(pointerPath, Paint()..color = blue);

    // Vehicle glyph, rasterized from a Material icon
    final iconData = Icons.two_wheeler_rounded;
    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: px * 0.4,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: navy,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2 + px * 0.02),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(px.round(), px.round());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: logicalSize,
      height: logicalSize,
    );
  }

  static Future<BitmapDescriptor> _drawLollipopMarker() async {
    const double logicalWidth = 34;
    const double logicalHeight = 56;
    const double scale = 3;
    const double w = logicalWidth * scale;
    const double h = logicalHeight * scale;
    const accent = Color(0xFF10B981); // emerald — the destination accent
    // already used elsewhere in this app's tracking UI.

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));

    const circleCenter = Offset(w / 2, h * 0.27);
    const circleRadius = w * 0.42;
    const stemBottom = Offset(w / 2, h * 0.82);

    // Ground shadow — sits at the exact coordinate this marker anchors to.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(w / 2, h * 0.9), width: w * 0.55, height: h * 0.055),
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );

    // Stem connecting the circle "head" to the ground point.
    canvas.drawLine(
      Offset(w / 2, circleCenter.dy + circleRadius * 0.7),
      stemBottom,
      Paint()
        ..color = accent
        ..strokeWidth = w * 0.07
        ..strokeCap = StrokeCap.round,
    );

    // Outer glow
    canvas.drawCircle(circleCenter, circleRadius * 1.25, Paint()..color = accent.withValues(alpha: 0.22));

    // The "lollipop" head: shadow, colored disc, white ring, solid center dot.
    canvas.drawCircle(
      circleCenter,
      circleRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(circleCenter, circleRadius, Paint()..color = accent);
    canvas.drawCircle(circleCenter, circleRadius * 0.68, Paint()..color = Colors.white);
    canvas.drawCircle(circleCenter, circleRadius * 0.34, Paint()..color = accent);

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.round(), h.round());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: logicalWidth,
      height: logicalHeight,
    );
  }
}
