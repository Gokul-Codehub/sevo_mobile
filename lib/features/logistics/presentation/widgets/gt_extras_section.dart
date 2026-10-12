import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/gt_models.dart';
import '../../domain/gt_providers.dart';
import '../../domain/logistics_models.dart';
import '../../domain/logistics_providers.dart';

// Goods & Transport sections wired to the updated backend:
//   GtCargoSection     goods catalogue + /evaluate-cargo/ vehicle fitment
//   GtOptionsSection   loading help, transit insurance, GSTIN / e-way bill
//   GtPtlSection       Light PTL (Part Truck Load) per-kg booking
//   GtPoliciesSection  /policies/ terms + /faqs/

const _titleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w800,
  color: AppColors.navy,
);
const _hintStyle = TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4);

InputDecoration _decoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
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

Widget _card(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: child,
    );

String _msg(Object err) {
  if (err is Exception) {
    final m = RegExp(r'^[A-Za-z]+Error\(?\s*(.*?)\)?$').firstMatch(err.toString());
    final t = m?.group(1)?.trim() ?? '';
    return t.isNotEmpty ? t : err.toString();
  }
  return err.toString();
}

// ── Cargo + fitment ─────────────────────────────────────────────────────────

const _kPanelBg = Color(0xFFF8FAFC);

/// Rounded icon + title + subtitle header used at the top of a card.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.required = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.serviceBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.serviceBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title, style: _titleStyle.copyWith(fontSize: 15)),
                  if (required)
                    const Text(
                      ' *',
                      style: TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: _hintStyle),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _fieldLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );

class GtCargoSection extends ConsumerStatefulWidget {
  const GtCargoSection({super.key, required this.city});

  /// Tier city used for the fitment check (the vehicle list is per city).
  final String city;

  @override
  ConsumerState<GtCargoSection> createState() => _GtCargoSectionState();
}

class _GtCargoSectionState extends ConsumerState<GtCargoSection> {
  final _weightController = TextEditingController();
  Timer? _weightDebounce;

  @override
  void dispose() {
    _weightDebounce?.cancel();
    _weightController.dispose();
    super.dispose();
  }

  void _setCargo(CargoDeclaration c) =>
      ref.read(cargoDeclarationProvider.notifier).state = c;

  int _qty(CargoDeclaration c, int itemId) {
    for (final l in c.items) {
      if (l.itemId == itemId) return l.quantity;
    }
    return 0;
  }

  void _setQty(CargoDeclaration c, int itemId, int qty) {
    final lines = c.items.where((l) => l.itemId != itemId).toList();
    if (qty > 0) lines.add(CargoLine(itemId: itemId, quantity: qty));
    _setCargo(c.copyWith(items: lines));
  }

