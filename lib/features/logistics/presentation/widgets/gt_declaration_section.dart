import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/gt_declaration.dart';
import '../../domain/gt_providers.dart';

/// "Handling & confirmation": notes for the driver at pickup / drop and the accuracy confirmation (required when the
/// customer typed their own goods).
class GtDeclarationSection extends ConsumerStatefulWidget {
  const GtDeclarationSection({super.key, required this.required});

  /// True when the customer typed goods themselves: the confirmation then has to be ticked.
  final bool required;

  @override
  ConsumerState<GtDeclarationSection> createState() => _GtDeclarationSectionState();
}

class _GtDeclarationSectionState extends ConsumerState<GtDeclarationSection> {
  late final TextEditingController _pickup;
  late final TextEditingController _drop;

  @override
  void initState() {
    super.initState();
    final d = ref.read(gtGoodsDeclProvider);
    _pickup = TextEditingController(text: d.pickup);
    _drop = TextEditingController(text: d.drop);
  }

  @override
  void dispose() {
    _pickup.dispose();
    _drop.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border, width: 0.8),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final decl = ref.watch(gtGoodsDeclProvider);
    void set(GtGoodsDecl next) => ref.read(gtGoodsDeclProvider.notifier).state = next;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            const Expanded(
              child: Text('Handling & confirmation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
            ),
            // Same as the website: the customer can read exactly which goods the driver is required to refuse.
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => showProhibitedGoodsSheet(context),
              icon: const Icon(Icons.block_rounded, size: 15),
              label: const Text('View Prohibited Items', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text('Instructions at pickup (optional)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        TextField(
          controller: _pickup,
          maxLength: GtGoodsDecl.maxNoteLength,
          decoration: _dec('e.g. 3rd floor, no lift; call on arrival'),
          onChanged: (v) => set(decl.copyWith(pickup: v)),
        ),
        const SizedBox(height: 10),
        const Text('Instructions at drop (optional)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        TextField(
          controller: _drop,
          maxLength: GtGoodsDecl.maxNoteLength,
          decoration: _dec('e.g. hand over to security; gate 2'),
          onChanged: (v) => set(decl.copyWith(drop: v)),
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          value: decl.accepted,
          onChanged: (v) => set(decl.copyWith(accepted: v ?? false)),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(
            'I confirm the goods are described accurately and none are hazardous, illegal or restricted.${widget.required ? ' *' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'The driver may check the goods at pickup and can refuse a load that does not match.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ]),
    );
  }
}

const _prohibitedCategories = <({String title, String desc})>[
  (title: 'Weapons, Firearms & Ammunition', desc: 'Firearms, ammunition, explosive devices, military weapons, or daggers.'),
  (title: 'Explosives & Pyrotechnics', desc: 'Commercial fireworks, firecrackers, dynamite, gunpowder, or blasting agents.'),
  (title: 'Illegal Drugs & Narcotics', desc: 'Narcotics, cannabis/ganja, unlawful contraband, or banned substances.'),
  (title: 'Hazardous & Toxic Chemicals', desc: 'Bulk industrial acids, toxic waste, biohazards, radioactive materials, or chemical poisons.'),
  (title: 'Highly Flammable Fuels & Volatiles', desc: 'Raw petroleum, unsealed bulk gasoline/diesel barrels, or volatile flammable crude.'),
  (title: 'Illegal Wildlife & Animal Articles', desc: 'Protected wildlife, ivory, elephant tusks, or restricted animal parts.'),
];

/// "Prohibited & Restricted Goods" - the statutory list the driver must refuse, plus the household-shifting exemption.
/// Mirrors the website's goods declaration pop-up.
Future<void> showProhibitedGoodsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Prohibited & Restricted Goods', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navy)),
                  Text('Statutory Transportation Safety Policy', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded), tooltip: 'Close'),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Text.rich(TextSpan(children: [
                    TextSpan(text: 'Legal Notice: ', style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(
                      text: 'Transportation of hazardous, flammable, explosive, or illicit goods is strictly prohibited under Indian transport laws. '
                          'Drivers are legally required to refuse non-compliant loads.',
                    ),
                  ]), style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF78350F))),
                ),
                const SizedBox(height: 12),
                for (final c in _prohibitedCategories)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(c.desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
                        ]),
                      ),
                    ]),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Text.rich(TextSpan(children: [
                    TextSpan(text: 'Packers & Movers Household Shifting Exemption: ', style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(
                      text: 'Standard domestic household items (such as kitchen cutlery, sealed domestic cooking gas cylinders, and household '
                          'cleaning supplies) are permitted for domestic relocation services.',
                    ),
                  ]), style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF064E3B))),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size(0, 46)),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
