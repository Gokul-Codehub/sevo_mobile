import 'package:flutter/material.dart';

/// SEVONIQ brand wordmark (assets/images/sevoniq_logo.png): transparent background, blue wordmark with the green
/// "E" bar and "N". Every logo in the app (splash, login, Home, footer) goes through this one widget, so changing
/// the artwork only ever means replacing that file.
///
/// (The class keeps its original name so existing screens did not need touching.)
class SevoLogo extends StatelessWidget {
  const SevoLogo({
    super.key,
    this.width,
    this.height,
  });

  final double? width;
  final double? height;

  static const String asset = 'assets/images/sevoniq_logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      semanticLabel: 'SEVONIQ',
    );
  }
}
