import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/errors/error_manager.dart';
import '../../../../core/navigation/safe_back.dart';
import '../../../../core/refresh/refresh_runner.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/utils/date_utils.dart';
import '../../../../shared/widgets/state_widgets.dart';
import 'package:calservices_customer/shared/widgets/motion.dart';
import '../../../feedback/presentation/widgets/review_photo_picker.dart';
import '../../data/support_requests_repository.dart';

AppBar _bar(BuildContext context, String title, {List<Widget>? actions}) => AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 18)),
      leading: BackButton(onPressed: context.goBack),
      backgroundColor: Colors.white,
      foregroundColor: AppColors.navy,
      elevation: 0,
      actions: actions,
    );

Color _stageColor(TicketStage s) => switch (s) {
      TicketStage.open => AppColors.swatchB26A00,
      TicketStage.inProgress => const Color(0xFF1E5AA8),
      TicketStage.waitingOnYou => AppColors.error,
      TicketStage.resolved => AppColors.swatch1B7F4B,
      TicketStage.closed => Colors.black45,
    };

String _stageText(SupportRequest r) => switch (r.stage) {
      TicketStage.open => 'Received',
      TicketStage.inProgress => 'Being looked into',
      TicketStage.waitingOnYou => 'We need your reply',
      TicketStage.resolved => 'Resolved',
      TicketStage.closed => 'Closed',
    };

// ───────────────────────────── My support requests ─────────────────────────────

