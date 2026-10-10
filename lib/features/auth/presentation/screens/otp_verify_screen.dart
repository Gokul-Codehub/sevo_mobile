import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/auth_notifier.dart';

/// Screen 5: OTP Verification
/// 6 individual rounded digit boxes with countdown timer and navy Verify CTA matching reference screen 5.
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({
    super.key,
    required this.identifier,
    required this.channel,
    this.resendAfterSeconds = 60,
  });

  final String identifier;
  final String channel;
  final int resendAfterSeconds;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  // Fixed 2026-10-07 ("the clear of a single box also inappropriate"): each
  // FocusNode now owns an `onKeyEvent` handler (set once, here, since a
  // FocusNode's key-event callback is fixed at construction and each one
  // needs to know its own index) instead of the plain `FocusNode()` list
  // this used to be. See [_handleBackspaceKey] for what it does and why.
  late final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(onKeyEvent: (node, event) => _handleBackspaceKey(event, index)),
  );

  bool _isLoading = false;
  int _secondsRemaining = 30;
  Timer? _timer;
  // Guards the programmatic `controller.text = ...` writes in
  // [_distributePastedDigits] from re-entering [_onDigitChanged] through the
  // TextEditingController's own change notifications — without this, each
  // write would be treated as if the user had typed that digit themselves
  // and would redundantly re-run the focus-advance logic out of order.
  bool _isDistributingPaste = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  /// Lets backspace continue walking backward through already-filled boxes
  /// instead of stalling the moment it reaches one that's already empty.
  ///
  /// Fixed 2026-10-07 ("the clear of a single box of a otp also
  /// inappropriate make it clear"): [onChanged] below only ever fires when a
  /// box's own text actually changes. Backspacing a box that has a digit
  /// clears that digit and (correctly) moves focus to the previous box —
  /// but the previous box's digit is left untouched, so a second backspace
  /// press on it does nothing visible until it, in turn, has a digit to
  /// delete. In practice this reads as "backspace doesn't really clear
  /// things" — the user has to press it once per box just to arrive, then
  /// again to actually delete, instead of one continuous backspace walking
  /// all the way back. Catching the backspace key directly, only when the
  /// CURRENT box is already empty, and using it to clear and refocus the
  /// PREVIOUS box in the same keystroke fixes that: holding or repeatedly
  /// pressing backspace now deletes one digit per press with no dead presses
  /// in between, matching how every native OTP input behaves.
  KeyEventResult _handleBackspaceKey(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _digitControllers[index].text.isEmpty &&
        index > 0) {
      _digitControllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Handles one box's [onChanged] firing, including the multi-digit case.
  ///
  /// Fixed 2026-10-07 ("speed otp entry is not allowed"): each box used to
  /// be capped with `maxLength: 1`, so whenever more than one digit landed
  /// in a single text-field update — pasting a copied code, or the
  /// SMS-autofill suggestion Android/iOS show above the keyboard, both of
  /// which insert the full 6-digit code into whichever box is focused in
  /// one shot — Flutter's length-limiting formatter silently truncated it
  /// to just the first digit and discarded the rest. Typing fast enough
  /// that the OS batches a couple of keystrokes into one update hit the
  /// same truncation. `maxLength: 1` is gone from the field now (see
  /// `build()` below); this method does the single-digit-per-box
  /// enforcement itself, and also recognizes a multi-character update as
  /// "spread these across the remaining boxes starting here" instead of
  /// clipping it.
  void _onDigitChanged(String val, int index) {
    if (_isDistributingPaste) return;
    final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 1) {
      _distributePastedDigits(digits, index);
      return;
    }
    if (digits.length != val.length) {
      // The formatter already strips non-digits before this runs, but a
      // defensive re-sync keeps the controller's text exactly one digit.
      _digitControllers[index].text = digits;
      _digitControllers[index].selection =
          TextSelection.collapsed(offset: digits.length);
    }
    if (digits.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _handleVerify();
      }
    } else if (index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  /// Spreads a pasted/autofilled multi-digit string across boxes
  /// `startIndex, startIndex + 1, ...`, landing focus on the next empty box
  /// (or triggering verification once all 6 are filled).
  void _distributePastedDigits(String digits, int startIndex) {
    _isDistributingPaste = true;
    var filled = 0;
    for (; filled < digits.length && startIndex + filled < 6; filled++) {
      final controller = _digitControllers[startIndex + filled];
      controller.text = digits[filled];
      controller.selection = const TextSelection.collapsed(offset: 1);
    }
    _isDistributingPaste = false;
    final nextIndex = startIndex + filled;
    if (nextIndex >= 6) {
      _focusNodes[5].unfocus();
      _handleVerify();
    } else {
      _focusNodes[nextIndex].requestFocus();
    }
  }

  void _startCountdown() {
    _secondsRemaining = widget.resendAfterSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTimer(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getOtpCode() {
    return _digitControllers.map((c) => c.text.trim()).join();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final otp = _getOtpCode();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits of the OTP code'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await ref.read(authProvider.notifier).verifyOtp(
          identifier: widget.identifier,
          otp: otp,
          channel: widget.channel,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      final user = ref.read(currentUserProvider);
      if (result.isNewUser || (user != null && !user.isProfileComplete)) {
        context.go(AppRoutes.profileComplete);
      } else {
        final pendingAction = ref.read(pendingActionProvider);
        if (pendingAction != null) {
          ref.read(pendingActionProvider.notifier).clear();
          ref.read(cartProvider.notifier).addService(
                pendingAction.service,
                quantity: pendingAction.quantity,
                notes: pendingAction.notes,
              );

          if (pendingAction.actionType == PendingCartActionType.buy) {
            context.go(AppRoutes.cart);
          } else {
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (messenger != null) {
              messenger.clearSnackBars();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    '${pendingAction.service.title} added to cart',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: AppColors.primary,
                  duration: const Duration(milliseconds: 1400),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              );
            }
            final returnTarget = pendingAction.returnPath ?? AppRoutes.home;
            context.go(returnTarget);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logged in successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
          context.go(AppRoutes.home);
        }
      }
    }
  }

  Future<void> _handleResendOtp() async {
    if (_secondsRemaining > 0) return;

    // Fixed 2026-10-08 ("once the user clicks resend OTP the older enterd
    // one should be cleared and let the user to enter newly"): the 6 boxes
    // used to keep whatever digits were typed for the OLD code, so after a
    // resend the customer either had to notice and manually clear each box
    // themselves, or risked submitting a mix of old-code leftovers and the
    // new code's digits. Clear every box and send focus back to the first
    // one, exactly like a fresh arrival at this screen.
    for (final c in _digitControllers) {
      c.clear();
    }
    if (_focusNodes.isNotEmpty) {
      _focusNodes.first.requestFocus();
    }

    setState(() => _isLoading = true);

    final result = await ref.read(authProvider.notifier).requestOtp(
          identifier: widget.identifier,
          channel: widget.channel,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.error!), backgroundColor: AppColors.error),
      );
    } else {
      _startCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New OTP sent successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayPhone = (widget.channel == 'phone' || widget.channel == 'sms')
        ? '+91 ${widget.identifier}'
        : widget.identifier;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // ── Title & Subtitle ──
              const Text(
                'Verify your number',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Enter the 6-digit code sent to\n'),
                    TextSpan(
                      text: displayPhone,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),

              // Fixed 2026-10-08 ("small space problem between the email
              // and otp entry section"): there was no gap at all here
              // before — the phone/email RichText butted straight up
              // against the OTP box row.
              const SizedBox(height: 28),

              // ── 6 Individual OTP Digit Boxes ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 46,
                    height: 58,
                    child: TextFormField(
                      controller: _digitControllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      autofocus: index == 0,
                      // Fixed 2026-10-07 ("speed otp entry is not
                      // allowed"): `maxLength: 1` used to truncate any
                      // multi-character update — a pasted code, SMS
                      // autofill, or just typing fast — down to one digit
                      // and threw the rest away. [_onDigitChanged] now
                      // does its own single-digit enforcement and spreads
                      // a longer update across the remaining boxes, so the
                      // cap on this field is gone.
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                        height: 1.0,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.border, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.border, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.primary, width: 2.5),
                        ),
                      ),
                      onChanged: (val) => _onDigitChanged(val, index),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 24),

              // ── Resend Timer Pill ──
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _secondsRemaining > 0
                      ? Container(
                          key: const ValueKey('timer'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Resend OTP in ${_formatTimer(_secondsRemaining)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
                ),
              ),

              const SizedBox(height: 28),

              // ── Navy Primary Verify Button ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleVerify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Didn't receive OTP? Resend ──
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Didn't receive OTP? ",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: _secondsRemaining > 0 || _isLoading
                          ? null
                          : _handleResendOtp,
                      child: Text(
                        'Resend',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _secondsRemaining > 0
                              ? AppColors.textHint
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
