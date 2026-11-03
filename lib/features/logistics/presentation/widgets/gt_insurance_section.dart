import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/gt_models.dart';
import '../../domain/gt_providers.dart';
import '../../domain/logistics_providers.dart';

String _inr(double v) => '₹${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

const _unavailableWhy = {
  'not_offered': 'Transit insurance is not being offered for this service at the moment.',
  'terms_incomplete': "Transit insurance can't be sold for this service yet because its policy terms are not fully set up.",
  'expired': "Transit insurance can't be sold for this service because its policy terms have expired.",
  'not_yet_valid': 'Transit insurance for this service is not available yet; its policy terms have not started.',
};

/// Optional transit insurance, same as the web: the premium, cover, policy reference, exclusions and consent wording all
/// come from the server (`/logistics/insurance-terms/`), the very figures that are billed. Sold with online / wallet
/// payment only. When it cannot be sold the customer is told why, and that the goods will not be insured.
class GtInsuranceSection extends ConsumerWidget {
  const GtInsuranceSection({super.key, required this.declaredValue});

  /// The booking's declared goods value (null / 0 until entered).
  final double? declaredValue;

  Widget _notice(String title, String body) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4)),
        ]),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(selectedVehicleCategoryProvider).serviceCategoryValue;
    final mode = ref.watch(ptlModeProvider) ? 'ptl' : null;
    final availability = ref.watch(insuranceAvailabilityProvider((service: service, mode: mode)));

    return availability.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => _notice(
        'Transit insurance',
        'We could not check transit insurance availability right now, so it cannot be added to this booking. Your goods will not be insured.',
      ),
      data: (avail) {
        if (!avail.offered) {
          final why = _unavailableWhy[avail.reason] ?? 'Transit insurance is not available for this service right now.';
          return _notice(
            'Transit insurance',
            '$why Your goods will not be insured; our liability is limited as set out in the Terms of Service.',
          );
        }
        final enabled = ref.watch(insuranceOptInProvider);
        final consent = ref.watch(insuranceConsentProvider);
        final prepaid = ref.watch(gtPaymentMethodProvider) != 'cod';
        final value = declaredValue ?? 0;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Add transit insurance for your goods', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
              value: enabled,
              onChanged: (v) {
                ref.read(insuranceOptInProvider.notifier).state = v;
                if (!v) ref.read(insuranceConsentProvider.notifier).state = false;
              },
            ),
            if (!enabled)
              const Text(
                'Without insurance your goods are not insured; our liability for loss or damage is limited as set out in the Terms of Service.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
              ),
            if (enabled && !prepaid)
              const Text(
                'Insurance is available with online or wallet payment. Choose one under Payment to add it.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309), height: 1.4),
              ),
            if (enabled && prepaid && value <= 0)
              const Text(
                'Enter the declared value of your goods above to see the premium.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309), height: 1.4),
              ),
            if (enabled && prepaid && value > 0)
              _Terms(
                terms: ref.watch(insuranceTermsProvider((value: value, service: service, mode: mode))),
                consent: consent,
                onConsent: (v) => ref.read(insuranceConsentProvider.notifier).state = v,
              ),
          ]),
        );
      },
    );
  }
}

class _Terms extends StatelessWidget {
  const _Terms({required this.terms, required this.consent, required this.onConsent});

  final AsyncValue<InsuranceTerms> terms;
  final bool consent;
  final ValueChanged<bool> onConsent;

  @override
  Widget build(BuildContext context) => terms.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(minHeight: 2),
        ),
        error: (_, __) => const Text(
          'We could not get the premium right now. You can still book without insurance.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309)),
        ),
        data: (t) {
          if (!t.offered) {
            return const Text('Insurance is not available for this booking.', style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309)));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Premium ${_inr(t.premium ?? 0)}'
              '${t.ratePercent != null ? ' (${t.ratePercent!.toStringAsFixed(t.ratePercent! % 1 == 0 ? 0 : 2)}% of declared value)' : ''}'
              ', covers up to ${_inr(t.liabilityCap ?? 0)}. Added to your fare.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((t.policyReference ?? '').isNotEmpty)
                  Text('Policy: ${t.policyReference}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Exclusions and limitations', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                Text(t.exclusions ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4)),
                const SizedBox(height: 6),
                // Its own Material: the box around it has a background colour, which would hide the tap highlight.
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    value: consent,
                    onChanged: (v) => onConsent(v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(t.consentText ?? '', style: const TextStyle(fontSize: 11, height: 1.4)),
                  ),
                ),
                if (!consent)
                  const Text(
                    'Tick the box to add cover. Without it your booking is not insured.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309)),
                  ),
              ]),
            ),
          ]);
        },
      );
}