  /// Tapped an item a 2-wheeler cannot carry: offer to book a truck instead.
  Future<void> _offerTruck(GoodsItem item, int categoryId) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'This needs a truck',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        content: Text(
          '"${item.name}" cannot be carried on a 2-wheeler.\n\n'
          'Do you want to ship it by mini truck instead?',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No, continue'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.serviceBlue),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, book a truck'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    final weight = ref.read(cargoDeclarationProvider).declaredWeightKg;
    // Switching the transportation type clears the cargo (the screen's
    // category listener), so re-apply it with this item once that settles.
    ref.read(selectedVehicleCategoryProvider.notifier).state =
        LogisticsVehicleCategory.truck;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cargoDeclarationProvider.notifier).state = CargoDeclaration(
        goodsCategoryId: categoryId,
        items: [CargoLine(itemId: item.id, quantity: 1)],
        declaredWeightKg: weight,
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Switched to Truck. Please pick a vehicle.')),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cargo = ref.watch(cargoDeclarationProvider);
    final categories = ref.watch(goodsCategoriesProvider);
    final tier = ref.watch(selectedLogisticsTierProvider);
    final vehicleCategory = ref.watch(selectedVehicleCategoryProvider);

    // Keep the weight field in step when the provider is reset externally
    // (e.g. a fresh booking).
    if (cargo.declaredWeightKg == null && _weightController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(cargoDeclarationProvider).declaredWeightKg == null) {
          _weightController.clear();
        }
      });
    }

    final itemCount = cargo.items.fold<int>(0, (s, l) => s + l.quantity);

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.inventory_2_outlined,
            title: 'Cargo details',
            required: true,
            subtitle:
                'Tell us what you are moving so we can check the vehicle '
                'can carry it safely.',
          ),
          const SizedBox(height: 16),
          categories.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => const Text(
              'Could not load goods types. You can still enter the weight below.',
              style: _hintStyle,
            ),
            data: (cats) {
              final usable = vehicleCategory == LogisticsVehicleCategory.twoWheeler
                  ? cats.where((c) => c.allowsTwoWheeler).toList()
                  : cats;
              if (usable.isEmpty) return const SizedBox.shrink();
              GoodsCategory? selected;
              for (final c in usable) {
                if (c.id == cargo.goodsCategoryId) selected = c;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Side by side so the type and its items are visible in one
                  // frame; each pane scrolls on its own.
                  Row(
                    children: [
                      Expanded(flex: 5, child: _fieldLabel('Type of goods')),
                      const SizedBox(width: 10),
                      Expanded(flex: 6, child: _fieldLabel('Select items')),
                    ],
                  ),
                  Container(
                    height: 330,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: _kPanelBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: usable.length,
                            itemBuilder: (context, i) {
                              final c = usable[i];
                              final isSel = c.id == cargo.goodsCategoryId;
                              return InkWell(
                                onTap: () => _setCargo(
                                  isSel
                                      ? cargo.copyWith(
                                          clearGoodsCategory: true,
                                          items: const [],
                                        )
                                      : cargo.copyWith(
                                          goodsCategoryId: c.id,
                                          items: const [],
                                        ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? AppColors.serviceBlue.withValues(alpha: 0.10)
                                        : Colors.transparent,
                                    border: Border(
                                      left: BorderSide(
                                        color: isSel
                                            ? AppColors.serviceBlue
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                      bottom: const BorderSide(
                                        color: AppColors.border,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    c.name,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.25,
                                      fontWeight:
                                          isSel ? FontWeight.w800 : FontWeight.w600,
                                      color: isSel
                                          ? AppColors.serviceBlue
                                          : AppColors.navy,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1, thickness: 0.8),
                        Expanded(
                          flex: 6,
                          child: Container(
                            color: Colors.white,
                            child: selected == null
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'Choose a type of goods to see its items.',
                                        textAlign: TextAlign.center,
                                        style: _hintStyle,
                                      ),
                                    ),
                                  )
                                : _ItemList(
                                    twoWheeler: vehicleCategory ==
                                        LogisticsVehicleCategory.twoWheeler,
                                    categoryId: selected.id,
                                    onLockedTap: (it) => _offerTruck(it, selected!.id),
                                    qtyOf: (id) => _qty(cargo, id),
                                    onQty: (id, q) => _setQty(cargo, id, q),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected != null && (selected.infoBanner ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lightbulb_outline_rounded,
                              size: 16, color: Color(0xFFB45309)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selected.infoBanner!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF92400E),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _fieldLabel('Approximate total weight'),
          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration('e.g. 150').copyWith(
              prefixIcon: const Icon(Icons.monitor_weight_outlined,
                  size: 20, color: AppColors.textSecondary),
              suffixText: 'kg',
              suffixStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            onChanged: (v) {
              // Debounced: the weight is part of the quote key, so every
              // change re-quotes (a billed distance lookup server-side).
              _weightDebounce?.cancel();
              _weightDebounce = Timer(const Duration(milliseconds: 600), () {
                if (!mounted) return;
                final current = ref.read(cargoDeclarationProvider);
                final w = double.tryParse(v.trim());
                _setCargo(
                  (w == null || w <= 0)
                      ? current.copyWith(clearWeight: true)
                      : current.copyWith(declaredWeightKg: w),
                );
              });
            },
          ),
          if (itemCount > 0 || cargo.declaredWeightKg != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (itemCount > 0) _summaryPill(Icons.inventory_2_outlined, '$itemCount item${itemCount == 1 ? '' : 's'}'),
                if (cargo.declaredWeightKg != null)
                  _summaryPill(Icons.scale_outlined, '~${cargo.declaredWeightKg!.toStringAsFixed(0)} kg'),
              ],
            ),
          ],
          if (!cargo.isEmpty) ...[
            const SizedBox(height: 14),
            _FitmentBanner(city: widget.city, cargo: cargo, tier: tier),
          ],
        ],
      ),
    );
  }

  Widget _summaryPill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.serviceBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.serviceBlue),
            const SizedBox(width: 5),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.serviceBlue,
              ),
            ),
          ],
        ),
      );
}

