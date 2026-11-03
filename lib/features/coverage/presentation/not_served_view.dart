import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../shared/theme/app_colors.dart';
import '../../addresses/presentation/widgets/location_sheet.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../catalog/data/marketplace_catalog_repository.dart';
import '../../home/domain/home_flow_mode.dart';
import '../data/coverage_repository.dart';
import '../domain/coverage.dart';

/// Replaces Home when we are SURE the vertical being browsed is not served at the delivery location. The Blinkit
/// pattern: say it plainly, offer "Notify me when you arrive", let the customer change the location, and, where the
/// other vertical is available here, offer that instead of a dead end.
class CoverageGate extends ConsumerWidget {
  const CoverageGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(homeFlowModeProvider);
    final info = notServedFor(ref.watch(areaCoverageProvider), mode);
    if (info == null) return child;
    final point = ref.watch(deliveryPointProvider);
    return NotServedView(key: ValueKey('${info.mode.name}|${point.key}'), info: info);
  }
}

class NotServedView extends ConsumerStatefulWidget {
  const NotServedView({super.key, required this.info});

  final NotServed info;

  @override
  ConsumerState<NotServedView> createState() => _NotServedViewState();
}

class _NotServedViewState extends ConsumerState<NotServedView> {
  final _phone = TextEditingController();
  bool _sending = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String get _vertical => widget.info.mode == HomeFlowMode.groceries ? 'groceries' : 'services';
  String get _what => widget.info.mode == HomeFlowMode.groceries ? 'Groceries & vegetables' : 'Our services';

  String _name(HomeFlowMode m) => m == HomeFlowMode.groceries ? 'Groceries' : 'Services';

  Future<void> _notify() async {
    final point = ref.read(deliveryPointProvider);
    final user = ref.read(currentUserProvider);
    final accountPhone = (user?.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final typed = _phone.text.trim();
    if (accountPhone.length < 10 && !RegExp(r'^[6-9]\d{9}$').hasMatch(typed)) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }
    if (point.lat == null || point.lng == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await ref.read(coverageRepositoryProvider).notifyMe(
          vertical: _vertical,
          lat: point.lat!,
          lng: point.lng!,
          phone: accountPhone.length >= 10 ? null : typed,
          pincode: point.pincode,
          areaLabel: point.label,
        );
    if (!mounted) return;
    setState(() {
      _sending = false;
      switch (result) {
        case Success():
          _done = true;
        case Failure(:final error):
          _error = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final point = ref.watch(deliveryPointProvider);
    final user = ref.watch(currentUserProvider);
    final knowsPhone = (user?.phone ?? '').replaceAll(RegExp(r'\D'), '').length >= 10;
    final other = widget.info.otherServed;
    final place = point.label.isEmpty ? 'your location' : point.label;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(color: Color(0xFFFFF4E5), shape: BoxShape.circle),
                  child: const Icon(Icons.location_off_outlined, size: 46, color: Color(0xFFB45309)),
                ),
                const SizedBox(height: 22),
                Text(
                  "$_what aren't available here yet",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.navy, height: 1.25),
                ),
                const SizedBox(height: 10),
                Text(
                  _done
                      ? "You're on the list. We'll let you know the moment we arrive at $place."
                      : "We're growing fast, but we don't reach $place yet. Tell us you're interested and we'll notify you the day we arrive.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 22),
                if (_done)
                  const Icon(Icons.check_circle_rounded, size: 40, color: Color(0xFF059669))
                else ...[
                  if (!knowsPhone) ...[
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                      decoration: InputDecoration(
                        hintText: 'Your mobile number',
                        prefixText: '+91  ',
                        filled: true,
                        fillColor: Colors.white,
                        errorText: _error,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: _sending ? null : _notify,
                      child: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Notify me when you arrive', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (knowsPhone && _error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                    ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => showLocationSheet(context),
                    icon: const Icon(Icons.edit_location_alt_outlined, size: 20),
                    label: const Text('Change location', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                ),
                if (other != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => ref.read(homeFlowModeProvider.notifier).state = other,
                    child: Text('Browse ${_name(other)} instead', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
