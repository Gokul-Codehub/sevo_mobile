import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../routing/app_router.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../home/domain/home_flow_mode.dart';
import '../../domain/ai_assistant_models.dart';
import '../../domain/ai_assistant_providers.dart';

/// Opens the AI Assistant chat sheet.
///
/// Added 2026-09-30 per explicit request ("remove Support in the footer,
/// replace with AI module... if user clicks that open a 3/4th page in top
/// (x) to close there is the interaction between user and AI chat bot"):
/// a 3/4-screen-height modal sheet, its own (x) close button, talking to
/// the real backend AI Assistant gateway (`/api/ai/chat/`).
Future<void> showAiChatSheet(BuildContext context) {
  // Open on the shell's navigator (when available) so the bottom navigator
  // stays visible under the chat instead of being covered by the sheet.
  final shellContext = shellNavigatorKey.currentContext;
  return showModalBottomSheet(
    context: shellContext ?? context,
    useRootNavigator: shellContext == null,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _AiChatSheet(),
  );
}

class _AiChatSheet extends ConsumerStatefulWidget {
  const _AiChatSheet();

  @override
  ConsumerState<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<_AiChatSheet> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  /// Showing the saved-chats list instead of the live conversation.
  bool _showHistory = false;

  /// A photo picked with the paperclip, waiting to be sent with the next
  /// message (the assistant accepts one image of up to 5 MB per message).
  Uint8List? _attachment;
  String? _attachmentName;
  String? _attachmentError;

