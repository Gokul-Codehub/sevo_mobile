import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:smart_auth/smart_auth.dart';

import 'otp_autofill.dart';

/// Reads the sign-in code from the SMS that arrives on THIS phone, using Android's SMS User Consent API.
///
/// How it stays safe:
///  * Only the phone that receives the SMS (the SIM in it) can ever see the code; nothing about the code travels
///    through the server, and the server never returns it.
///  * Android shows its own "Allow SEVO to read this message?" box for that single message. The app has no standing
///    SMS permission, cannot read other messages, and nothing is read until the customer taps Allow.
///  * The code is only put into the boxes. The server still checks it against the number it was sent to (single use,
///    5 minutes, 3 tries), so a code read by another app or phone is useless without that number's SMS.
///
/// No app hash is needed in the SMS, so the DLT-approved template stays as it is. iOS needs nothing: its keyboard offers
/// the code from the SMS (the boxes are marked as a one-time code).
class SmsUserConsentAutofill implements OtpAutofill {
  SmsUserConsentAutofill();

  StreamController<String>? _controller;
  bool _active = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  Stream<String> listen() {
    _controller?.close();
    final controller = StreamController<String>();
    _controller = controller;
    if (_supported) {
      _active = true;
      unawaited(_waitForSms(controller));
    } else {
      controller.close();
    }
    return controller.stream;
  }

  Future<void> _waitForSms(StreamController<String> controller) async {
    try {
      // Completes when an SMS arrives and the customer taps Allow, or when Android gives up after five minutes.
      final dynamic result = await SmartAuth.instance.getSmsWithUserConsentApi();
      if (!_active || controller.isClosed) return;
      final dynamic data = result.data;
      final String? sms = data?.sms as String?;
      final String? code = (data?.code as String?) ?? extractOtp(sms);
      if (code != null && code.length == 6) controller.add(code);
    } catch (_) {
      // No reader, a declined consent box or a timeout: the code is simply typed or taken from the keyboard instead.
    }
  }

  @override
  Future<String?> appSignature() async => null;

  @override
  Future<void> stop() async {
    _active = false;
    try {
      if (_supported) await SmartAuth.instance.removeUserConsentApiListener();
    } catch (_) {}
    await _controller?.close();
    _controller = null;
  }
}