class _ItemList extends ConsumerWidget {
  const _ItemList({
    required this.categoryId,
    required this.qtyOf,
    required this.onQty,
    this.twoWheeler = false,
    this.onLockedTap,
  });

  final bool twoWheeler;
  final void Function(GoodsItem item)? onLockedTap;
  final int categoryId;
  final int Function(int itemId) qtyOf;
  final void Function(int itemId, int qty) onQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(goodsItemsProvider(categoryId));
    return items.when(
      loading: () => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Could not load items.', style: _hintStyle),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No listed items for this type. Enter the weight below.',
                textAlign: TextAlign.center,
                style: _hintStyle,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: list.length,
          separatorBuilder: (context, index) => const Divider(height: 1, thickness: 0.6),
          itemBuilder: (context, i) => _ItemRow(
            item: list[i],
            qty: qtyOf(list[i].id),
            onQty: (q) => onQty(list[i].id, q),
            locked: twoWheeler && !list[i].isTwoWheelerCompatible,
            onLockedTap: onLockedTap == null ? null : () => onLockedTap!(list[i]),
          ),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.qty,
    required this.onQty,
    this.locked = false,
    this.onLockedTap,
  });

  /// Called when a locked (faded) item is tapped.
  final VoidCallback? onLockedTap;

  final GoodsItem item;
  final int qty;
  final ValueChanged<int> onQty;

  /// Cannot be carried by the selected vehicle type (2-wheeler).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final tags = [
      if (item.isFragile) 'Fragile',
      if (item.isHeavy) 'Heavy',
      if (item.isOversized) 'Oversized',
      if (item.requiresSpecialHandling) 'Special handling',
    ];
    final active = qty > 0 && !locked;
    // Stacked (name, tags, control) because the pane is only about half the
    // card width. A locked item (needs a truck while a 2-wheeler is selected)
    // is faded and cannot be added.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked ? onLockedTap : null,
      child: Opacity(
      opacity: locked ? 0.45 : 1.0,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            style: TextStyle(
              fontSize: 13,
              height: 1.25,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
          if (locked) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_shipping_outlined,
                    size: 13, color: Color(0xFFB91C1C)),
                const SizedBox(width: 4),
                const Text(
                  'Requires truck',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              ],
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(tags.join(' · '), style: _hintStyle.copyWith(fontSize: 10.5)),
          ],
          const SizedBox(height: 8),
          if (locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kPanelBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: const Text(
                'Not 2W fit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else if (!active)
            GestureDetector(
              onTap: () => onQty(1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.serviceBlue, width: 1),
                ),
                child: const Text(
                  'ADD',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.serviceBlue,
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.serviceBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StepBtn(icon: Icons.remove_rounded, onTap: () => onQty(qty - 1)),
                  SizedBox(
                    width: 26,
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _StepBtn(icon: Icons.add_rounded, onTap: () => onQty(qty + 1)),
                ],
              ),
            ),
        ],
      ),
      ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );
}

class _FitmentBanner extends ConsumerWidget {
  const _FitmentBanner({required this.city, required this.cargo, required this.tier});