  static const _maxAttachmentBytes = 5 * 1024 * 1024;
  static const _allowedExtensions = {'png', 'jpg', 'jpeg', 'webp'};

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Picks a photo from the gallery. (No camera on purpose: the chat only
  /// needs existing photos, and it keeps the camera permission out of it.)
  Future<void> _pickAttachment() async {
    setState(() => _attachmentError = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 88,
      );
      if (picked == null) return;
      final name = picked.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (!_allowedExtensions.contains(ext)) {
        setState(
          () => _attachmentError = 'Please choose a PNG, JPG or WebP image.',
        );
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxAttachmentBytes) {
        setState(
          () => _attachmentError =
              'That photo is over 5 MB. Please choose a smaller one.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _attachment = bytes;
        _attachmentName = name;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _attachmentError =
              "Couldn't open that photo. Please try another.",
        );
    }
  }

  void _clearAttachment() => setState(() {
    _attachment = null;
    _attachmentName = null;
    _attachmentError = null;
  });

  void _send() {
    final text = _inputController.text;
    final bytes = _attachment;
    if (text.trim().isEmpty && bytes == null) return;
    final controller = ref.read(aiChatControllerProvider.notifier);
    _inputController.clear();
    if (bytes != null) {
      final name = _attachmentName ?? 'photo.jpg';
      _clearAttachment();
      controller.sendImage(
        imageBytes: bytes,
        imageFileName: name,
        caption: text,
      );
    } else {
      controller.sendMessage(text);
    }
    _scrollToBottom();
  }

  /// Added 2026-10-08 as part of porting the Cus-backend AI module's
  /// deterministic support-intake wizard: taps one of the step's quick-reply
  /// chips (e.g. an order to pick, a return reason, "Talk to a human").
  void _tapOption(AiChatOption option) {
    // Link chips ("Open AC & Appliance Repair", "View Cancellation Policy")
    // go to that page; the rest are answers sent back to the assistant.
    final url = option.url;
    if (url != null) {
      openAiAssistantLink(context, ref, url);
      return;
    }
    ref.read(aiChatControllerProvider.notifier).sendOption(option);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiChatControllerProvider);
    final mediaQuery = MediaQuery.of(context);

    ref.listen<AiChatState>(aiChatControllerProvider, (previous, next) {
      if (next.messages.length != (previous?.messages.length ?? 0)) {
        _scrollToBottom();
        // "Taking you directly to ..." replies are deliberate navigation (the
        // web chat redirects on them too): go there. Other answers that merely
        // mention a service only get the button under the bubble.
        final last = next.messages.isEmpty ? null : next.messages.last;
        final target = last?.navigateTo;
        if (last != null &&
            last.sender == AiChatSender.assistant &&
            target != null &&
            last.content.startsWith('Taking you directly')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) openAiAssistantLink(context, ref, target);
          });
        }
      }
    });

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SizedBox(
        height: mediaQuery.size.height * 0.75,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              const Divider(height: 1, color: AppColors.divider),
              if (_showHistory)
                Expanded(child: _buildHistoryPanel())
              else ...[
              if (chatState.handedOff) _buildHandoffBanner(),
              Expanded(
                child: chatState.messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount:
                            chatState.messages.length +
                            (chatState.isSending ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= chatState.messages.length) {
                            return const _TypingIndicatorBubble();
                          }
                          return _ChatBubble(
                            message: chatState.messages[index],
                          );
                        },
                      ),
              ),
              // Added 2026-10-08 — quick-reply chips for the support-intake
              // wizard's current step (an order to pick, a return reason,
              // "Talk to support agent" / "I will wait"). Hidden once the
              // conversation has been handed off, since the wizard is done.
              if (!chatState.handedOff && chatState.options.isNotEmpty)
                _buildOptionsRow(chatState.options, chatState.isSending),
              _buildInputBar(chatState.isSending, expects: chatState.expects),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          // Added 2026-10-08 per explicit request ("place that animation
          // beside of the AI Mitra here, with bigger size"): the same
          // robot animation now used on the bottom-nav AI Mitra tab
          // (assets/animations/ai_mitra_robot.json), replacing the static
          // sparkle-in-a-circle icon this header used to show. Sized
          // noticeably bigger (56x56) than the nav tab's 34x34 since this
          // header has the room for it. ClipRect + Transform.scale(1.3)
          // crops the same baked-in transparent padding the nav tab's fix
          // already accounts for -- see app_shell.dart's doc comment on
          // iconSlotSize for the full measurement/reasoning.
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRect(
              child: Transform.scale(
                scale: 1.3,
                child: Lottie.asset(
                  'assets/animations/ai_mitra_robot.json',
                  fit: BoxFit.contain,
                  repeat: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              // Renamed 2026-10-08 per explicit request ("Change the AI bot
              // name from 'AI Mitra' to 'Ask Apta'").
              'Ask Apta',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Chat history',
            icon: Icon(
              Icons.history_rounded,
              color: _showHistory ? AppColors.primary : AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _showHistory = !_showHistory),
          ),
          IconButton(
            tooltip: 'Clear chat',
            icon: const Icon(
              Icons.delete_sweep_outlined,
              color: AppColors.textSecondary,
            ),
            onPressed: _confirmClearChat,
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text('The conversation will be deleted and a fresh chat started.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _clearAttachment();
    await ref.read(aiChatControllerProvider.notifier).clearChat();
    if (mounted) setState(() => _showHistory = false);
  }

  Widget _buildHistoryPanel() {
    final user = ref.watch(currentUserProvider);
    final signedIn = user != null && !user.isGuest;
    final controller = ref.read(aiChatControllerProvider.notifier);

    Widget message(IconData icon, String title, String body) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: AppColors.textHint),
                const SizedBox(height: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navy)),
                const SizedBox(height: 6),
                Text(body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
        );

    final conversations = signedIn ? ref.watch(aiConversationsProvider) : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('Past conversations',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
              ),
              if (signedIn && (conversations?.valueOrNull?.isNotEmpty ?? false))
                TextButton(
                  onPressed: () async {
                    await controller.deleteAllConversations();
                    ref.invalidate(aiConversationsProvider);
                  },
                  child: const Text('Clear all'),
                ),
              FilledButton.icon(
                onPressed: () {
                  _clearAttachment();
                  controller.reset();
                  setState(() => _showHistory = false);
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('New chat'),
              ),
            ],
          ),
        ),
        Expanded(
          child: !signedIn
              ? message(Icons.person_outline_rounded, 'Guest session',
                  'Sign in to keep your chat history across sessions and devices.')
              : conversations!.when(
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (_, __) => message(Icons.cloud_off_rounded, "Couldn't load history",
                      'Please check your connection and try again.'),
                  data: (list) {
                    if (list.isEmpty) {
                      return message(Icons.chat_bubble_outline_rounded, 'No saved conversations',
                          'Your chats with Apta will appear here.');
                    }
                    final currentId = ref.watch(aiChatControllerProvider).conversationId;
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = list[i];
                        final active = c.id == currentId;
                        final d = c.updatedAt;
                        final when = d == null
                            ? ''
                            : ' · ${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final ok = await controller.loadConversation(c.id);
                            if (!mounted) return;
                            if (ok) {
                              setState(() => _showHistory = false);
                              _scrollToBottom();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            decoration: BoxDecoration(
                              color: active ? AppColors.groceryGreenLight : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: active ? AppColors.groceryGreen : AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded,
                                    size: 18, color: AppColors.textSecondary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.navy)),
                                      Text('${c.messageCount} messages$when',
                                          style: const TextStyle(
                                              fontSize: 11.5, color: AppColors.textSecondary)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 20, color: AppColors.textSecondary),
                                  onPressed: () async {
                                    await controller.deleteConversation(c.id);
                                    ref.invalidate(aiConversationsProvider);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 40,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Ask me anything about your bookings, services, or groceries',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Added 2026-10-08 — shown once `handed_off` flips true on a reply, so
  /// the customer knows a live human agent (not the bot) is now reading.
  Widget _buildHandoffBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.support_agent_rounded, size: 16, color: AppColors.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "You're now connected with a support agent",
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Added 2026-10-08 — the current wizard step's quick-reply chips.
  Widget _buildOptionsRow(List<AiChatOption> options, bool isSending) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((option) {
          return Material(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: isSending ? null : () => _tapOption(option),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar(
    bool isSending, {
    AiChatExpects expects = AiChatExpects.text,
  }) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachmentError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _attachmentError!,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ),
            ),
          if (_attachment != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _attachment!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _attachmentName ?? 'Photo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            '${(_attachment!.length / 1024).round()} KB · ready to send',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove photo',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _clearAttachment,
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach a photo',
                  icon: const Icon(
                    Icons.attach_file_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: isSending ? null : _pickAttachment,
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _attachment != null
                          ? 'Add a message (optional)...'
                          : (expects == AiChatExpects.image
                                ? 'Attach a photo with the clip...'
                                : 'Ask Apta or attach a photo...'),
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textHint,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isSending ? null : _send,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Splits AI Mitra's markdown-flavored reply text into plain, `**bold**` and
/// `[label](/path)` link spans, so the chat bubble renders real bold text and
/// TAPPABLE links (the web chat already does) instead of the literal markers.
/// Deliberately a small hand-rolled parser rather than a full markdown
/// package — bold and links are the only formatting the gateway emits.
///
/// [onLink] receives the raw target (a web path like
/// `/booking/services?category=ac_appliance`, or an absolute URL); see
/// [openAiAssistantLink] for how it is mapped onto app screens. When it is
/// null links are shown as plain text.
List<InlineSpan> _parseAiMarkdownSpans(
  String text,
  TextStyle baseStyle, {
  void Function(String url)? onLink,
}) {
  // `[label](url)` — the model sometimes wraps the label in ** and sometimes
  // leaves a space between ] and (.
  final linkPattern = RegExp(r'\[([^\]]+)\]\s*\(([^)\s]+)\)');
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final match in linkPattern.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.addAll(_boldSpans(text.substring(lastEnd, match.start), baseStyle));
    }
    final label = match.group(1)!.replaceAll('**', '').trim();
    final url = match.group(2)!;
    if (onLink == null) {
      spans.add(
        TextSpan(
          text: label,
          style: baseStyle.copyWith(fontWeight: FontWeight.w800),
        ),
      );
    } else {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onLink(url),
            child: Text(
              label,
              style: baseStyle.copyWith(
                color: AppColors.serviceBlue,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.serviceBlue,
              ),
            ),
          ),
        ),
      );
    }
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.addAll(_boldSpans(text.substring(lastEnd), baseStyle));
  }
  return spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans;
}

List<InlineSpan> _boldSpans(String text, TextStyle baseStyle) {
  final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.w800);
  final pattern = RegExp(r'\*\*(.+?)\*\*');
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.add(
        TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle),
      );
    }
    final boldText = match.group(1);
    if (boldText != null && boldText.isNotEmpty) {
      spans.add(TextSpan(text: boldText, style: boldStyle));
    }
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
  }
  return spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans;
}

