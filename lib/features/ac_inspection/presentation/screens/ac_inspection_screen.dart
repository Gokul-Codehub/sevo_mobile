import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/utils/input_validators.dart';
import '../../../addresses/domain/address_models.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../../logistics/presentation/widgets/slot_picker_widget.dart';
import '../../data/ac_inspection_repository.dart';
import '../../domain/ac_inspection_models.dart';

/// "AC Inspection & Diagnostic Visit" - the same inspection booking the web
/// offers inside the Air Conditioner category: a technician visits, inspects the
/// AC and sends an itemised quotation before any repair work (approved later
/// from the booking's quotation card).
class AcInspectionScreen extends ConsumerStatefulWidget {
  const AcInspectionScreen({super.key});

  @override
  ConsumerState<AcInspectionScreen> createState() => _AcInspectionScreenState();
}

class _AcInspectionScreenState extends ConsumerState<AcInspectionScreen> {
  /// The service the backend resolves for inspection slots
  /// (EstimationService uses resolve_service("ac-service-cleaning", "ac-appliance")).
  static const _slotService = 'ac-service-cleaning';

  String _brand = 'Daikin';
  String _type = 'SPLIT';
  String _capacity = '1.5_TON';
  int _qty = 1;
  final _notes = TextEditingController();
  Uint8List? _photo;
  String? _photoName;
  bool _submitting = false;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _container.read(selectedBookingServiceIdProvider.notifier).state = _slotService;
      _container.read(selectedTimeSlotProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    Future.microtask(() {
      _container.read(selectedBookingServiceIdProvider.notifier).state = null;
      _container.read(selectedTimeSlotProvider.notifier).state = null;
    });
    super.dispose();
  }

  Future<void> _pick(ImageSource s) async {
    try {
      final x = await ImagePicker().pickImage(source: s, maxWidth: 1600, imageQuality: 85);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (b.length > 5 * 1024 * 1024) {
        if (mounted) AppToast.show(context, 'Photo must be under 5 MB.', type: AppToastType.error);
        return;
      }
      if (mounted) setState(() { _photo = b; _photoName = x.name; });
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not open the photo.', type: AppToastType.error);
    }
  }

