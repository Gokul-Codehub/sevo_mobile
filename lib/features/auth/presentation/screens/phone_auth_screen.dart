import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/env.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/sevo_logo.dart';
import '../../domain/auth_models.dart';
import '../../domain/auth_notifier.dart';

/// Screen 4: Login / Register
/// Redesigned to match reference screen 4 with SEVO branding, mobile input, and navy CTA.
class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String _channel = 'phone'; // 'phone' or 'email'

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _phoneFocusNode.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final identifier = _channel == 'phone'
        ? _phoneController.text.trim()
        : _emailController.text.trim();
    final result = await ref.read(authProvider.notifier).requestOtp(
          identifier: identifier,
          channel: _channel,
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
      final args = OtpVerifyArgs(
        identifier: identifier,
        channel: _channel,
        resendAfterSeconds: result.resendAfterSeconds,
      );
      final uri = Uri(
        path: AppRoutes.otpVerify,
        queryParameters: {
          'identifier': identifier,
          'channel': _channel,
          'resend_after': result.resendAfterSeconds.toString(),
        },
      );
      context.go(uri.toString(), extra: args);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Branded Header ──
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primaryLight, width: 2),
                    ),
                    child: const Center(
                      child: SevoLogo(height: 32),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Welcome Headline ──
                const Text(
                  'Welcome back!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Login or create an account',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),

                const SizedBox(height: 28),

                // ── Channel Switcher (Phone / Email) ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_channel != 'phone') {
                              setState(() => _channel = 'phone');
                              _phoneFocusNode.requestFocus();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _channel == 'phone'
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: _channel == 'phone'
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.phone_android_rounded,
                                  size: 16,
                                  color: _channel == 'phone'
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Mobile Number',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _channel == 'phone'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _channel == 'phone'
                                        ? AppColors.navy
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_channel != 'email') {
                              setState(() => _channel = 'email');
                              _emailFocusNode.requestFocus();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _channel == 'email'
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: _channel == 'email'
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.email_outlined,
                                  size: 16,
                                  color: _channel == 'email'
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Email Address',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _channel == 'email'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _channel == 'email'
                                        ? AppColors.navy
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ── Input Field ──
                if (_channel == 'phone') ...[
                  const Text(
                    'Mobile Number',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // +91 Country pill
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: const Center(
                          child: Row(
                            children: [
                              Text('🇮🇳 ', style: TextStyle(fontSize: 16)),
                              Text(
                                '+91',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Phone text field
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('phone_input_field'),
                          controller: _phoneController,
                          focusNode: _phoneFocusNode,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter mobile number',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: AppColors.textHint,
                              fontWeight: FontWeight.w400,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter your mobile number';
                            }
                            if (v.trim().length != 10 ||
                                !RegExp(r'^[6-9]\d{9}$').hasMatch(v.trim())) {
                              return 'Enter a valid 10-digit mobile number';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Text(
                    'Email Address',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('email_input_field'),
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                    decoration: InputDecoration(
                      hintText: 'name@example.com',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(Icons.email_outlined),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your email address';
                      }
                      if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$')
                          .hasMatch(v.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // ── Navy Primary Continue Button ──
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSendOtp,
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
                            'Continue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Trust signals ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TrustBadge(
                      icon: Icons.lock_outline_rounded,
                      label: 'OTP Secured',
                    ),
                    const SizedBox(width: 20),
                    _TrustBadge(
                      icon: Icons.verified_outlined,
                      label: 'Free to register',
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Guest option
                Center(
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: const Text(
                      'Continue as Guest',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── Terms & Privacy Footer ──
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(text: 'By continuing, you agree to our\n'),
                        const TextSpan(
                          text: 'Terms & Conditions',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              launchUrl(
                                Uri.parse(Env.privacyPolicyUrl),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Small icon + label trust signal displayed on the phone auth screen.
class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