class SupportRequestsScreen extends ConsumerWidget {
  const SupportRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(supportRequestsProvider);
    return Scaffold(
      backgroundColor: AppColors.swatchF6F8FA,
      appBar: _bar(context, 'My support requests'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/support/new'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New request'),
      ),
      body: requests.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(supportRequestsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.support_agent_rounded,
              title: 'No support requests yet',
              body: 'If something went wrong with a booking, a payment or a delivery, tell us here and follow the reply.',
              actionLabel: 'Raise a request',
              onAction: () => context.push('/support/new'),
            );
          }
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(supportRequestsProvider);
              return RefreshRunner.run(context, [() => ref.read(supportRequestsProvider.future)]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                for (var i = 0; i < list.length; i++)
                  FadeSlideIn(index: i, child: _RequestCard(request: list[i])),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});
  final SupportRequest request;

  @override
  Widget build(BuildContext context) {
    final color = _stageColor(request.stage);
    return PressScale(
      scale: 0.985,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.swatchE3E8EE)),
        child: ListTile(
          onTap: () => context.push('/support/tickets/${request.id}'),
          title: Row(children: [
            Expanded(child: Text(request.categoryLabel, style: const TextStyle(fontWeight: FontWeight.w800))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(_stageText(request), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [request.number, if (request.bookingRef != null && request.bookingRef!.isNotEmpty) 'Booking ${request.bookingRef}', if (request.createdAt != null) formatDmy(request.createdAt!)].join(' - '),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── New request ─────────────────────────────

/// `/support/new?topic=payment&booking=<id>`: the topic and booking can be pre-filled by the screen the customer came from.
class NewSupportRequestScreen extends ConsumerStatefulWidget {
  const NewSupportRequestScreen({super.key, this.topic, this.bookingId, this.bookingRef});
  final String? topic;
  final String? bookingId;
  final String? bookingRef;

  @override
  ConsumerState<NewSupportRequestScreen> createState() => _NewSupportRequestScreenState();
}

class _NewSupportRequestScreenState extends ConsumerState<NewSupportRequestScreen> {
  late String _topic = kSupportTopics.containsKey(widget.topic) ? widget.topic! : ((widget.bookingId ?? '').isNotEmpty ? 'booking' : 'other');
  final _text = TextEditingController();
  List<XFile> _photos = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().length >= 10;

  Future<void> _submit() async {
    AppHaptics.success();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(supportRequestsRepositoryProvider).create(
          category: kSupportTopics[_topic]!.category,
          description: _text.text,
          bookingId: widget.bookingId,
          photos: _photos,
        );
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        ref.invalidate(supportRequestsProvider);
        AppToast.show(context, 'Request ${data.number} received. We will reply here.');
        context.pushReplacement('/support/tickets/${data.id}');
      case Failure(:final error):
        setState(() {
          _busy = false;
          _error = error is ValidationError && error.message.isNotEmpty ? error.message : ErrorManager.present(error).body;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topic = kSupportTopics[_topic]!;
    final chars = _text.text.trim().length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _bar(context, 'New support request'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          FadeSlideIn(
            child: _SupportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SupportSectionTitle(
                    icon: Icons.help_outline_rounded,
                    title: 'What is this about?',
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in kSupportTopics.entries)
                        _TopicChip(
                          label: e.value.label,
                          selected: _topic == e.key,
                          onTap: () {
                            AppHaptics.selection();
                            setState(() => _topic = e.key);
                          },
                        ),
                    ],
                  ),
                  if ((widget.bookingRef ?? widget.bookingId ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE6EAF2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded, size: 18, color: AppColors.navy),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'About booking ${widget.bookingRef ?? widget.bookingId}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          FadeSlideIn(
            index: 1,
            child: _SupportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SupportSectionTitle(
                    icon: Icons.edit_note_rounded,
                    title: 'Describe the issue',
                  ),
                  TextField(
                    controller: _text,
                    maxLines: 6,
                    maxLength: 2000,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    decoration: InputDecoration(
                      hintText: topic.hint,
                      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13.5),
                      filled: true,
                      fillColor: AppColors.surfaceVariant.withValues(alpha: 0.55),
                      contentPadding: const EdgeInsets.all(14),
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.navy, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chars >= 10
                              ? 'Looks good — you can submit.'
                              : 'Tell us what happened (at least 10 characters).',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: chars >= 10 ? AppColors.success : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '$chars/2000',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          FadeSlideIn(
            index: 2,
            child: _SupportCard(
              child: ReviewPhotoPicker(
                photos: _photos,
                onChanged: (p) => setState(() => _photos = p),
                title: 'Add photos (optional)',
                subtitle: 'Damage, a wrong bill, anything that helps. Up to 3 photos.',
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: Color(0xFFE6EAF2))),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: PressScale(
            child: FilledButton(
              onPressed: _valid && !_busy ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                disabledForegroundColor: AppColors.swatch6B7280,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text(
                      'Submit request',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EAF2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SupportSectionTitle extends StatelessWidget {
  const _SupportSectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEF4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: AppColors.navy),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navy),
          ),
        ],
      ),
    );
  }
}

/// Topic pill: selected = outer grey ring + shadow (no checkmark / no navy fill).
class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 14 : 12,
            vertical: selected ? 10 : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? AppColors.textHint : const Color(0xFFD7DEE8),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.22),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: selected ? 13 : 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── One request: conversation ─────────────────────────────

class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Result<Object?>> Function() action, String done) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Success():
        ref.invalidate(supportRequestProvider(widget.id));
        ref.invalidate(supportRequestsProvider);
        if (done.isNotEmpty) AppToast.show(context, done);
      case Failure(:final error):
        AppToast.show(context, error is ValidationError && error.message.isNotEmpty ? error.message : ErrorManager.present(error).body,
            type: AppToastType.error);
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(supportRequestsRepositoryProvider);
    await _run(() async {
      final r = await repo.reply(widget.id, text);
      if (r is Success) _reply.clear();
      return r;
    }, '');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supportRequestProvider(widget.id));
    return Scaffold(
      backgroundColor: AppColors.swatchF6F8FA,
      appBar: _bar(context, 'Support request'),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(supportRequestProvider(widget.id))),
        data: (r) => Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () {
                ref.invalidate(supportRequestProvider(widget.id));
                return RefreshRunner.run(context, [() => ref.read(supportRequestProvider(widget.id).future)]);
              },
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _Header(request: r),
                const SizedBox(height: 12),
                if (r.canReopen || r.canEscalate)
                  Wrap(spacing: 8, children: [
                    if (r.canReopen)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _run(() => ref.read(supportRequestsRepositoryProvider).reopen(widget.id), 'Request reopened.'),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Not fixed - reopen'),
                      ),
                    if (r.canEscalate)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _run(() => ref.read(supportRequestsRepositoryProvider).escalate(widget.id), 'We have escalated your request.'),
                        icon: const Icon(Icons.priority_high_rounded, size: 18),
                        label: const Text('Escalate'),
                      ),
                  ]),
                if (r.escalated)
                  const Padding(padding: EdgeInsets.only(top: 6), child: Text('Escalation requested - our team has been notified.', style: TextStyle(fontSize: 12, color: Colors.black54))),
                const SizedBox(height: 12),
                _Bubble(fromCustomer: true, text: r.description, at: r.createdAt),
                for (final m in r.messages) _Bubble(fromCustomer: m.fromCustomer, text: m.text, at: m.at),
              ]),
            ),
          ),
          if (r.stage != TicketStage.closed)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: r.stage == TicketStage.resolved ? 'Add a message...' : 'Write a reply...',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: AppColors.navy),
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request});
  final SupportRequest request;

  @override
  Widget build(BuildContext context) {
    final color = _stageColor(request.stage);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.swatchE3E8EE)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(request.categoryLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy))),
          Text(_stageText(request), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
        const SizedBox(height: 2),
        Text([request.number, if (request.bookingRef != null && request.bookingRef!.isNotEmpty) 'Booking ${request.bookingRef}'].join(' - '),
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        if (request.timeline.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final t in request.timeline)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                Icon(Icons.circle, size: 7, color: color),
                const SizedBox(width: 8),
                Text(t.label, style: const TextStyle(fontSize: 12.5)),
                const Spacer(),
                if (t.at != null) Text(formatDmy(t.at!), style: const TextStyle(fontSize: 11, color: Colors.black45)),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromCustomer, required this.text, this.at});
  final bool fromCustomer;
  final String text;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromCustomer ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: fromCustomer ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: fromCustomer ? null : Border.all(color: AppColors.swatchE3E8EE),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!fromCustomer) const Text('SevoNiq Support', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
          Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: fromCustomer ? Colors.white : Colors.black87)),
          if (at != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(formatDmy(at!), style: TextStyle(fontSize: 10, color: fromCustomer ? Colors.white70 : Colors.black45))),
        ]),
      ),
    );
  }
}
