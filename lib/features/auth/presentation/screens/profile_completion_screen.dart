import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/auth_notifier.dart';

/// Screen allowing newly registered customers to set their display name & optional email.
class ProfileCompletionScreen extends ConsumerStatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  ConsumerState<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState
    extends ConsumerState<ProfileCompletionScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Fixed 2026-10-01 per explicit request ("it must not ask another email
  // while already verified"): a customer who signed up via the Email
  // channel has just typed AND OTP-verified their email one screen ago —
  // by the time they land here the backend has already saved that exact
  // address to the account, and UserProfile.fromJson reads it straight off
  // the verify response into currentUserProvider. Asking for it again here
  // as a blank field, as if nothing had happened, was pure, confusing
  // friction. Phone-channel signups never had this problem (there's no
  // phone field on this screen to begin with) — this fix is specifically
  // for the email side.
  String? _verifiedEmail;

  @override
  void initState() {
    super.initState();
    final currentEmail = ref.read(currentUserProvider)?.email?.trim();
    if (currentEmail != null && currentEmail.isNotEmpty) {
      _verifiedEmail = currentEmail;
      _emailController.text = currentEmail;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final error = await ref.read(authProvider.notifier).completeProfile(
          name: _nameController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile setup complete! Welcome to CalServices.'),
          backgroundColor: AppColors.success,
        ),
      );

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
          final returnTarget = pendingAction.returnPath ?? AppRoutes.home;
          context.go(returnTarget);
        }
      } else {
        context.go(AppRoutes.home);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Complete Profile'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text('Almost there! 🎉', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Please provide your name so our service professionals know who they are assisting.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),

                // Name field (Required)
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. Rahul Sharma',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your full name';
                    }
                    if (val.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email: already verified via OTP on the previous screen —
                // show it as a read-only confirmation instead of asking for
                // it again. Only shown when it's actually known.
                if (_verifiedEmail != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_outlined,
                            color: AppColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _verifiedEmail!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        const Text(
                          'Verified',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // Email field (Optional) — only shown when the customer
                  // signed up via phone and hasn't given an email yet.
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address (Optional)',
                      hintText: 'For booking invoices and receipts',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (val) {
                      if (val != null && val.trim().isNotEmpty) {
                        if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$')
                            .hasMatch(val.trim())) {
                          return 'Enter a valid email address or leave blank';
                        }
                      }
                      return null;
                    },
                  ),

                const SizedBox(height: 36),

                FilledButton(
                  onPressed: _isLoading ? null : _handleComplete,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save and Continue'),
                ),
                const SizedBox(height: 16),

                Center(
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: const Text('Skip for now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
