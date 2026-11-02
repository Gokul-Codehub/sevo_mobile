import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/env.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/errors/error_manager.dart';
import '../../../core/navigation/safe_back.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/app_toast.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/auth_notifier.dart';

/// Profile -> Delete Account. Two steps: understand what happens and ask for a code, then confirm with the
/// code sent to the customer's own phone. Refused (with the reason) while a booking or order is still active.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _code = TextEditingController();
  DeletionCodeInfo? _sent; // non-null = step 2
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _blocked; // active bookings / orders
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = (_cooldown - 1).clamp(0, 9999));
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
      _blocked = null;
    });
    final result = await ref.read(authProvider.notifier).requestAccountDeletion();
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        setState(() {
          _busy = false;
          _sent = data;
        });
        _startCooldown(data.resendAfterSeconds);
      case Failure(:final error):
        final blocked = error is ValidationError && error.code == 'ACTIVE_ACTIVITY';
        setState(() {
          _busy = false;
          _blocked = blocked ? (error.extra['details'] is Map ? Map<String, dynamic>.from(error.extra['details'] as Map) : const {}) : null;
          _error = blocked ? null : ErrorManager.present(error).body;
        });
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(authProvider.notifier).confirmAccountDeletion(_code.text);
    if (!mounted) return;
    switch (result) {
      case Success():
        AppToast.show(context, 'Your account has been deleted.');
        context.go('/');
      case Failure(:final error):
        setState(() {
          _busy = false;
          _error = error is ValidationError && error.message.isNotEmpty ? error.message : ErrorManager.present(error).body;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Delete account', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
        leading: BackButton(onPressed: context.goBack),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            icon: Icons.delete_forever_rounded,
            title: 'Before you go',
            children: const [
              _Bullet('Your name, phone number, email, saved addresses and notifications are permanently removed.'),
              _Bullet('You will be signed out on all your phones.'),
              _Bullet('Records of past bookings and payments are kept without your personal details, as required for accounting and the law.'),
              _Bullet('This cannot be undone.'),
            ],
          ),
          if (_blocked != null) ...[
            const SizedBox(height: 12),
            _card(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              title: 'You still have something in progress',
              children: [
                Text(
                  'We cannot delete your account while a booking or order is active'
                  '${_blocked!['bookings'] != null && _blocked!['bookings'] != 0 ? ' (${_blocked!['bookings']} booking(s))' : ''}'
                  '${_blocked!['orders'] != null && _blocked!['orders'] != 0 ? ' (${_blocked!['orders']} order(s))' : ''}. '
                  'Please wait until it is completed, or cancel it, then come back.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => context.push('/bookings'), child: const Text('View my bookings')),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (_sent == null)
            FilledButton(
              onPressed: _busy ? null : _sendCode,
              style: FilledButton.styleFrom(backgroundColor: AppColors.error, minimumSize: const Size.fromHeight(50)),
              child: Text(_busy ? 'Sending...' : 'Send confirmation code'),
            )
          else ...[
            Text('Enter the 6-digit code we sent to ${_sent!.sentTo}.', style: const TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '------',
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || _code.text.length != 6 ? null : _confirm,
              style: FilledButton.styleFrom(backgroundColor: AppColors.error, minimumSize: const Size.fromHeight(50)),
              child: Text(_busy ? 'Deleting...' : 'Delete my account permanently'),
            ),
            TextButton(
              onPressed: _busy || _cooldown > 0 ? null : _sendCode,
              child: Text(_cooldown > 0 ? 'Resend code in ${_cooldown}s' : 'Resend code'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => launchUrl(Uri.parse(Env.accountDeletionUrl), mode: LaunchMode.externalApplication),
              child: const Text('Prefer the website? Request deletion there', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required IconData icon, required String title, required List<Widget> children, Color color = AppColors.navy}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E8EE))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color))),
          ]),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  ', style: TextStyle(fontSize: 13)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ]),
      );
}