  final String city;
  final CargoDeclaration cargo;
  final LogisticsTier? tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cargoFitmentProvider((cargo: cargo, city: city)));
    return async.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => _note(_msg(e), error: true),
      data: (fit) {
        final summary = fit.cargoSummary;
        final errs = summary['validation_errors'];
        if (errs is List && errs.isNotEmpty && errs.first is Map) {
          return _note(
            (errs.first as Map)['error']?.toString() ?? 'Some cargo details are invalid.',
            error: true,
          );
        }
        if (!fit.hasSuitableVehicle) {
          return _note(
            fit.reason ?? 'No vehicle available in $city can carry this load.',
            error: true,
          );
        }
        final t = tier;
        if (t != null && !fit.suitableTierIds.contains(t.id)) {
          final why = fit.incompatibleReason(t.id) ??
              '${t.name} cannot safely carry this load.';
          final rec = fit.recommendedTier;
          final recId = fit.recommendedTierId;
          final sameCategory = rec != null && rec['category']?.toString() == t.category;
          return _note(
            why,
            error: true,
            footer: rec == null
                ? null
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Suggested: ${rec['name']}'
                          '${sameCategory ? '' : ' (change transportation type)'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      if (sameCategory && recId != null)
                        TextButton(
                          onPressed: () {
                            final tiers = ref
                                .read(logisticsTiersProvider(
                                    ref.read(selectedVehicleCategoryProvider)))
                                .valueOrNull;
                            final match = tiers?.where((x) => x.id == recId).firstOrNull;
                            if (match != null) {
                              ref.read(selectedLogisticsTierProvider.notifier).state = match;
                            }
                          },
                          child: const Text('Switch'),
                        ),
                    ],
                  ),
          );
        }
        if (fit.requiresSurvey) {
          return _note('This load may need a closer look before pricing is final.');
        }
        final w = summary['total_weight_kg']?.toString();
        return _note(
          t != null
              ? '${t.name} can carry this load${w != null ? ' (~$w kg)' : ''}.'
              : 'Select a vehicle to continue.',
          ok: t != null,
        );
      },
    );
  }

  Widget _note(String text, {bool error = false, bool ok = false, Widget? footer}) {
    final color = error
        ? AppColors.error
        : (ok ? const Color(0xFF15803D) : AppColors.textSecondary);
    final bg = error
        ? const Color(0xFFFEF2F2)
        : (ok ? const Color(0xFFF0FDF4) : _kPanelBg);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                error
                    ? Icons.error_outline_rounded
                    : (ok ? Icons.check_circle_rounded : Icons.info_outline_rounded),
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: color,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 6), footer],
        ],
      ),
    );
  }
}

// ── Options: loading help, insurance, GSTIN / e-way bill ────────────────────

class GtOptionsSection extends ConsumerStatefulWidget {
  const GtOptionsSection({super.key, required this.declaredValue});

  /// Parsed declared goods value (null / 0 when blank).
  final double? declaredValue;

  @override
  ConsumerState<GtOptionsSection> createState() => _GtOptionsSectionState();
}

class _GtOptionsSectionState extends ConsumerState<GtOptionsSection> {
  final _gstinController = TextEditingController();
  final _ewayController = TextEditingController();
  Timer? _debounce;
  double? _settledValue;

  @override
  void initState() {
    super.initState();
    _settledValue = widget.declaredValue;
  }

