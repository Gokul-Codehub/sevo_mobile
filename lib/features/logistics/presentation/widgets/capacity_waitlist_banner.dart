import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../../notifications/data/capacity_waitlist_repository.dart';
import '../../domain/logistics_providers.dart';

/// Shown instead of "no slots" when a FUTURE date has hit its daily booking
/// limit: lets the customer ask to be told if a place opens up (the backend
/// then notifies them in the app and by email, with a time-limited claim), or
/// shows that they already asked.
class CapacityWaitlistBanner extends ConsumerStatefulWidget {
  const CapacityWaitlistBanner({super.key});

  @override
  ConsumerState<CapacityWaitlistBanner> createState() => _CapacityWaitlistBannerState();
}

class _CapacityWaitlistBannerState extends ConsumerState<CapacityWaitlistBanner> {
  bool _busy = false;
  String? _message;

  Future<void> _join(String service, String date) async {
    if (!ref.read(isUserAuthenticatedProvider)) {
      context.push(AppRoutes.login);
      return;
    }
    final address = ref.read(selectedAddressProvider)?.formattedAddress ?? '';
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await ref
        .read(capacityWaitlistRepositoryProvider)
        .join(service: service, date: date, address: address);
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        ref.invalidate(myWaitlistProvider);
        setState(() {
          _busy = false;
          _message = data.message;
        });
      case Failure(:final error):
        setState(() {
          _busy = false;
          _message = error.message;
        });
    }
  }

  Future<void> _cancel(int id) async {
    setState(() => _busy = true);
    await ref.read(capacityWaitlistRepositoryProvider).cancel(id);
    ref.invalidate(myWaitlistProvider);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedBookingDateProvider);
    final service = ref.watch(selectedBookingServiceIdProvider);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final entries = ref.watch(myWaitlistProvider).valueOrNull ?? const [];
    final mine = entries.where((e) => e.date == dateStr && e.isActive).toList();
    final existing = mine.isEmpty ? null : mine.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5D88A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy_rounded, color: Color(0xFFB7791F)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${DateFormat('d MMM').format(date)} is fully booked',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            existing != null
                ? "You're on the list. We'll notify you here and by email if a place opens up — you'll then have a short time to book it."
                : "Want it anyway? We can tell you if a place opens up. You'll get a notification and a short window to book it.",
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
          ),
          if (_message != null && existing == null) ...[
            const SizedBox(height: 6),
            Text(_message!, style: const TextStyle(fontSize: 12.5, color: AppColors.error)),
          ],
          const SizedBox(height: 10),
          if (existing != null)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _cancel(existing.id),
              icon: const Icon(Icons.notifications_off_outlined, size: 18),
              label: const Text('Cancel my alert'),
            )
          else
            FilledButton.icon(
              onPressed: _busy || service == null ? null : () => _join(service, dateStr),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('Notify me when a slot opens'),
            ),
        ],
      ),
    );
  }
}
