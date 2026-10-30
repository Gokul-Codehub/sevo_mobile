import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../domain/app_update_controller.dart';

/// Shared header: SEVO mark, title and the "installed -> latest" line.
class _UpdateHeader extends StatelessWidget {
  const _UpdateHeader({required this.title, required this.subtitle, this.icon = Icons.system_update_rounded});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
          child: Icon(icon, size: 32, color: AppColors.primary),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.title, required this.notes});

  final String title;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty && title.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isNotEmpty ? title : "What's new",
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy),
          ),
          for (final note in notes.take(6))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 5, color: AppColors.primary),
                  ),
                  Expanded(child: Text(note, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textPrimary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _versionLabel(String name, int build) => name.isEmpty ? 'build $build' : '$name ($build)';

/// Optional update: "Update Now" starts the Google Play flexible update, "Maybe Later" dismisses.
class OptionalUpdateDialog extends ConsumerWidget {
  const OptionalUpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final policy = state.policy;
    final installed = state.installed;
    if (policy == null) return const SizedBox.shrink();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _UpdateHeader(
                title: 'Update available',
                subtitle: 'Installed ${_versionLabel(installed?.versionName ?? '', installed?.buildNumber ?? 0)}\n'
                    'Latest ${_versionLabel(policy.latestVersionName, policy.latestBuild)}',
              ),
              _ReleaseNotes(title: policy.releaseTitle, notes: policy.releaseNotes),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.busy
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          ref.read(appUpdateControllerProvider.notifier).updateNow();
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(appUpdateControllerProvider.notifier).maybeLater();
                },
                child: const Text('Maybe Later', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen, non-dismissible screen shown while the installed build is
/// below the supported minimum. It covers the whole app (see AppUpdateGate).
class MandatoryUpdateScreen extends ConsumerWidget {
  const MandatoryUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final policy = state.policy;
    final installed = state.installed;

    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _UpdateHeader(
                    title: 'Update required',
                    subtitle: 'Please update SEVO to keep using the app.\n'
                        'Installed ${_versionLabel(installed?.versionName ?? '', installed?.buildNumber ?? 0)}\n'
                        'Minimum supported ${_versionLabel(policy?.minimumVersionName ?? '', policy?.minimumBuild ?? 0)}',
                    icon: Icons.system_security_update_warning_rounded,
                  ),
                  _ReleaseNotes(title: policy?.releaseTitle ?? '', notes: policy?.releaseNotes ?? const []),
                  if (state.message != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFEF3F2), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        state.message!,
                        style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: state.busy ? null : controller.updateNow,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: state.busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                          : const Text('Update Now', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ),
                  if (state.playUnavailable) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: state.busy ? null : controller.openStore,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Open Play Store', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    TextButton(
                      onPressed: state.busy ? null : controller.recheck,
                      child: const Text('I already updated - check again', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
