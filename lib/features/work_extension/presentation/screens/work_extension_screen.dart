import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../data/work_extension_repository.dart';

/// Screen for reviewing and approving/declining on-site work extensions requested by technician.
class WorkExtensionScreen extends ConsumerStatefulWidget {
  const WorkExtensionScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  ConsumerState<WorkExtensionScreen> createState() =>
      _WorkExtensionScreenState();
}

class _WorkExtensionScreenState extends ConsumerState<WorkExtensionScreen> {
  bool _isLoading = false;
  String? _finalDecision; // 'approved' | 'rejected'

  Future<void> _handleResponse(bool approve) async {
    setState(() => _isLoading = true);

    final result = await ref
        .read(workExtensionRepositoryProvider)
        .respondToExtension(token: widget.token, approve: approve);

    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case Success():
        setState(() => _finalDecision = approve ? 'approved' : 'rejected');
      case Failure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action failed: ${error.message}'),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extensionAsync = ref.watch(workExtensionDetailsProvider(widget.token));

    if (_finalDecision != null) {
      final isApproved = _finalDecision == 'approved';
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Work Extension Status')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isApproved
                      ? Icons.check_circle_rounded
                      : Icons.cancel_outlined,
                  color: isApproved ? AppColors.success : AppColors.error,
                  size: 72,
                ),
                const SizedBox(height: 16),
                Text(
                  isApproved
                      ? 'Work Extension Approved'
                      : 'Work Extension Declined',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isApproved
                      ? 'The technician has been notified and will proceed with the additional work. The added amount will be reflected in your final bill.'
                      : 'The technician has been notified to proceed only with the original booking scope.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Extra Work Approval'),
      ),
      body: extensionAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: ShimmerCard(height: 250),
        ),
        error: (err, stackTrace) => ErrorStateWidget(
          message: err.toString(),
          onRetry: () =>
              ref.refresh(workExtensionDetailsProvider(widget.token)),
        ),
        data: (proposal) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Alert Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your technician ${proposal.technicianName} has requested approval for extra work on-site.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Technician Diagnosis & Reason
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.border, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Technician Diagnosis',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          proposal.reason,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Breakdown of Extra Work & Parts
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.border, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Proposed Additional Items',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...proposal.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${item.title} (x${item.quantity})',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                Text(
                                  '₹${item.totalPrice}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Additional Total Amount:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${proposal.additionalAmount}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Approval & Decline Actions
                FilledButton.icon(
                  onPressed: _isLoading ? null : () => _handleResponse(true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('Approve Extra Work (+₹${proposal.additionalAmount})'),
                ),
                const SizedBox(height: 12),

                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.errorLight),
                  ),
                  onPressed: _isLoading ? null : () => _handleResponse(false),
                  icon: const Icon(Icons.close),
                  label: const Text('Decline Additional Work'),
                ),

                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}
