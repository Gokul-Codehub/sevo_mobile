import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/env.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/input_validators.dart';
import '../../../../shared/widgets/sevo_logo.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/auth_models.dart';
import '../../domain/auth_notifier.dart';
import '../../domain/auth_return.dart';

/// Log in: email / mobile number / username + password, or "email me a code" when the password is forgotten.
/// (Class name kept so the existing '/login' route and imports keep working.)
class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _hide = true;
  bool _loading = false;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final error = await ref.read(authProvider.notifier).passwordLogin(identifier: _id.text.trim(), password: _pw.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      _toast(error);
      return;
    }
    // Carry out whatever the customer was doing before being asked to log in (e.g. add to cart).
    final pending = ref.read(pendingActionProvider);
    if (pending != null) {
      ref.read(returnAfterLoginProvider.notifier).state = false;
      ref.read(pendingActionProvider.notifier).clear();
      ref.read(cartProvider.notifier).addService(pending.service, quantity: pending.quantity, notes: pending.notes);
      if (pending.actionType == PendingCartActionType.buy) {
        context.go(AppRoutes.cart);
      } else {
        context.go(pending.returnPath ?? AppRoutes.home);
      }
      return;
    }
    finishSignIn(context, ref);
  }

  /// Sends a login code to the email address typed in the first box (must be an email).
  Future<void> _emailCode() async {
    final email = _id.text.trim();
    if (InputValidators.email(email) != null) {
      _toast('Type your email address in the first box, then tap "Email me a login code".');
      return;
    }
    setState(() => _loading = true);
    final result = await ref.read(authProvider.notifier).requestOtp(identifier: email, channel: 'email');
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.error != null) {
      _toast(result.error!);
      return;
    }
    final args = OtpVerifyArgs(identifier: email, channel: 'email', resendAfterSeconds: result.resendAfterSeconds);
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
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primaryLight, width: 2),
                    ),
                    child: const Center(child: SevoLogo(height: 32)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Welcome back!',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.3)),
                const SizedBox(height: 6),
                const Text('Log in with your email, mobile number or username',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _id,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email, mobile number or username',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email, mobile number or username' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pw,
                  obscureText: _hide,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _loading ? null : _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Log in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: _loading ? null : _emailCode,
                    child: const Text('Forgot password? Email me a login code',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                ),
                const Divider(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => context.push(AppRoutes.signup),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Create a new account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: const Text('Continue as Guest',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.5),
                      children: [
                        const TextSpan(text: 'By continuing, you agree to our '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, decoration: TextDecoration.underline),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => launchUrl(Uri.parse(Env.privacyPolicyUrl), mode: LaunchMode.externalApplication),
                        ),
                      ],
                    ),
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
