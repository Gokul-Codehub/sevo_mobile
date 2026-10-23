import 'package:flutter/services.dart';

/// Shared sign-up / onboarding input rules, so the phone screen, the profile
/// screen and anything later check the same thing the same way.
class InputValidators {
  InputValidators._();

  static final RegExp _mobile = RegExp(r'^[6-9]\d{9}$');
  static final RegExp _name = RegExp(r"^\p{L}[\p{L}\s.'\-]*$", unicode: true);
  static final RegExp _email = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$',
  );

  /// Collapses runs of spaces and trims. Use this on the value that is sent.
  static String cleanName(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? indianMobile(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Please enter your mobile number';
    if (t.length != 10) return 'Mobile number must be exactly 10 digits';
    if (!_mobile.hasMatch(t)) return 'Mobile number must start with 6, 7, 8 or 9';
    return null;
  }

  static String? fullName(String? v) {
    final t = cleanName(v ?? '');
    if (t.isEmpty) return 'Please enter your full name';
    if (t.length < 2) return 'Name must be at least 2 characters';
    if (t.length > 60) return 'Name must be 60 characters or fewer';
    if (!_name.hasMatch(t)) {
      return 'Use letters only (spaces, . \' - are fine)';
    }
    return null;
  }

  /// [required] false → an empty value is fine, a filled one must be valid.
  static String? email(String? v, {bool required = true}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return required ? 'Please enter your email address' : null;
    final bad = t.length > 254 ||
        t.contains('..') ||
        t.startsWith('.') ||
        t.split('@').first.endsWith('.') ||
        !_email.hasMatch(t);
    if (bad) {
      return required
          ? 'Enter a valid email address'
          : 'Enter a valid email address or leave blank';
    }
    return null;
  }
}

/// Keeps only digits and understands pasted Indian numbers: "+91 98765 43210",
/// "919876543210" and "09876543210" all become "9876543210". (A plain
/// digits-only + 10-character limit would have turned "919876543210" into the
/// wrong number "9198765432" without any warning.)
class IndianMobileFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 12 && d.startsWith('91')) {
      d = d.substring(2);
    } else if (d.length == 11 && d.startsWith('0')) {
      d = d.substring(1);
    }
    if (d.length > 10) d = d.substring(0, 10);
    return TextEditingValue(
      text: d,
      selection: TextSelection.collapsed(offset: d.length),
    );
  }
}