/// Opens a link from an AI reply. The backend writes WEB paths (the same
/// replies power the website chat), so each is mapped onto the matching app
/// screen; anything the app has no screen for opens on the website instead.
///
///   /booking/services?category=<slug>   -> that service category
///   /booking                            -> all services
///   /trucks/..  /two-wheelers/..  /packers..  -> Goods & Transport
///   /vegetables  /groceries             -> Groceries home
///   /bookings  /cart  /profile  /support -> the matching tab/screen
void openAiAssistantLink(BuildContext context, WidgetRef ref, String rawUrl) {
  var uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return;

  final router = GoRouter.of(context);
  final navigator = Navigator.of(context);

  if (uri.hasScheme) {
    final isSevo = uri.host == 'sevo.co.in' || uri.host.endsWith('.sevo.co.in');
    if (!isSevo) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    uri = Uri(path: uri.path, query: uri.hasQuery ? uri.query : null);
  }

  var path = uri.path;
  if (path.length > 1 && path.endsWith('/'))
    path = path.substring(0, path.length - 1);
  final q = uri.queryParameters;

  String? route;
  var goHome = false;
  if ((path == '/booking/services' || path == '/services') &&
      (q['category'] ?? '').isNotEmpty) {
    // The web groups some services under combined names the app's catalog
    // doesn't have; use the nearest real category, else the full list.
    const aliases = {
      'electrician_plumbing_carpentry': 'electrician',
      'home_pest_control': 'cleaning',
    };
    var slug = q['category']!;
    final known = ref.read(categoriesProvider).valueOrNull;
    if (known != null && !known.any((c) => c.slug == slug)) {
      final alias = aliases[slug];
      slug = (alias != null && known.any((c) => c.slug == alias)) ? alias : '';
    }
    route = slug.isEmpty
        ? '/categories'
        : '/categories/${Uri.encodeComponent(slug)}';
  } else if (path == '/booking' ||
      path == '/services' ||
      path == '/categories') {
    route = '/categories';
  } else if (path.startsWith('/trucks')) {
    route = '/goods-transport/booking?category=truck';
  } else if (path.startsWith('/two-wheelers') ||
      path.startsWith('/two-wheeler')) {
    route = '/goods-transport/booking?category=two_wheeler';
  } else if (path.startsWith('/packers')) {
    route = '/goods-transport/booking?category=packers_movers';
  } else if (path == '/vegetables' ||
      path == '/groceries' ||
      path == '/grocery') {
    goHome = true;
  } else if (path == '/bookings' ||
      path == '/my-bookings' ||
      path == '/customer/bookings') {
    route = '/bookings';
  } else if (path == '/cart') {
    route = '/cart';
  } else if (path == '/profile') {
    route = '/profile';
  } else if (path == '/support') {
    route = '/support';
  }

  if (route == null && !goHome) {
    // No app screen for this one (policy pages etc.) — show it on the site.
    launchUrl(
      Uri.https('sevo.co.in', path, q.isEmpty ? null : q),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  if (goHome) {
    ref.read(homeFlowModeProvider.notifier).state = HomeFlowMode.groceries;
  }
  navigator.pop(); // close the chat sheet
  if (goHome) {
    router.go('/');
  } else {
    router.push(route!);
  }
}

class _ChatBubble extends ConsumerWidget {
  const _ChatBubble({required this.message});

  final AiChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.sender == AiChatSender.user;
    final bubbleColor = message.isError
        ? AppColors.errorLight
        : isUser
        ? AppColors.primary
        : AppColors.surfaceVariant;
    final textColor = isUser && !message.isError
        ? Colors.white
        : AppColors.navy;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Added 2026-10-08 — a photo this device just picked and sent,
            // shown immediately from its in-memory bytes (no round trip
            // needed since this is the device's own just-taken photo).
            if (message.localImageBytes != null) ...[
              _PhotoThumbnail(bytes: message.localImageBytes!),
              const SizedBox(height: 8),
            ]
            // Added 2026-10-08 — a photo attached to a PAST turn, restored
            // from `/api/ai/photos/<path>` (an AUTHENTICATED endpoint —
            // never a bare Image.network, which would skip this app's
            // Bearer token and get a 403).
            else if (message.photoUrl != null) ...[
              _AuthenticatedPhotoThumbnail(photoPath: message.photoUrl!),
              const SizedBox(height: 8),
            ],
            if (message.content.isNotEmpty)
              Text.rich(
                TextSpan(
                  children: _parseAiMarkdownSpans(
                    message.content,
                    TextStyle(fontSize: 14, color: textColor, height: 1.35),
                    onLink: (url) => openAiAssistantLink(context, ref, url),
                  ),
                ),
              ),
            if (!isUser && message.navigateTo != null) ...[
              const SizedBox(height: 10),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () =>
                      openAiAssistantLink(context, ref, message.navigateTo!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.serviceBlue),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Go to Service & Booking Page',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.serviceBlue,
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: AppColors.serviceBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: message.sources
                    .map(
                      (s) => Chip(
                        label: Text(s, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a just-picked photo immediately from its in-memory bytes.
class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, width: 160, height: 160, fit: BoxFit.cover),
    );
  }
}

/// Fetches and renders a support-intake photo from a past turn via the
/// authenticated `/api/ai/photos/<path>` endpoint — see
/// [aiChatPhotoProvider]'s doc comment for why this can't be a bare
/// `Image.network`.
class _AuthenticatedPhotoThumbnail extends ConsumerWidget {
  const _AuthenticatedPhotoThumbnail({required this.photoPath});

  final String photoPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(aiChatPhotoProvider(photoPath));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 160,
        height: 160,
        child: photoAsync.when(
          data: (bytes) => Image.memory(bytes, fit: BoxFit.cover),
          loading: () => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            child: const Icon(
              Icons.broken_image_rounded,
              color: AppColors.textSecondary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatelessWidget {
  const _TypingIndicatorBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 24,
          height: 16,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
