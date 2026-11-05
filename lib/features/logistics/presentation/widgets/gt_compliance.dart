import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/theme/app_colors.dart';

// Declared value, high-value receiver rules, GSTIN and e-way bill helpers for the Goods & Transport booking flow.
// Mirrors the web booking pages (DeclaredValueField / EwayBillField / GstinField):
//   >= Rs 25,000  high-value consignment: a named receiver (name, phone) and their relationship to you are recorded
//   >= Rs 50,000  a 12-digit e-way bill number is required
//   GSTIN         optional, 15 characters, validated, never changes the fare
// The server re-validates every rule with its own (admin-configured) thresholds; these are the up-front hints.

const double kHighValueThreshold = 25000;
const double kEwayBillThreshold = 50000;

/// (value sent to the server, label shown) — same options and values as the web.
const List<(String, String)> kGtRelationshipOptions = [
  ('Self', 'Self (my own branch / store / home)'),
  ('Customer / Buyer', 'Customer / Buyer'),
  ('Store / Warehouse', 'Store / Warehouse / Depot'),
  ('Supplier / Vendor', 'Supplier / Business Partner'),
  ('Family & Friend', 'Friend / Family Member'),
  ('Receiver', 'Other authorized receiver'),
];

final RegExp _gstinRe = RegExp(r'^(0[1-9]|[1-2][0-9]|3[0-8]|97|99)[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

/// Upper-case, no spaces, at most 15 characters.
String normalizeGstin(String v) {
  final s = v.replaceAll(RegExp(r'\s'), '').toUpperCase();
  return s.length > 15 ? s.substring(0, 15) : s;
}

bool isValidGstin(String v) => _gstinRe.hasMatch(normalizeGstin(v));

/// Digits only, no spaces.
String ewayDigits(String v) => v.replaceAll(RegExp(r'\D'), '');

/// Error text for the e-way bill field, or null when fine. [raw] may contain spaces.
String? ewayBillError(String raw, {required bool required}) {
  final s = raw.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) {
    return required ? 'E-way bill number is required for goods worth ₹50,000 or more.' : null;
  }
  if (!RegExp(r'^\d+$').hasMatch(s)) return 'E-way bill number must contain only digits.';
  if (s.length != 12) return 'E-way bill number must be 12 digits (${s.length}/12 entered).';
  return null;
}

/// 1234567 -> 12,34,567 (Indian digit grouping).
String formatInr(num v) {
  final s = v.round().toString();
  if (s.length <= 3) return s;
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[s.substring(s.length - 3)];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return parts.join(',');
}

/// Shows an e-way bill as 1234 5678 9012 while typing; the stored value is the bare digits.
class EwayBillFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = ewayDigits(newValue.text);
    if (d.length > 12) d = d.substring(0, 12);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(d[i]);
    }
    final out = b.toString();
    return TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
  }
}

enum GtNoticeTone { info, warning, success }

/// A coloured guidance box: icon, bold title, plain-language body.
class GtNoticeCard extends StatelessWidget {
  const GtNoticeCard({super.key, required this.tone, required this.title, required this.body});

  final GtNoticeTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color bd, IconData icon) = switch (tone) {
      GtNoticeTone.warning => (const Color(0xFFB45309), const Color(0xFFFFFBEB), const Color(0xFFFCD34D), Icons.description_outlined),
      GtNoticeTone.success => (const Color(0xFF15803D), const Color(0xFFF0FDF4), const Color(0xFFBBF7D0), Icons.check_circle_outline),
      GtNoticeTone.info => (const Color(0xFF1D4ED8), const Color(0xFFEFF6FF), const Color(0xFFBFDBFE), Icons.info_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: bd)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(fontSize: 11.5, height: 1.4, color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _dec(String hint, {String? prefix}) => InputDecoration(
      hintText: hint,
      prefixText: prefix,
      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
    );

/// The typed declared-value box with quick amounts and a live amount line.
class GtDeclaredValueField extends StatelessWidget {
  const GtDeclaredValueField({super.key, required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  static const _quick = <int>[10000, 25000, 50000, 100000];

  @override
  Widget build(BuildContext context) {
    final v = double.tryParse(controller.text.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          onChanged: (_) => onChanged(),
          decoration: _dec('e.g. 15000', prefix: '₹ '),
        ),
        if (v > 0) ...[
          const SizedBox(height: 4),
          Text('₹${formatInr(v)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final q in _quick)
              ChoiceChip(
                label: Text('₹${formatInr(q)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                selected: v == q,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  controller.text = '$q';
                  onChanged();
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Badge + plain-language notices for the entered value (used for typed and for goods-derived values).
class GtValueGuidance extends StatelessWidget {
  const GtValueGuidance({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();
    final eway = value >= kEwayBillThreshold;
    final high = value >= kHighValueThreshold;
    final (String label, Color c) = eway
        ? ('E-way bill needed (₹50,000+)', const Color(0xFFB45309))
        : high
            ? ('High value (₹25,000+)', const Color(0xFF1D4ED8))
            : ('Standard', const Color(0xFF15803D));
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
          ),
          if (eway) ...[
            const SizedBox(height: 8),
            const GtNoticeCard(
              tone: GtNoticeTone.warning,
              title: 'GST rule: e-way bill needed',
              body: 'Goods worth ₹50,000 or more must travel with an active 12-digit e-way bill. '
                  'Enter its number in the "GST & e-way bill" section below to avoid delays at transit checks.',
            ),
          ],
          if (high) ...[
            const SizedBox(height: 8),
            const GtNoticeCard(
              tone: GtNoticeTone.info,
              title: 'High-value consignment',
              body: 'For safety, the driver hands over only to a named receiver. Add the receiver\'s name and phone in '
                  'the Drop-off section (we use yours if you leave them blank) and tell us who the receiver is to you.',
            ),
          ],
        ],
      ),
    );
  }
}

/// "Receiver relationship to sender" — required for high-value goods; chips instead of a free-text box.
class GtRelationshipPicker extends StatelessWidget {
  const GtRelationshipPicker({super.key, required this.value, required this.onChanged, this.focusNode});

  final String value;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Who is the receiver to you? *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final o in kGtRelationshipOptions)
                  ChoiceChip(
                    label: Text(o.$2, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    selected: value == o.$1,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onChanged(o.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
