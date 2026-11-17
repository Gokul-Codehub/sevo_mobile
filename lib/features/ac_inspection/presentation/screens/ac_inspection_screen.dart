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
import 'package:calservices_customer/shared/widgets/motion.dart';
import '../../../../shared/widgets/state_widgets.dart';
import '../../../addresses/domain/address_models.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../../logistics/data/logistics_repository.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../../logistics/presentation/widgets/slot_picker_widget.dart';
import '../../data/ac_inspection_repository.dart';
import '../../domain/ac_inspection_models.dart';

/// "AC Inspection & Diagnostic Visit" - the same inspection booking the web
/// offers inside the Air Conditioner category: a technician visits, inspects the
/// AC and sends an itemised quotation before any repair work (approved later
/// from the booking's quotation card).
class AcInspectionScreen extends ConsumerStatefulWidget {
  const AcInspectionScreen({super.key, this.category = InspectionCategory.ac});

  final InspectionCategory category;

  @override
  ConsumerState<AcInspectionScreen> createState() => _AcInspectionScreenState();
}

class _AcInspectionScreenState extends ConsumerState<AcInspectionScreen> {
  /// The service the backend resolves for inspection slots
  /// (EstimationService uses resolve_service("ac-service-cleaning", "ac-appliance")).

  static const _border = Color(0xFFE6EAF2);
  static const _softNavy = Color(0xFFE8EEF4);

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
      _container.read(selectedBookingServiceIdProvider.notifier).state = widget.category.slotService;
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
    // Is this address inside a service zone? Tell the customer now, not after they have filled in the whole form.
    // If the check can't be made it never blocks: the server still enforces the zone when the booking is created.
    setState(() => _submitting = true);
    final zone = await ref.read(logisticsRepositoryProvider).checkServiceability(
          postalCode: address.postalCode,
          latitude: address.latitude,
          longitude: address.longitude,
          serviceSlug: 'ac-service-cleaning',
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (zone case Success(:final data) when !data.isUnknown && !data.isServiceable) {
      AppToast.show(
        context,
        data.message.isNotEmpty ? data.message : 'Sorry, we do not serve this address yet. Please choose another one.',
        type: AppToastType.error,
      );
      return;
    }
    final notes = _notes.text.trim();
    final details = AcInspectionDetails(
      brand: _brand,
      acType: _type,
      capacity: _capacity,
      quantity: _qty,
      // The backend requires a symptom; the web fills this default too.
      symptom: notes.isEmpty ? '${widget.category.label} Inspection & Diagnostic requested' : notes,
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
          category: widget.category,
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
    final configAsync = ref.watch(acInspectionConfigProvider(widget.category));
    final config = configAsync.valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.category.label} Inspection'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: configAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState.from(
          e,
          onRetry: () => ref.invalidate(acInspectionConfigProvider(widget.category)),
        ),
        data: (config) {
          if (!config.isActive) {
            return EmptyState(
              icon: Icons.ac_unit_rounded,
              title: '${widget.category.label} inspection is not available right now',
              body: 'Please check back soon.',
            );
          }
          return FadeSlideIn(child: _body(config));
        },
      ),
      // Confirm stays in reach however long the form is.
      bottomNavigationBar: (config != null && config.isActive)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(top: BorderSide(color: _border)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: PressScale(
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.45),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _submitting
                          ? null
                          : () {
                              AppHaptics.light();
                              _submit(configAsync.requireValue);
                            },
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : Text(
                              'Confirm booking · ₹${configAsync.requireValue.fee}',
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) => FadeSlideIn(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: child,
        ),
      );

  Widget _sectionTitle(String title, {IconData? icon, Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _softNavy,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: AppColors.navy),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.1,
          ),
        ),
      );

  Widget _bullets(List<String> items, IconData icon, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s,
                      style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _chips<T>(List<(String, T)> opts, T value, ValueChanged<T> onChanged) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opts)
            PressScale(
              child: GestureDetector(
                onTap: () {
                  AppHaptics.selection();
                  onChanged(o.$2);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: o.$2 == value ? AppColors.navy : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: o.$2 == value ? AppColors.navy : const Color(0xFFD7DEE8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (o.$2 == value) ...[
                        const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        o.$1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: o.$2 == value ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _qtyStepper() => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _qtyBtn(
              icon: Icons.remove_rounded,
              enabled: _qty > 1,
              onTap: () => setState(() => _qty--),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '$_qty',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy),
              ),
            ),
            _qtyBtn(
              icon: Icons.add_rounded,
              enabled: _qty < 50,
              onTap: () => setState(() => _qty++),
            ),
          ],
        ),
      );

  Widget _qtyBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () {
                  AppHaptics.selection();
                  onTap();
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? AppColors.navy : AppColors.textMuted,
            ),
          ),
        ),
      );

  InputDecoration _inputDecoration({String? label, String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceVariant.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.4),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
      );

  Widget _body(AcInspectionConfig config) {
    final addresses = ref.watch(addressListProvider).valueOrNull ?? const <Address>[];
    final selected = ref.watch(selectedAddressProvider);
    final list = <Address>[...addresses];
    if (selected != null && !list.any((a) => a.id == selected.id)) list.insert(0, selected);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // ── Hero ──
        _card(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.accent, AppColors.navy],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.ac_unit_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.title,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                            height: 1.25,
                          ),
                        ),
                        if (config.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            config.subtitle,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _softNavy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Fee',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                        ),
                        Text(
                          '₹${config.fee}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.navy),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (config.badges.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in config.badges)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _border),
                        ),
                        child: Text(
                          b,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),

        if (config.includes.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle("What's included", icon: Icons.check_circle_outline_rounded),
                _bullets(config.includes, Icons.check_circle_rounded, AppColors.success),
              ],
            ),
          ),

        if (config.ready.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Keep ready', icon: Icons.checklist_rounded),
                _bullets(config.ready, Icons.info_outline_rounded, AppColors.navy),
              ],
            ),
          ),

        if (config.rateCard.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Spare parts rate card', icon: Icons.receipt_long_rounded),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.infoLight.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Quoted after inspection — nothing is done without your approval.',
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.textSecondary),
                  ),
                ),
                for (final c in config.rateCard)
                  Material(
                    type: MaterialType.transparency,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(
                          '${c.name} (${c.items.length})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
                        ),
                        children: [
                          for (final i in c.items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(i.name, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                                  ),
                                  Text(
                                    i.price,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // ── AC details (AC only) / issue details ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(widget.category.isAc ? 'Your AC' : 'Your issue', icon: Icons.devices_other_rounded),
              if (widget.category.isAc) ...[
              DropdownButtonFormField<String>(
                initialValue: _brand,
                decoration: _inputDecoration(label: 'Brand'),
                borderRadius: BorderRadius.circular(12),
                items: [for (final b in acBrands) DropdownMenuItem(value: b, child: Text(b))],
                onChanged: (v) => setState(() => _brand = v ?? _brand),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Type'),
              _chips<String>(acTypes, _type, (v) => setState(() => _type = v)),
              const SizedBox(height: 16),
              _fieldLabel('Capacity'),
              _chips<String>(acCapacities, _capacity, (v) => setState(() => _capacity = v)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'How many ACs?',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy),
                      ),
                    ),
                    _qtyStepper(),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ],
              TextField(
                controller: _notes,
                maxLines: 3,
                style: const TextStyle(fontSize: 13.5, height: 1.4),
                decoration: _inputDecoration(
                  label: 'Describe the issue (optional)',
                  hint: widget.category.isAc
                      ? 'e.g. not cooling, strange noise, water leaking'
                      : widget.category == InspectionCategory.plumbing
                          ? 'e.g. leaking tap, blocked drain, low water pressure'
                          : 'e.g. power tripping, switch sparking, fan not working',
                ),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Photo (optional)'),
              if (_photo == null)
                Row(
                  children: [
                    Expanded(
                      child: _mediaButton(
                        icon: Icons.photo_camera_outlined,
                        label: 'Take photo',
                        onTap: () => _pick(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _mediaButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: () => _pick(ImageSource.gallery),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.successLight.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_photo!, width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Photo attached', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
                            SizedBox(height: 2),
                            Text('Tap × to remove', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove photo',
                        onPressed: () => setState(() {
                          _photo = null;
                          _photoName = null;
                        }),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // ── Date & time ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Date & time', icon: Icons.schedule_rounded),
              const SlotPickerWidget(),
            ],
          ),
        ),

        // ── Address ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                'Service address',
                icon: Icons.location_on_outlined,
                trailing: TextButton(
                  onPressed: () => context.push('/addresses/add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Add new', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              if (list.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'No saved address yet — add one to continue.',
                    style: TextStyle(color: AppColors.textHint, fontSize: 12.5),
                  ),
                )
              else
                for (final a in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          AppHaptics.selection();
                          ref.read(selectedAddressProvider.notifier).state = a;
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected?.id == a.id ? _softNavy : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected?.id == a.id ? AppColors.navy : AppColors.border,
                              width: selected?.id == a.id ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected?.id == a.id
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: selected?.id == a.id ? AppColors.navy : AppColors.textHint,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  a.formattedAddress,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),

        // ── Fee ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Fee summary', icon: Icons.payments_outlined),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Inspection & diagnosis',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Pay after the visit · adjustable against repair',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${config.fee}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mediaButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: Color(0xFFD0D7E2)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}
