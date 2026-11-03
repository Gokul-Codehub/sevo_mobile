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
        const Text('Handling & confirmation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
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