  Future<void> _submit(AcInspectionConfig config) async {
    final user = ref.read(currentUserProvider);
    final address = ref.read(selectedAddressProvider);
    final slot = ref.read(selectedTimeSlotProvider);
    if (user == null) {
      AppToast.show(context, 'Please sign in to book.', type: AppToastType.error);
      return;
    }
    if (address == null) {
      AppToast.show(context, 'Please select a service address.', type: AppToastType.error);
      return;
    }
    if (slot == null) {
      AppToast.show(context, 'Please choose a date and time slot.', type: AppToastType.error);
      return;
    }
    final notes = _notes.text.trim();
    final details = AcInspectionDetails(
      brand: _brand,
      acType: _type,
      capacity: _capacity,
      quantity: _qty,
      // The backend requires a symptom; the web fills this default too.
      symptom: notes.isEmpty ? 'AC Inspection & Diagnostic requested' : notes,
      notes: notes.isEmpty ? null : notes,
    );
    final phone = user.hasMobileNumber ? user.phone : '';
    if (phone.isEmpty) {
      AppToast.show(context, 'Please add your mobile number in Profile first.', type: AppToastType.error);
      return;
    }
    setState(() => _submitting = true);
    final date = DateFormat('yyyy-MM-dd').format(ref.read(selectedBookingDateProvider));
    final result = await ref.read(acInspectionRepositoryProvider).book(
          config: config,
          details: details,
          address: address,
          date: date,
          timeSlot: slot.label,
          customerName: InputValidators.bookingName(user.name) ?? 'Customer',
          phone: phone,
          email: user.email,
          photoBytes: _photo,
          photoFileName: _photoName,
          idempotencyKey: 'acinsp-${user.id}-${DateTime.now().millisecondsSinceEpoch}',
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Success(:final data):
        AppToast.bookingSuccessful(context);
        context.go('/bookings/success/${data.id}', extra: data);
      case Failure(:final error):
        AppToast.show(context, error.message, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(acInspectionConfigProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(title: const Text('AC Inspection')),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load the inspection details.'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => ref.invalidate(acInspectionConfigProvider), child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (config) {
          if (!config.isActive) {
            return const Center(child: Text('AC inspection is not available right now.'));
          }
          return _body(config);
        },
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6EAF2)),
        ),
        child: child,
      );

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
      );

  Widget _bullets(List<String> items, IconData icon, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary))),
                ],
              ),
            ),
        ],
      );

  Widget _chips<T>(List<(String, T)> opts, T value, ValueChanged<T> on) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opts)
            ChoiceChip(
              label: Text(o.$1),
              selected: o.$2 == value,
              onSelected: (_) => on(o.$2),
              selectedColor: const Color(0xFFE3EAF1),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: o.$2 == value ? const Color(0xFF0B2337) : AppColors.textPrimary,
              ),
            ),
        ],
      );

  Widget _body(AcInspectionConfig config) {
    final addresses = ref.watch(addressListProvider).valueOrNull ?? const <Address>[];
    final selected = ref.watch(selectedAddressProvider);
    final list = <Address>[...addresses];
    if (selected != null && !list.any((a) => a.id == selected.id)) list.insert(0, selected);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.ac_unit_rounded, color: const Color(0xFF0B2337)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(config.title,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: AppColors.navy)),
                  ),
                ],
              ),
              if (config.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(config.subtitle, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in config.badges)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0xFFE3EAF1), borderRadius: BorderRadius.circular(20)),
                      child: Text(b, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF0B2337))),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (config.includes.isNotEmpty)
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h("What's included"),
            _bullets(config.includes, Icons.check_circle_rounded, AppColors.success),
          ])),
        if (config.ready.isNotEmpty)
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h('What you need to keep ready'),
            _bullets(config.ready, Icons.info_outline_rounded, const Color(0xFF0B2337)),
          ])),
        if (config.rateCard.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _h('Spare parts & repair rate card'),
                const Text('Quoted to you after the inspection - nothing is done without your approval.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
                const SizedBox(height: 6),
                for (final c in config.rateCard)
                  // Material between the decorated card and the tile: ListTile
                  // asserts (debug red screen) without it.
                  Material(
                    type: MaterialType.transparency,
                    child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text('${c.name} (${c.items.length})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
                      children: [
                        for (final i in c.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(i.name, style: const TextStyle(fontSize: 12.5))),
                                Text(i.price, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )),
              ],
            ),
          ),

        // ── AC details ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h('Your AC'),
              DropdownButtonFormField<String>(
                initialValue: _brand,
                decoration: const InputDecoration(labelText: 'Brand', border: OutlineInputBorder()),
                items: [for (final b in acBrands) DropdownMenuItem(value: b, child: Text(b))],
                onChanged: (v) => setState(() => _brand = v ?? _brand),
              ),
              const SizedBox(height: 14),
              const Text('Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              _chips<String>(acTypes, _type, (v) => setState(() => _type = v)),
              const SizedBox(height: 14),
              const Text('Capacity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              _chips<String>(acCapacities, _capacity, (v) => setState(() => _capacity = v)),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text('How many ACs?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  ),
                  IconButton(
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text('$_qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  IconButton(
                    onPressed: _qty < 50 ? () => setState(() => _qty++) : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Describe the issue (optional)',
                  hintText: 'e.g. AC not cooling, strange noise, water leaking from indoor unit',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_photo == null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('Take photo')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('Gallery')),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_photo!, width: 64, height: 64, fit: BoxFit.cover)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Photo attached', style: TextStyle(fontWeight: FontWeight.w700))),
                    IconButton(onPressed: () => setState(() { _photo = null; _photoName = null; }), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
            ],
          ),
        ),

        // ── Date & time ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_h('Date & time'), const SlotPickerWidget()],
          ),
        ),

        // ── Address ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _h('Service address')),
                  TextButton(onPressed: () => context.push('/addresses/add'), child: const Text('Add new')),
                ],
              ),
              for (final a in list)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => ref.read(selectedAddressProvider.notifier).state = a,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected?.id == a.id ? const Color(0xFF0B2337) : const Color(0xFFE2E8F0),
                        width: selected?.id == a.id ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(a.formattedAddress,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.35)),
                        ),
                        Icon(
                          selected?.id == a.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: selected?.id == a.id ? const Color(0xFF0B2337) : AppColors.textHint,
                        ),
                      ],
                    ),
                  ),
                ),
              if (list.isEmpty) const Text('No saved address yet - add one to continue.', style: TextStyle(color: AppColors.textHint)),
            ],
          ),
        ),

        // ── Fee ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h('Fee'),
              Row(
                children: [
                  const Expanded(child: Text('Inspection & diagnosis fee')),
                  Text('Rs ${config.fee}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Pay via cash or UPI after the technician inspects. Adjustable against the repair if you go ahead.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
            ],
          ),
        ),

        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0B2337),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _submitting ? null : () => _submit(config),
          child: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Confirm booking - Rs ${config.fee}', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
