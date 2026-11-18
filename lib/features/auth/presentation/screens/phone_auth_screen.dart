import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../../shared/utils/app_toast.dart';

/// How the customer is signing in. Mobile number + SMS code is the main way (new numbers get an account
/// automatically); the email code and the password are fallbacks.
enum _LoginMode { mobile, email, password }

/// Log in or sign up. The first screen asks only for a mobile number and sends a six-digit SMS code.
/// "Use email instead" sends the code by email, and "Log in with password" keeps older password accounts working.
/// (Class name kept so the existing '/login' route and imports keep working.)
class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  _LoginMode _mode = _LoginMode.mobile;
  bool _hide = true;
  bool _loading = false;

  /// The SMS could not be sent (provider down, number blocked): the email option is then offered right away.
  bool _smsFailed = false;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  void _toast(String msg) => AppToast.show(context, msg, type: AppToastType.error);

  void _switchTo(_LoginMode mode) {
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    setState(() => _mode = mode);
  }

  void _openOtp(String identifier, String channel, int resendAfterSeconds) {
    final args = OtpVerifyArgs(identifier: identifier, channel: channel, resendAfterSeconds: resendAfterSeconds);
    context.push(
      Uri(path: AppRoutes.otpVerify, queryParameters: {
        'identifier': identifier,
        'channel': channel,
        'resend_after': resendAfterSeconds.toString(),
      }).toString(),
      extra: args,
    );
  }

  /// Sends the SMS code to the typed mobile number, then opens the code screen.
  Future<void> _sendSms() async {
    if (!_formKey.currentState!.validate()) return;
    final number = _phone.text.trim();
    setState(() {
      _loading = true;
      _smsFailed = false;
    });
    final result = await ref.read(authProvider.notifier).requestOtp(identifier: number, channel: 'phone');
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.error != null) {
      _toast(result.error!);
      // A rate-limit message ("wait 42 seconds") is not an SMS outage; anything else offers the email route.
      setState(() => _smsFailed = !result.error!.toLowerCase().contains('wait'));
      return;
    }
    _openOtp(number, 'phone', result.resendAfterSeconds);
  }

  /// Sends the code to the typed email address, then opens the code screen.
  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    setState(() => _loading = true);
    final result = await ref.read(authProvider.notifier).requestOtp(identifier: email, channel: 'email');
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.error != null) {
      _toast(result.error!);
      return;
    }
    _openOtp(email, 'email', result.resendAfterSeconds);
  }

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

  /// "Forgot password": sends a login code to the email typed in the first box (must be an email).
  Future<void> _emailCodeFromPassword() async {
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
    _openOtp(email, 'email', result.resendAfterSeconds);
  }

  Widget _primaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _linkButton(String label, VoidCallback onPressed) {
    return Center(
      child: TextButton(
        onPressed: _loading ? null : onPressed,
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color c, [double w = 1.2]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));

  Widget _secondaryButton(String label, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : onPressed,
        icon: Icon(icon, size: 18, color: AppColors.navy),
        label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _orDivider() {
    return const Row(children: [
      Expanded(child: Divider(color: AppColors.border)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('or', style: TextStyle(fontSize: 12, color: AppColors.textHint, fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Divider(color: AppColors.border)),
    ]);
  }

  List<Widget> _mobileForm() {
    return [
      const Text('Log in or sign up',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.5)),
      const SizedBox(height: 8),
      const Text('Enter your mobile number. We will text you a 6-digit code.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
      const SizedBox(height: 28),
      TextFormField(
        key: const ValueKey('phone_input_field'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        onFieldSubmitted: (_) => _loading ? null : _sendSms(),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: AppColors.navy),
        cursorColor: AppColors.navy,
        decoration: InputDecoration(
          hintText: 'Mobile number',
          hintStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textHint),
          counterText: '',
          filled: true,
          fillColor: AppColors.surfaceVariant,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.phone_android_rounded, size: 20, color: AppColors.navy),
              const SizedBox(width: 8),
              const Text('+91', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(width: 12),
              Container(width: 1, height: 24, color: AppColors.border),
            ]),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: _fieldBorder(AppColors.border),
          enabledBorder: _fieldBorder(AppColors.border),
          focusedBorder: _fieldBorder(AppColors.navy, 1.6),
          errorBorder: _fieldBorder(AppColors.error),
          focusedErrorBorder: _fieldBorder(AppColors.error, 1.6),
        ),
        validator: (v) =>
            RegExp(r'^[6-9][0-9]{9}$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid 10-digit mobile number',
      ),
      const SizedBox(height: 18),
      _primaryButton('Continue', _sendSms),
      if (_smsFailed) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 18, color: AppColors.navy),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'We could not send the SMS right now. You can get your code by email instead.',
                style: TextStyle(fontSize: 12.5, color: AppColors.navy, height: 1.4),
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textHint),
        SizedBox(width: 5),
        Text('We only use your number to verify it is you.', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
      ]),
      const SizedBox(height: 22),
      _orDivider(),
      const SizedBox(height: 18),
      _secondaryButton(_smsFailed ? 'Get the code by email' : 'Use email instead', Icons.email_outlined, () => _switchTo(_LoginMode.email)),
      const SizedBox(height: 10),
      _secondaryButton('Log in with password', Icons.lock_outline_rounded, () => _switchTo(_LoginMode.password)),
    ];
  }

  List<Widget> _emailForm() {
    return [
      const Text('Get a code by email',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.3)),
      const SizedBox(height: 6),
      const Text('We will email you a 6-digit code. Use this only if the SMS does not reach you.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 24),
      TextFormField(
        key: const ValueKey('email_input_field'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onFieldSubmitted: (_) => _loading ? null : _sendEmail(),
        decoration: const InputDecoration(
          labelText: 'Email address',
          prefixIcon: Icon(Icons.email_outlined),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        validator: (v) => InputValidators.email((v ?? '').trim()),
      ),
      const SizedBox(height: 18),
      _primaryButton('Send code', _sendEmail),
      const SizedBox(height: 6),
      _linkButton('Use mobile number instead', () => _switchTo(_LoginMode.mobile)),
    ];
  }

  List<Widget> _passwordForm() {
    return [
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
      _primaryButton('Log in', _login),
      const SizedBox(height: 6),
      _linkButton('Forgot password? Email me a login code', _emailCodeFromPassword),
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
      const SizedBox(height: 6),
      _linkButton('Use mobile number instead', () => _switchTo(_LoginMode.mobile)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final form = switch (_mode) {
      _LoginMode.mobile => _mobileForm(),
      _LoginMode.email => _emailForm(),
      _LoginMode.password => _passwordForm(),
    };
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () {
            if (_mode != _LoginMode.mobile) {
              _switchTo(_LoginMode.mobile);
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.primaryLight, Colors.white],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(child: SevoLogo(height: 26)),
                ),
                const SizedBox(height: 28),
                ...form,
                if (_mode == _LoginMode.mobile) ...[
                  const SizedBox(height: 14),
                  _linkButton('Continue as Guest', () => context.go(AppRoutes.home)),
                ],
                const SizedBox(height: 18),
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
