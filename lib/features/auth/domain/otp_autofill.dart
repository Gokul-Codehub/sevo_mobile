import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the sign-in code can come from without the customer typing it.
///
/// There is no SMS service yet, so today this is a no-op and the code is typed or pasted (the keyboard's "From
/// messages" suggestion already works). It is a socket, not a feature: when SMS goes live, ONE class implements this
/// and ONE line in [otpAutofillProvider] switches it on. Nothing in the sign-in screen changes.
///
/// To connect it (Android SMS Retriever; needs no SMS permission):
///  1. Server: set `OTP_SMS_APP_HASH` to the app's 11-character hash (`accounts.otp_sms` then sends the message in the
///     format the retriever recognises, ending with that hash). The text must still match the DLT-registered template.
///  2. App: add a package that wraps SMS Retriever (for example `smart_auth`), implement [OtpAutofill] with it
///     (`listen()` -> its SMS stream mapped through [extractOtp]; `appSignature()` -> the app hash, to read it for the
///     server setting), and return that class from [otpAutofillProvider].
///  3. iOS needs nothing: its keyboard offers the code from the SMS (the field is already marked as a one-time code).
abstract class OtpAutofill {
  /// Codes as they arrive. An empty stream when this device or build cannot read them.
  Stream<String> listen();

  /// The app hash the SMS has to end with (Android SMS Retriever), for setting `OTP_SMS_APP_HASH`; null if unsupported.
  Future<String?> appSignature();

  /// Stops listening (the retriever times out after five minutes by itself).
  Future<void> stop();
}

class NoopOtpAutofill implements OtpAutofill {
  const NoopOtpAutofill();

  @override
  Stream<String> listen() => const Stream<String>.empty();

  @override
  Future<String?> appSignature() async => null;

  @override
  Future<void> stop() async {}
}

/// The sign-in code inside an SMS: the first run of exactly [length] digits, or null. A longer run of digits (a phone
/// number, an order number) is never mistaken for the code.
String? extractOtp(String? sms, {int length = 6}) {
  if (sms == null) return null;
  final m = RegExp('(?<!\\d)\\d{$length}(?!\\d)').firstMatch(sms);
  return m?.group(0);
}

/// Swap in the real implementation here once SMS is connected.
final otpAutofillProvider = Provider<OtpAutofill>((ref) => const NoopOtpAutofill());
