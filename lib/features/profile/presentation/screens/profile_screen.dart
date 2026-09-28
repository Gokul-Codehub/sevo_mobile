import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../config/env.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../auth/domain/auth_notifier.dart';

/// Screen 20: Profile & Account Management
/// Matches reference screen 20 with verified customer profile card, stats counters,
/// grouped settings menu, support links, and logout action.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Added 2026-09-16: the profile photo circle used to be purely
  // decorative — the checkmark badge over it wasn't tappable, and there
  // was no upload flow anywhere in the app (only ever reading whatever
  // avatar_url/profile_picture the backend already had). PATCH
  // /api/v1/auth/profile/ accepts multipart with an `avatar` field, so
  // this is a real upload, not a client-side workaround.
  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Update Profile Photo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open ${source == ImageSource.camera ? "camera" : "gallery"}: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    final error = await ref.read(authProvider.notifier).updateAvatar(picked.path);
    if (!context.mounted) return;
    setState(() => _uploadingAvatar = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Profile photo updated!'),
        backgroundColor: error != null ? AppColors.error : AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            // ── 1. Profile Header Card ──
            if (user != null) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _uploadingAvatar
                          ? null
                          : () => _pickAndUploadAvatar(context),
                      child: Stack(
                        children: [
                          ClipOval(
                            child: user.profilePictureUrl != null &&
                                    user.profilePictureUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: user.profilePictureUrl!,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 64,
                                      height: 64,
                                      color: AppColors.primary,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        _buildAvatarFallback(user.name),
                                  )
                                : _buildAvatarFallback(user.name),
                          ),
                          if (_uploadingAvatar)
                            Positioned.fill(
                              child: ClipOval(
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _uploadingAvatar
                                    ? Icons.check_rounded
                                    : Icons.camera_alt_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  (user.name != null && user.name!.isNotEmpty)
                                      ? user.name!
                                      : 'Valued Customer',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'VERIFIED',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.phone,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (user.email != null &&
                              user.email!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              user.email!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.border, width: 0.8),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 16, color: AppColors.navy),
                      ),
                      onPressed: () => _showEditProfileModal(context, ref),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primaryLight,
                      child: Icon(Icons.person_rounded,
                          size: 32, color: AppColors.primary),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Welcome to SEVO',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sign in to sync your bookings, saved addresses, and payments.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => context.push('/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Login / Sign Up'),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── 2. Account & Bookings Menu ──
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Column(
                children: [
                  _MenuTile(
                    icon: Icons.receipt_long_rounded,
                    title: 'My Bookings',
                    subtitle: 'Active bookings & past service history',
                    onTap: () => context.go('/bookings'),
                  ),
                  const Divider(
                      height: 1, indent: 56, color: AppColors.border),
                  _MenuTile(
                    icon: Icons.location_on_rounded,
                    title: 'Saved Addresses',
                    subtitle: 'Manage home, work & other addresses',
                    onTap: () => context.push('/addresses'),
                  ),
                  const Divider(
                      height: 1, indent: 56, color: AppColors.border),
                  _MenuTile(
                    icon: Icons.verified_rounded,
                    title: '30-Day Service Guarantee',
                    subtitle: 'SEVO rework warranty & assurance',
                    onTap: () => _showGuaranteeDialog(context),
                  ),
                  const Divider(
                      height: 1, indent: 56, color: AppColors.border),
                  _MenuTile(
                    icon: Icons.headset_mic_rounded,
                    title: 'Help & Customer Care',
                    subtitle: 'WhatsApp & call support (24/7)',
                    onTap: () => context.go('/support'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── 3. Legal & App Policies ──
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Column(
                children: [
                  _MenuTile(
                    icon: Icons.description_rounded,
                    title: 'Terms of Service',
                    onTap: () => _showTermsDialog(context),
                  ),
                  const Divider(
                      height: 1, indent: 56, color: AppColors.border),
                  _MenuTile(
                    icon: Icons.privacy_tip_rounded,
                    title: 'Privacy Policy',
                    onTap: () => _showPrivacyDialog(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 4. Sign Out Button ──
            if (user != null) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(
                        color: Color(0xFFFCA5A5), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _showLogoutDialog(context, ref),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── 5. App Version Footer ──
            Text(
              '${Env.appName} v${Env.appVersion} • Built with ❤️ for Hosur',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textHint,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showEditProfileModal(BuildContext context, WidgetRef ref) {
    final user = ref.read(currentUserProvider);
    final nameController = TextEditingController(text: user?.name ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit Profile',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email Address'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Fixed 2026-08-27: this previously showed "Profile updated
                  // successfully!" unconditionally, even when the backend
                  // call failed — so a failed save looked identical to a
                  // successful one and the name silently stayed unchanged.
                  final error = await ref
                      .read(authProvider.notifier)
                      .completeProfile(
                        name: nameController.text.trim(),
                        email: emailController.text.trim().isNotEmpty
                            ? emailController.text.trim()
                            : null,
                      );
                  if (!context.mounted) return;
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
                        content: Text('Profile updated successfully!'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        content: const Text(
          'Are you sure you want to sign out of SEVO?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/');
              }
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _showGuaranteeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Row(
          children: [
            Icon(Icons.verified, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              '30-Day Guarantee',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: const Text(
          'Every service performed by SEVO professionals comes with our 30-Day Service Assurance Guarantee.\n\nIf the same issue recurs within 30 days of completion, we will send a technician for a complimentary inspection and rework at no extra service charge.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text(
          'Terms of Service',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        content: const SingleChildScrollView(
          child: Text(
            '1. Acceptance of Terms: By booking services through SEVO, you agree to abide by our service standards and cancellation rules.\n\n2. Pricing & Payments: All prices shown include applicable taxes and service fees. An advance deposit of 20% is required to secure your booking.\n\n3. Rescheduling & Cancellation: You may reschedule or cancel your booking without penalty up to 2 hours prior to the scheduled slot.\n\n4. Verified Professionals: All technicians are vetted and background-verified.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'SEVO is committed to protecting your personal data.\n\n1. Data Collection: We collect your phone number, name, email, and service addresses solely for booking fulfillment and technician dispatch.\n\n2. Encryption: All communications are encrypted using TLS 1.3. Sensitive tokens are stored securely in Android Keystore / EncryptedSharedPreferences.\n\n3. Payment Security: Payment details are handled exclusively by RBI-authorized payment aggregator Razorpay and never stored on our servers.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            )
          : null,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppColors.textHint,
      ),
      onTap: onTap,
    );
  }
}

Widget _buildAvatarFallback(String? name) {
  final initial = (name != null && name.trim().isNotEmpty)
      ? name.trim()[0].toUpperCase()
      : 'U';
  return Container(
    width: 64,
    height: 64,
    color: AppColors.navy,
    child: Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    ),
  );
}