  @override
  void didUpdateWidget(covariant GtOptionsSection old) {
    super.didUpdateWidget(old);
    if (old.declaredValue != widget.declaredValue) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _settledValue = widget.declaredValue);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gstinController.dispose();
    _ewayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loadingHelp = ref.watch(loadingHelpProvider);
    final insured = ref.watch(insuranceOptInProvider);
    final ptl = ref.watch(ptlModeProvider);
    final value = _settledValue;

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!ptl)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Loading help', style: _titleStyle),
              subtitle: const Text(
                'The driver helps load and unload your goods. Turn off if you '
                'will handle loading yourself.',
                style: _hintStyle,
              ),
              value: loadingHelp,
              onChanged: (v) => ref.read(loadingHelpProvider.notifier).state = v,
            ),
          if (value != null && value > 0)
            Consumer(
              builder: (context, ref, _) {
                final terms = ref.watch(insuranceTermsProvider(value));
                return terms.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (t) {
                    if (!t.offered) {
                      if (insured) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          ref.read(insuranceOptInProvider.notifier).state = false;
                        });
                      }
                      return const SizedBox.shrink();
                    }
                    return SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Add transit insurance'
                        '${t.premium != null ? ' (₹${t.premium!.toStringAsFixed(2)})' : ''}',
                        style: _titleStyle,
                      ),
                      subtitle: Text(
                        'Covers up to ₹${(t.liabilityCap ?? 0).toStringAsFixed(0)}. '
                        'Requires online payment.',
                        style: _hintStyle,
                      ),
                      value: insured,
                      onChanged: (v) =>
                          ref.read(insuranceOptInProvider.notifier).state = v,
                    );
                  },
                );
              },
            ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('GST & e-way bill (optional)', style: _titleStyle),
              children: [
                TextField(
                  controller: _gstinController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _decoration('Your GSTIN (15 characters)'),
                  onChanged: (v) =>
                      ref.read(customerGstinProvider.notifier).state = v.trim().toUpperCase(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ewayController,
                  keyboardType: TextInputType.number,
                  decoration: _decoration('E-way bill number (12 digits)'),
                  onChanged: (v) =>
                      ref.read(ewayBillNumberProvider.notifier).state = v.trim(),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Goods of higher value may need an e-way bill. You are '
                    'responsible for providing it to the driver at pickup.',
                    style: _hintStyle,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Light PTL (Part Truck Load) ─────────────────────────────────────────────

class GtPtlSection extends ConsumerStatefulWidget {
  const GtPtlSection({
    super.key,
    required this.city,
    required this.tier,
    this.pickupLatitude,
    this.pickupLongitude,
    this.dropLatitude,
    this.dropLongitude,
  });

  final String city;
  final LogisticsTier? tier;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? dropLatitude;
  final double? dropLongitude;

  @override
  ConsumerState<GtPtlSection> createState() => _GtPtlSectionState();
}

class _GtPtlSectionState extends ConsumerState<GtPtlSection> {
  final _weightController = TextEditingController();
  Timer? _weightDebounce;

  @override
  void dispose() {
    _weightDebounce?.cancel();
    _weightController.dispose();
    super.dispose();
  }

  /// Param for [ptlQuoteProvider], or null until everything is known.
  PtlQuoteParam? buildParam(WidgetRef ref) {
    final weight = ref.read(ptlWeightKgProvider);
    if (widget.tier == null ||
        weight == null ||
        weight <= 0 ||
        widget.pickupLatitude == null ||
        widget.pickupLongitude == null ||
        widget.dropLatitude == null ||
        widget.dropLongitude == null) {
      return null;
    }
    return PtlQuoteParam(
      tierId: widget.tier!.id,
      declaredWeightKg: weight,
      pickupLatitude: widget.pickupLatitude!,
      pickupLongitude: widget.pickupLongitude!,
      dropLatitude: widget.dropLatitude!,
      dropLongitude: widget.dropLongitude!,
      laneId: ref.read(selectedGtLaneProvider)?.id,
      loadAssist: ref.read(ptlLoadAssistProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(ptlConfigProvider(widget.city));
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (cfg) {
        if (!cfg.enabled) return const SizedBox.shrink();
        final on = ref.watch(ptlModeProvider);
        ref.watch(ptlWeightKgProvider); // rebuild on change; read in buildParam
        final assist = ref.watch(ptlLoadAssistProvider);
        final lane = ref.watch(selectedGtLaneProvider);
        final tier = widget.tier;
        final eligible = tier == null || cfg.tiers.any((t) => t.id == tier.id);

        PtlQuoteParam? param;
        if (on) {
          // Watching the providers above already rebuilds on change.
          param = buildParam(ref);
        }

        return _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Part Truck Load', style: _titleStyle),
                subtitle: Text(
                  'Pay per kg for part of a truck'
                  '${cfg.ratePerKg != null ? ' (₹${cfg.ratePerKg!.toStringAsFixed(2)}/kg)' : ''}. '
                  'Booked in advance'
                  '${cfg.minAdvanceDays != null && cfg.minAdvanceDays! > 0 ? ' (at least ${cfg.minAdvanceDays} day(s) ahead)' : ''}.',
                  style: _hintStyle,
                ),
                value: on,
                onChanged: (v) {
                  ref.read(ptlModeProvider.notifier).state = v;
                  // Slots differ between spot and PTL — force a re-pick.
                  ref.read(selectedTimeSlotProvider.notifier).state = null;
                },
              ),
              if (on) ...[
                if ((cfg.loadingNotice ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(cfg.loadingNotice!, style: _hintStyle),
                ],
                if (!eligible) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Pick one of these vehicles for Part Truck Load: '
                    '${cfg.tiers.map((t) => t.name).join(', ')}.',
                    style: const TextStyle(fontSize: 12, color: AppColors.error, height: 1.4),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _weightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _decoration(
                    'Cargo weight in kg'
                    '${cfg.minimumChargeableWeightKg != null ? ' (min. ${cfg.minimumChargeableWeightKg!.toStringAsFixed(0)} kg billed)' : ''}',
                  ),
                  onChanged: (v) {
                    _weightDebounce?.cancel();
                    _weightDebounce = Timer(const Duration(milliseconds: 600), () {
                      if (!mounted) return;
                      ref.read(ptlWeightKgProvider.notifier).state =
                          double.tryParse(v.trim());
                    });
                  },
                ),
                if (cfg.lanes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: lane?.id,
                    isExpanded: true,
                    decoration: _decoration('Route (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Any route')),
                      for (final l in cfg.lanes)
                        DropdownMenuItem<int?>(
                          value: l.lane.id,
                          child: Text(
                            '${l.lane.displayLabel} · ₹${l.ratePerKg.toStringAsFixed(2)}/kg',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => ref.read(selectedGtLaneProvider.notifier).state =
                        id == null
                            ? null
                            : cfg.lanes.firstWhere((l) => l.lane.id == id).lane,
                  ),
                ],
                if (cfg.loadAssistOffered)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'Add load assist'
                      '${cfg.loadAssistFee != null ? ' (+₹${cfg.loadAssistFee!.toStringAsFixed(0)})' : ''}',
                      style: _titleStyle,
                    ),
                    value: assist,
                    onChanged: (v) => ref.read(ptlLoadAssistProvider.notifier).state = v,
                  ),
                const SizedBox(height: 10),
                if (param == null)
                  const Text(
                    'Enter the weight, vehicle, pickup and drop to see the fare.',
                    style: _hintStyle,
                  )
                else
                  Consumer(
                    builder: (context, ref, _) {
                      final q = ref.watch(ptlQuoteProvider(param!));
                      return q.when(
                        loading: () => const LinearProgressIndicator(minHeight: 2),
                        error: (e, _) => Text(
                          _msg(e),
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.error, height: 1.4),
                        ),
                        data: (quote) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Part Truck Load fare',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '₹${quote.total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Quote notices: supply hint + estimated-distance consent ─────────────────

/// Shown under the spot fare. `supply` is informational only (never blocks);
/// the estimated-distance checkbox is required by the backend when road
/// routing is unavailable and Admin policy is ESTIMATE_WITH_CONSENT.
class GtQuoteNotices extends ConsumerWidget {
  const GtQuoteNotices({super.key, required this.quote});

  final LogisticsQuote quote;

  /// True when booking this quote needs the customer's explicit consent.
  static bool needsEstimateConsent(LogisticsQuote q) =>
      q.isEstimate && q.pricingMode != 'lane_fixed';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(acceptEstimatedDistanceProvider);
    final supplyMsg = quote.supplyMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (quote.noVehicleNearby && (supplyMsg ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  supplyMsg!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB45309), height: 1.4),
                ),
              ),
            ],
          ),
        ],
        if (needsEstimateConsent(quote))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: consent,
            onChanged: (v) =>
                ref.read(acceptEstimatedDistanceProvider.notifier).state = v ?? false,
            title: Text(
              (quote.estimateNotice ?? '').isNotEmpty
                  ? quote.estimateNotice!
                  : 'This fare uses an estimated distance. I accept the estimate.',
              style: _hintStyle,
            ),
          ),
      ],
    );
  }
}

