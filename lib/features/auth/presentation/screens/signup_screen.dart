import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/focus_first_error.dart';
import '../../../../shared/utils/input_validators.dart';
import '../../domain/auth_models.dart';
import '../../domain/auth_notifier.dart';

/// New customer signup: name, mobile number, email and password. A 6-digit code is emailed to confirm the
/// address; the account is created when the code is entered (see OtpVerifyScreen in signup mode).
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {IconData? icon, Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );

  Future<void> _submit() async {
    if (!validateAndFocus(_formKey)) return;
    setState(() => _loading = true);
    final email = _email.text.trim();
    final result = await ref.read(authProvider.notifier).signupRequest(
          fullName: InputValidators.cleanName(_name.text),
          email: email,
          mobile: _mobile.text.trim(),
          password: _password.text,
          confirmPassword: _confirm.text,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!), backgroundColor: AppColors.error),
      );
      return;
    }
    final args = OtpVerifyArgs(
      identifier: email,
      channel: 'email',
      resendAfterSeconds: result.resendAfterSeconds,
      signup: true,
    );
    context.push(
      Uri(path: AppRoutes.otpVerify, queryParameters: {
        'identifier': email,
        'channel': 'email',
        'resend_after': result.resendAfterSeconds.toString(),
      }).toString(),
      extra: args,
    );
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
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Create your account',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.3)),
                const SizedBox(height: 6),
                const Text("We'll email you a 6-digit code to confirm your address.",
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 22),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: _dec('Full name', icon: Icons.person_outline_rounded),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: InputValidators.fullName,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [IndianMobileFormatter()],
                  decoration: _dec('Mobile number', icon: Icons.phone_android_rounded).copyWith(prefixText: '+91  '),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: InputValidators.indianMobile,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: _dec('Email address', icon: Icons.email_outlined),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: InputValidators.email,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _dec(
                    'Password',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirm,
                  obscureText: _hide,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _dec('Confirm password', icon: Icons.lock_outline_rounded),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                  onFieldSubmitted: (_) => _loading ? null : _submit(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Send verification code', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.login),
                    child: const Text('Already have an account? Log in',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
