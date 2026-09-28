import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../domain/address_models.dart';
import '../../domain/address_notifier.dart';

/// Screen listing customer addresses with options to add, select, edit, or delete.
class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({
    super.key,
    this.isSelectionMode = false,
  });

  final bool isSelectionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guard: unauthenticated users get a login prompt, not an error
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null || currentUser.isGuest) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(isSelectionMode ? 'Select Service Address' : 'Saved Addresses'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 64, color: AppColors.textSecondary),
                const SizedBox(height: 20),
                Text(
                  'Login Required',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please log in to manage your saved addresses.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => context.push(AppRoutes.login),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Log In'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final addressesAsync = ref.watch(addressListProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isSelectionMode ? 'Select Service Address' : 'Saved Addresses'),
      ),
      body: addressesAsync.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: 3,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => const ShimmerCard(height: 110),
        ),
        error: (err, stackTrace) => ErrorStateWidget(
          message: err.toString(),
          onRetry: () => ref.read(addressListProvider.notifier).refresh(),
        ),
        data: (addresses) {
          if (addresses.isEmpty) {
            return EmptyStateWidget(
              title: 'No Addresses Saved',
              subtitle: 'Add an address where our technicians can reach you.',
              emoji: '📍',
              actionLabel: 'Add New Address',
              action: () => context.push('/addresses/add'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: addresses.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final address = addresses[index];
              final isSelected = selectedAddress?.id == address.id;

              return _AddressCard(
                address: address,
                isSelected: isSelected,
                isSelectionMode: isSelectionMode,
                onSelect: () {
                  ref.read(selectedAddressProvider.notifier).state = address;
                  if (isSelectionMode) {
                    context.pop(address);
                  }
                },
                onSetDefault: () async {
                  final error = await ref
                      .read(addressListProvider.notifier)
                      .setDefault(address.id);
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error), backgroundColor: AppColors.error),
                    );
                  }
                },
                onDelete: () => _confirmDelete(context, ref, address),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: () => context.push('/addresses/add'),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add New Address'),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Address address) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address'),
        content: Text('Are you sure you want to delete "${address.addressLine1}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(addressListProvider.notifier).deleteAddress(address.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onSelect,
    required this.onSetDefault,
    required this.onDelete,
  });

  final Address address;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  IconData get _typeIcon => switch (address.addressType) {
        'home' => Icons.home_outlined,
        'work' => Icons.business_outlined,
        _ => Icons.location_on_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: isSelected ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 2 : 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.surfaceVariant : AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _typeIcon,
                      size: 20,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    address.addressType.toUpperCase(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (address.isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.chipEssentialBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'DEFAULT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.chipEssentialText,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                    onSelected: (val) {
                      if (val == 'default') onSetDefault();
                      if (val == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => [
                      if (!address.isDefault)
                        const PopupMenuItem(
                          value: 'default',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 18),
                              SizedBox(width: 8),
                              Text('Set as Default'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                address.formattedAddress,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
