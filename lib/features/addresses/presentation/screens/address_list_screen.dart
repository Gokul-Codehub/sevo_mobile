import '../../../../shared/widgets/login_required_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../domain/address_models.dart';
import '../../domain/address_notifier.dart';
import 'guest_location_picker_screen.dart';
import '../../../../core/navigation/safe_back.dart';

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
      // A location is needed to use the app; an account is only needed to book.
      // So guests picking a service location get the no-login picker.
      if (isSelectionMode) return const GuestLocationPickerScreen();
      return Scaffold(
        backgroundColor: const Color(0xFFF7F9FC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F9FC),
          title: Text(isSelectionMode ? 'Select Service Address' : 'Saved Addresses'),
        ),
        body: LoginRequiredView(
          title: 'Login Required',
          subtitle: 'Please log in to manage your saved addresses.',
          buttonLabel: 'Log In',
          onPressed: () => context.push(AppRoutes.login),
        ),
      );
    }

    final addressesAsync = ref.watch(addressListProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(7),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.goBack(),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.navy, size: 20),
            ),
          ),
        ),
        title: Text(
          isSelectionMode ? 'Select Service Address' : 'Addresses',
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
            fontSize: 16.5,
          ),
        ),
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // Add New Address
              Material(
                color: Color(0xFFE6ECF4),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/addresses/add'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                    child: Row(
                      children: [
                        Icon(Icons.add_rounded,
                            color: AppColors.navy, size: 26),
                        SizedBox(width: 16),
                        Text(
                          'Add New Address',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (addresses.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      Text('📍', style: TextStyle(fontSize: 38.5)),
                      SizedBox(height: 12),
                      Text('No Addresses Saved',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy)),
                      SizedBox(height: 6),
                      Text(
                        'Add an address where our technicians can reach you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              for (final address in addresses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AddressCard(
                    address: address,
                    isSelected: selectedAddress?.id == address.id,
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
                          SnackBar(
                              content: Text(error),
                              backgroundColor: AppColors.error),
                        );
                      }
                    },
                    onDelete: () => _confirmDelete(context, ref, address),
                    onEdit: () =>
                        context.push('/addresses/edit', extra: address),
                  ),
                ),
            ],
          );
        },
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
    required this.onEdit,
  });

  final Address address;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  String get _typeLower => address.addressType.toLowerCase();

  IconData get _typeIcon {
    if (_typeLower.contains('home')) return Icons.home_rounded;
    if (_typeLower.contains('work') || _typeLower.contains('office')) {
      return Icons.business_rounded;
    }
    return Icons.location_on_rounded;
  }

  String get _typeLabel {
    if (_typeLower.contains('work') || _typeLower.contains('office')) {
      return 'Office';
    }
    if (_typeLower.contains('home')) return 'Home';
    if (_typeLower.contains('other')) return 'Other Location';
    final t = address.addressType;
    return t.isEmpty ? 'Address' : t[0].toUpperCase() + t.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFFF1FAF5) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? AppColors.navy : const Color(0xFFE2E8F0),
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE6ECF4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_typeIcon, size: 24, color: AppColors.navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _typeLabel,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          address.formattedAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.navy : Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.navy
                              : const Color(0xFFCBD5E1),
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              size: 17, color: Colors.white)
                          : null,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 58),
                  if (address.isDefault)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCE6F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Default',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded,
                        size: 24, color: AppColors.textSecondary),
                    onSelected: (val) {
                      if (val == 'default') onSetDefault();
                      if (val == 'edit') onEdit();
                      if (val == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
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
                            Icon(Icons.delete_outline,
                                size: 18, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Delete',
                                style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