// ── Policies + FAQs ─────────────────────────────────────────────────────────

class GtPoliciesSection extends ConsumerWidget {
  const GtPoliciesSection({
    super.key,
    required this.serviceCategory,
    required this.faqCategory,
    this.city,
  });

  /// goods_transport_truck | goods_transport_two_wheeler | packers_movers
  final String serviceCategory;

  /// truck | two_wheeler | packers_movers (GTFaq.category)
  final String faqCategory;
  final String? city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policies = ref.watch(gtPoliciesProvider(serviceCategory));
    final faqs = ref.watch(gtFaqsProvider((category: faqCategory, city: city?.toLowerCase())));

    final terms = policies.valueOrNull?.terms ?? const <String>[];
    final faqList = faqs.valueOrNull ?? const <GtFaq>[];
    if (terms.isEmpty && faqList.isEmpty) return const SizedBox.shrink();

    return _card(
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          children: [
            if (terms.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Cancellation & booking terms', style: _titleStyle),
                children: [
                  for (final t in terms)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 5, right: 8),
                            child: Icon(Icons.circle, size: 5, color: AppColors.textSecondary),
                          ),
                          Expanded(child: Text(t, style: _hintStyle)),
                        ],
                      ),
                    ),
                ],
              ),
            if (faqList.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('FAQs', style: _titleStyle),
                children: [
                  for (final f in faqList)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(
                        f.question,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      expandedAlignment: Alignment.centerLeft,
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(f.answer, style: _hintStyle)],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── Packers & Movers inventory (same side-by-side layout as cargo) ──────────

/// Rooms / categories on the left, the items of the chosen room on the right,
/// in one frame. Reads and writes [pmSelectedQuantitiesProvider] directly, so
/// the quote and booking code that already uses it is unchanged.
class PmInventoryPicker extends ConsumerStatefulWidget {
  const PmInventoryPicker({super.key, required this.categories});

  final List<PmGoodsCategory> categories;

  @override
  ConsumerState<PmInventoryPicker> createState() => _PmInventoryPickerState();
}

class _PmInventoryPickerState extends ConsumerState<PmInventoryPicker> {
  int? _selectedId;

  void _setQty(Map<int, int> current, int itemId, int qty) {
    final next = Map<int, int>.from(current);
    if (qty <= 0) {
      next.remove(itemId);
    } else {
      next[itemId] = qty;
    }
    ref.read(pmSelectedQuantitiesProvider.notifier).state = next;
  }

  @override
  Widget build(BuildContext context) {
    final qty = ref.watch(pmSelectedQuantitiesProvider);
    final cats = widget.categories;
    if (cats.isEmpty) return const SizedBox.shrink();

    PmGoodsCategory selected = cats.first;
    for (final c in cats) {
      if (c.id == _selectedId) selected = c;
    }
    final total = qty.values.fold<int>(0, (s, q) => s + q);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(flex: 5, child: _fieldLabel('Rooms & categories')),
            const SizedBox(width: 10),
            Expanded(flex: 6, child: _fieldLabel('Select items')),
          ],
        ),
        Container(
          height: 380,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _kPanelBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: cats.length,
                  itemBuilder: (context, i) {
                    final c = cats[i];
                    final isSel = c.id == selected.id;
                    final count = c.items.fold<int>(0, (s, it) => s + (qty[it.id] ?? 0));
                    return InkWell(
                      onTap: () => setState(() => _selectedId = c.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppColors.serviceBlue.withValues(alpha: 0.10)
                              : Colors.transparent,
                          border: Border(
                            left: BorderSide(
                              color: isSel ? AppColors.serviceBlue : Colors.transparent,
                              width: 3,
                            ),
                            bottom: const BorderSide(color: AppColors.border, width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.name,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.25,
                                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                  color: isSel ? AppColors.serviceBlue : AppColors.navy,
                                ),
                              ),
                            ),
                            if (count > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.serviceBlue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1, thickness: 0.8),
              Expanded(
                flex: 6,
                child: Container(
                  color: Colors.white,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: selected.items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, thickness: 0.6),
                    itemBuilder: (context, i) {
                      final it = selected.items[i];
                      return _PmRow(
                        item: it,
                        qty: qty[it.id] ?? 0,
                        onQty: (q) => _setQty(qty, it.id, q),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (total > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 15, color: AppColors.serviceBlue),
              const SizedBox(width: 6),
              Text(
                '$total item${total == 1 ? '' : 's'} selected',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.serviceBlue,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PmRow extends StatelessWidget {
  const _PmRow({required this.item, required this.qty, required this.onQty});

  final PmGoodsItem item;
  final int qty;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final active = qty > 0;
    return Opacity(
      opacity: item.configured ? 1.0 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            if (!item.configured)
              const Text(
                'Contact us to quote',
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textHint,
                ),
              )
            else if (!active)
              GestureDetector(
                onTap: () => onQty(1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.serviceBlue, width: 1),
                  ),
                  child: const Text(
                    'ADD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.serviceBlue,
                    ),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.serviceBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepBtn(icon: Icons.remove_rounded, onTap: () => onQty(qty - 1)),
                    SizedBox(
                      width: 26,
                      child: Text(
                        '$qty',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    _StepBtn(icon: Icons.add_rounded, onTap: () => onQty(qty + 1)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}