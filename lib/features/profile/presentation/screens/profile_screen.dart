import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/env.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../auth/domain/auth_models.dart';
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
                  fontSize: 14,
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
      backgroundColor: const Color(0xFFF4F6FA),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Title ──
            // Row layout (back button | centred title | same-width spacer) so
            // the arrow can never sit on top of the title, unlike the old
            // Stack + Positioned version.
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 52),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user != null) _buildHeaderCard(user) else _buildGuestCard(),

                    const _SectionLabel('Account'),
                    _MenuCard(children: [
                      if (user != null)
                        _MenuRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Manage Profile',
                          onTap: () => _showEditProfileModal(context, ref),
                        ),
                      _MenuRow(
                        icon: Icons.calendar_month_outlined,
                        label: 'My Bookings',
                        onTap: () => context.push('/bookings'),
                      ),
                      _MenuRow(
                        icon: Icons.location_on_outlined,
                        label: 'Saved Addresses',
                        onTap: () => context.push('/addresses'),
                      ),
                      _MenuRow(
                        icon: Icons.notifications_none_rounded,
                        label: 'Notifications',
                        onTap: () => context.push('/notifications'),
                      ),
                    ]),

                    const _SectionLabel('Preferences'),
                    _MenuCard(children: [
                      _MenuRow(
                        icon: Icons.language_rounded,
                        label: 'Language',
                        value: 'English',
                        onTap: () => AppToast.show(
                            context, 'English is the only language available right now.',
                            type: AppToastType.info),
                      ),
                      _MenuRow(
                        icon: Icons.palette_outlined,
                        label: 'Theme',
                        value: 'Light',
                        onTap: () => AppToast.show(
                            context, 'Light is the only theme available right now.',
                            type: AppToastType.info),
                      ),
                      _MenuRow(
                        icon: Icons.verified_user_outlined,
                        label: '30-Day Service Guarantee',
                        onTap: () => _showGuaranteeDialog(context),
                      ),
                    ]),

                    const _SectionLabel('Support'),
                    _MenuCard(children: [
                      _MenuRow(
                        icon: Icons.help_outline_rounded,
                        label: 'Help Center',
                        onTap: () => context.push('/support'),
                      ),
                      _MenuRow(
                        icon: Icons.article_outlined,
                        label: 'Privacy Policy',
                        onTap: () => _showPrivacyDialog(context),
                      ),
                      _MenuRow(
                        icon: Icons.description_outlined,
                        label: 'Terms of Service',
                        onTap: () => _showTermsDialog(context),
                      ),
                      if (user != null)
                        _MenuRow(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete Account',
                          onTap: () => _showDeleteAccountDialog(context, ref),
                        ),
                    ]),

                    if (user != null) ...[
                      const SizedBox(height: 14),
                      _MenuCard(children: [
                        _MenuRow(
                          icon: Icons.logout_rounded,
                          label: 'Log out',
                          danger: true,
                          onTap: () => _showLogoutDialog(context, ref),
                        ),
                      ]),
                    ],

                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        '${Env.appName} v${Env.appVersion}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(UserProfile user) {
    final name = (user.name != null && user.name!.isNotEmpty)
        ? user.name!
        : 'Valued Customer';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploadingAvatar ? null : () => _pickAndUploadAvatar(context),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipOval(
                  child: user.profilePictureUrl != null &&
                          user.profilePictureUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: user.profilePictureUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 80,
                            height: 80,
                            color: AppColors.surfaceVariant,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                                strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                if (user.email != null && user.email!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7788)),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  user.phone,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7788)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.surfaceVariant,
            child: Icon(Icons.person_outline_rounded, size: 32, color: AppColors.navy),
          ),
          const SizedBox(height: 12),
          const Text(
            'Welcome to SEVO',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.navy),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sign in to sync your bookings, saved addresses, and payments.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () => context.push('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Login / Sign Up'),
            ),
          ),
        ],
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
                fontSize: 16,
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
          style: TextStyle(fontSize: 12),
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
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: const Text(
          'Every service performed by SEVO professionals comes with our 30-Day Service Assurance Guarantee.\n\nIf the same issue recurs within 30 days of completion, we will send a technician for a complimentary inspection and rework at no extra service charge.',
          style: TextStyle(fontSize: 12, height: 1.4),
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
            style: TextStyle(fontSize: 11.5, height: 1.4),
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
            'SEVO is committed to protecting your personal data.\n\n1. Data Collection: We collect your phone number, name, email, and service addresses solely for booking fulfillment and technician dispatch.\n\n2. Encryption: All communications are encrypted using TLS 1.3. Sensitive tokens are stored securely in Android Keystore / EncryptedSharedPreferences.\n\n3. Payment Security: Payment details are handled exclusively by RBI-authorized payment aggregator Razorpay and never stored on our servers.\n\n4. Your Rights: You have the right to access, rectify, or request permanent deletion of your account and personal data at any time.',
            style: TextStyle(fontSize: 11.5, height: 1.4),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(
                Uri.parse(Env.privacyPolicyUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 14),
            label: const Text('Open Online (Web)'),
          ),
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

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text(
              'Delete Account',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to delete your SEVO account?\n\n'
                '• This action is permanent and cannot be undone.\n'
                '• Your profile, saved addresses, active bookings, and order history will be permanently deleted from our servers.\n'
                '• Any active loyalty points or coupon discounts will be forfeited.\n',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse(Env.accountDeletionUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new_rounded,
                          size: 14, color: AppColors.primary),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Web Deletion Request Portal',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final error =
                  await ref.read(authProvider.notifier).deleteAccount();
              if (!context.mounted) return;

              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Account deletion notice: $error'),
                    backgroundColor: AppColors.warning,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Your account and data have been permanently deleted.',
                    ),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
              context.go('/');
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }
}


BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1E3A8A).withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 0, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7788),
          ),
        ),
      );
}

/// White rounded card holding [_MenuRow]s separated by indented hairlines.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(
            height: 1, thickness: 0.6, indent: 54, endIndent: 14, color: Color(0xFFECEFF4)));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.navy;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            if (value != null) ...[
              Text(value!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7788))),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded,
                size: 20, color: danger ? AppColors.error : const Color(0xFF5B6678)),
          ],
        ),
      ),
    );
  }
}

Widget _buildAvatarFallback(String? name) {
  final initial = (name != null && name.trim().isNotEmpty)
      ? name.trim()[0].toUpperCase()
      : 'U';
  return Container(
    width: 80,
    height: 80,
    color: AppColors.navy,
    child: Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    ),
  );
}
