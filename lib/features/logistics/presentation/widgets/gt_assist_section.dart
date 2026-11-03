import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/gt_assist.dart';
import '../../domain/gt_providers.dart';
import '../../domain/logistics_models.dart';

String _rupees(double v) => '₹${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';

const _floors = <int, String>{
  0: 'Ground floor',
  1: '1st floor',
  2: '2nd floor',
  3: '3rd floor',
  4: '4th floor',
  5: '5th floor or higher',
};

/// "Floor and access" for a goods booking, as on the web: the floor at pickup and drop, whether a lift works there, and
/// whether the vehicle can reach the door. These only brief the driver. When the chosen Mini Truck offers it
/// ([tier] with Admin-set rates) the customer can also pick extra helpers and stairs carrying; what that costs comes
/// back from the server in the fare.
class GtAssistSection extends ConsumerWidget {
  const GtAssistSection({super.key, this.tier});

  /// The vehicle chosen (its extra-help rates), or null when none is offered.
  final LogisticsTier? tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(gtAssistProvider);
    void set(GtAssist next) => ref.read(gtAssistProvider.notifier).state = next;
    final t = tier;
    final helpersOffered = t != null && t.extraHelperCharge > 0 && t.maxExtraHelpers > 0;
    final carryOffered = t != null && t.carryChargePerFloor > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 14),
          title: const Text('Floor and access (optional, helps the driver prepare)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
          children: [
            _EndRow(
              title: 'Floor at pickup',
              floor: a.pickupFloor,
              hasLift: a.pickupHasLift,
              onFloor: (v) => set(a.copyWith(pickupFloor: v, pickupHasLift: v > 0 ? a.pickupHasLift : null)),
              onLift: (v) => set(a.copyWith(pickupHasLift: v)),
            ),
            _EndRow(
              title: 'Floor at drop',
              floor: a.dropFloor,
              hasLift: a.dropHasLift,
              onFloor: (v) => set(a.copyWith(dropFloor: v, dropHasLift: v > 0 ? a.dropHasLift : null)),
              onLift: (v) => set(a.copyWith(dropHasLift: v)),
            ),
            CheckboxListTile(
              value: a.narrowLane,
              onChanged: (v) => set(a.copyWith(narrowLane: v ?? false)),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text('The vehicle cannot reach the door (narrow lane or no parking)', style: TextStyle(fontSize: 12.5)),
            ),
            if (helpersOffered || carryOffered) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    'Standard service is kerb-to-kerb: the driver loads from and unloads at the vehicle tailboard. Pick extra help only if you need it carried.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
                  ),
                  if (helpersOffered) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Extra helpers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          Text('${_rupees(t.extraHelperCharge)} each · up to ${t.maxExtraHelpers}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ]),
                      ),
                      _Stepper(
                        value: a.helpers.clamp(0, t.maxExtraHelpers),
                        min: 0,
                        max: t.maxExtraHelpers,
                        onChanged: (v) => set(a.copyWith(helpers: v)),
                        label: 'helpers',
                      ),
                    ]),
                  ],
                  if (carryOffered)
                    CheckboxListTile(
                      value: a.carry,
                      onChanged: (v) => set(a.copyWith(carry: v ?? false)),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text('Carry goods up or down the stairs (${_rupees(t.carryChargePerFloor)} per floor, only where there is no lift)', style: const TextStyle(fontSize: 12.5)),
                      subtitle: a.carry && !a.hasStairs
                          ? const Text('No floor charge yet: choose a floor above ground with "No, stairs only" at pickup or drop.', style: TextStyle(fontSize: 11, color: Color(0xFFB45309)))
                          : null,
                    ),
                ]),
              ),
            ],
            if (a.hasStairs || a.narrowLane)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFDE68A))),
                child: const Text(
                  'Note: Standard transport covers ground level / vehicle tailboard. If goods must be carried upstairs via stairs or across a long walking distance, please ensure helper assistance is arranged or select an extra helper to avoid driver delays.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EndRow extends StatelessWidget {
  const _EndRow({required this.title, required this.floor, required this.hasLift, required this.onFloor, required this.onLift});
  final String title;
  final int floor;
  final bool? hasLift;
  final ValueChanged<int> onFloor;
  final ValueChanged<bool> onLift;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            key: ValueKey('$title-$floor'),
            initialValue: floor.clamp(0, 5),
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            ),
            items: [for (final e in _floors.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => onFloor(v ?? 0),
          ),
          if (floor > 0) ...[
            const SizedBox(height: 6),
            const Text('Is there a working lift?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Yes', style: TextStyle(fontSize: 12)), selected: hasLift == true, onSelected: (_) => onLift(true)),
              ChoiceChip(label: const Text('No, stairs only', style: TextStyle(fontSize: 12)), selected: hasLift == false, onSelected: (_) => onLift(false)),
            ]),
          ],
        ]),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged, required this.label});
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Fewer $label',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(width: 24, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
        IconButton(
          tooltip: 'More $label',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ]);
}
