import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/widgets/app_remote_image.dart';

/// Fonts an admin can pick for a Home Studio section title. The key is what is
/// stored in `settings.title_font`; the value is the Google Fonts family.
/// Keep in sync with TITLE_FONTS in backend home_studio/registry.py and
/// TITLE_FONTS in the admin PhonePreview.
const Map<String, String> kStudioTitleFonts = {
  'poppins': 'Poppins',
  'montserrat': 'Montserrat',
  'playfair': 'Playfair Display',
  'merriweather': 'Merriweather',
  'oswald': 'Oswald',
  'lobster': 'Lobster',
  'pacifico': 'Pacifico',
  'dancing': 'Dancing Script',
  'caveat': 'Caveat',
  'baloo2': 'Baloo 2',
};

/// Applies the admin-chosen title font on top of [base]. Unknown / empty keys
/// (and any font that fails to resolve) leave [base] untouched, so a section
/// saved before fonts existed looks exactly as before.
TextStyle studioTitleStyle(TextStyle base, String? fontKey) {
  final family = kStudioTitleFonts[(fontKey ?? '').trim()];
  if (family == null) return base;
  try {
    return GoogleFonts.getFont(family, textStyle: base);
  } catch (_) {
    return base;
  }
}

/// A section heading: the uploaded title image when there is one (the text is
/// kept as its accessibility label), otherwise the text in the chosen font.
class StudioTitle extends StatelessWidget {
  const StudioTitle({
    super.key,
    required this.text,
    required this.style,
    this.imageUrl = '',
    this.font = '',
    this.maxLines = 1,
    this.imageHeight = 34,
    this.trailing,
  });

  final String text;
  final TextStyle style;
  final String imageUrl;
  final String font;
  final int maxLines;
  final double imageHeight;

  /// Optional widget after the title (e.g. the emoji on Tabbed Showcase).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isNotEmpty) {
      return Semantics(
        header: true,
        label: text,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            // Image titles are uploaded artwork (logos / lettering) and read small at
            // text size, so they are drawn larger than the plain-text title would be.
            height: imageHeight * 1.8,
            child: AppRemoteImage(imageUrl: imageUrl.trim(), title: text, fit: BoxFit.contain),
          ),
        ),
      );
    }
    final t = Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: studioTitleStyle(style, font),
    );
    if (trailing == null) return t;
    return Row(children: [Flexible(child: t), const SizedBox(width: 6), trailing!]);
  }
}
