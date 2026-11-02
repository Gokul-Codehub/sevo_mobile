import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/errors/error_manager.dart';
import '../../../../core/navigation/safe_back.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/utils/date_utils.dart';
import '../../../../shared/widgets/state_widgets.dart';
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
      TicketStage.open => const Color(0xFFB26A00),
      TicketStage.inProgress => const Color(0xFF1E5AA8),
      TicketStage.waitingOnYou => AppColors.error,
      TicketStage.resolved => const Color(0xFF1B7F4B),
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
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _bar(context, 'My support requests'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/support/new'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New request'),
      ),
      body: requests.when(
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
            onRefresh: () async => ref.invalidate(supportRequestsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [for (final r in list) _RequestCard(request: r)],
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE3E8EE))),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _bar(context, 'New support request'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('What is this about?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final e in kSupportTopics.entries)
              ChoiceChip(
                label: Text(e.value.label),
                selected: _topic == e.key,
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(color: _topic == e.key ? Colors.white : AppColors.navy, fontWeight: FontWeight.w600, fontSize: 12.5),
                onSelected: (_) => setState(() => _topic = e.key),
              ),
          ]),
          if ((widget.bookingRef ?? widget.bookingId ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.link_rounded, size: 18, color: AppColors.navy),
              const SizedBox(width: 6),
              Text('About booking ${widget.bookingRef ?? widget.bookingId}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
            ]),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            maxLines: 6,
            maxLength: 2000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: topic.hint,
              helperText: 'Tell us what happened (at least 10 characters).',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 6),
          ReviewPhotoPicker(photos: _photos, onChanged: (p) => setState(() => _photos = p), title: 'Add photos (optional)', subtitle: 'Damage, a wrong bill, anything that helps.'),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _valid && !_busy ? _submit : null,
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size.fromHeight(50)),
            child: Text(_busy ? 'Sending...' : 'Submit request'),
          ),
        ],
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
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: _bar(context, 'Support request'),
      body: async.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState.from(e, onRetry: () => ref.invalidate(supportRequestProvider(widget.id))),
        data: (r) => Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(supportRequestProvider(widget.id)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E8EE))),
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
          border: fromCustomer ? null : Border.all(color: const Color(0xFFE3E8EE)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!fromCustomer) const Text('SEVO Support', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
          Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: fromCustomer ? Colors.white : Colors.black87)),
          if (at != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(formatDmy(at!), style: TextStyle(fontSize: 10, color: fromCustomer ? Colors.white70 : Colors.black45))),
        ]),
      ),
    );
  }
}
