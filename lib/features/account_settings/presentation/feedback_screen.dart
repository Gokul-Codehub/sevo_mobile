import '../../../core/l10n/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/safe_back.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/app_toast.dart';
import '../data/account_settings_repository.dart';

/// Profile -> Send feedback. Also the "Report a problem with this booking" shortcut: pass the booking
/// reference and it is pre-filled and the category set to "booking".
class AppFeedbackScreen extends ConsumerStatefulWidget {
  const AppFeedbackScreen({super.key, this.bookingRef});
  final String? bookingRef;

  @override
  ConsumerState<AppFeedbackScreen> createState() => _AppFeedbackScreenState();
}

class _AppFeedbackScreenState extends ConsumerState<AppFeedbackScreen> {
  static const _categories = {
    'problem': 'Report a problem',
    'suggestion': 'Suggestion',
    'booking': 'Problem with a booking',
    'other': 'Other',
  };

  final _message = TextEditingController();
  late String _category = (widget.bookingRef ?? '').isNotEmpty ? 'booking' : 'problem';
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _valid => _message.text.trim().length >= 5;

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await ref.read(accountSettingsRepositoryProvider).sendFeedback(
          category: _category,
          message: _message.text,
          bookingRef: widget.bookingRef,
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      AppToast.show(context, context.l10n.feedbackThanks);
      context.goBack();
    } else {
      AppToast.show(context, 'Could not send. Check your connection and try again.', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: Text(context.l10n.feedbackTitle, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
        leading: BackButton(onPressed: context.goBack),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Tell us what happened or what we can do better. Your app version and phone model are attached to help us fix it.',
              style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in _categories.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _category == e.key,
                  selectedColor: AppColors.navy,
                  labelStyle: TextStyle(color: _category == e.key ? Colors.white : AppColors.navy, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _category = e.key),
                ),
            ],
          ),
          if ((widget.bookingRef ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('About booking ${widget.bookingRef}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _message,
            maxLines: 6,
            maxLength: 1000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.l10n.feedbackHint,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _valid && !_sending ? _send : null,
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size.fromHeight(50)),
            child: Text(_sending ? context.l10n.feedbackSending : context.l10n.feedbackSend),
          ),
        ],
      ),
    );
  }
}
