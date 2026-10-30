import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../data/ai_assistant_repository.dart';
import 'ai_assistant_models.dart';

/// State for one AI chat sheet session — the transcript shown, whether a
/// reply is in flight, and the backend's own conversation id (once the
/// first message has round-tripped) so a follow-up message continues the
/// same session instead of starting a new one every send.
///
/// Extended 2026-10-08 for the deterministic support-intake wizard
/// ("return / refund / replacement") that `AIChatView` already runs on the
/// backend: [expects] drives whether the sheet shows a plain text field, a
/// row of quick-reply [options], or a photo-attach affordance next, and
/// [handedOff] flips true once the conversation has been handed to a human
/// agent — at which point the sheet stops offering quick replies and shows
/// a "connected to support" banner instead.
class AiChatState {
  const AiChatState({
    this.messages = const [],
    this.conversationId,
    this.isSending = false,
    this.expects = AiChatExpects.text,
    this.options = const [],
    this.handedOff = false,
  });

  final List<AiChatMessage> messages;
  final String? conversationId;
  final bool isSending;
  final AiChatExpects expects;
  final List<AiChatOption> options;
  final bool handedOff;

  AiChatState copyWith({
    List<AiChatMessage>? messages,
    String? conversationId,
    bool? isSending,
    AiChatExpects? expects,
    List<AiChatOption>? options,
    bool? handedOff,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      conversationId: conversationId ?? this.conversationId,
      isSending: isSending ?? this.isSending,
      expects: expects ?? this.expects,
      options: options ?? this.options,
      handedOff: handedOff ?? this.handedOff,
    );
  }
}

/// Drives one AI chat sheet session.
///
/// Added 2026-09-30 as part of the bottom-nav "AI" tab (replacing
/// "Support"). Kept alive for the app's lifetime (via [aiChatControllerProvider]
/// below, no `.autoDispose`) so closing and reopening the sheet resumes the
/// same conversation instead of losing the transcript — same reasoning as
/// the cart provider staying alive across navigation.
class AiChatController extends StateNotifier<AiChatState> {
  AiChatController(this._repository) : super(const AiChatState());

  final AiAssistantRepository _repository;

  // While a chat is handed off to a human agent, the agent's replies are only
  // ever stored on the server (nothing pushes them to the app), so poll for
  // them — the web widget does the same every ~3.5 s.
  Timer? _handoffTimer;
  bool _polling = false;

  @override
  set state(AiChatState value) {
    super.state = value;
    _syncHandoffPolling();
  }

  void _syncHandoffPolling() {
    final shouldPoll = state.handedOff &&
        (state.conversationId ?? '').isNotEmpty;
    if (shouldPoll && _handoffTimer == null) {
      _handoffTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _pollHandoff(),
      );
    } else if (!shouldPoll && _handoffTimer != null) {
      _handoffTimer!.cancel();
      _handoffTimer = null;
    }
  }

  Future<void> _pollHandoff() async {
    final id = state.conversationId;
    if (_polling || state.isSending || id == null || id.isEmpty) return;
    _polling = true;
    try {
      final result = await _repository.getConversationHistory(id);
      // The chat may have been reset / switched while the request was out.
      if (!mounted || state.conversationId != id) return;
      result.when(
        success: (server) {
          // Count how often each assistant line is already on screen, then
          // append only the server lines that aren't (i.e. new agent replies).
          final shown = <String, int>{};
          for (final m in state.messages) {
            if (m.sender == AiChatSender.assistant && !m.isError) {
              shown[m.content] = (shown[m.content] ?? 0) + 1;
            }
          }
          final fresh = <AiChatMessage>[];
          for (final m in server) {
            if (m.sender != AiChatSender.assistant) continue;
            final left = shown[m.content] ?? 0;
            if (left > 0) {
              shown[m.content] = left - 1;
            } else {
              fresh.add(m);
            }
          }
          if (fresh.isNotEmpty) {
            state = state.copyWith(messages: [...state.messages, ...fresh]);
          }
        },
        failure: (_) {},
      );
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _handoffTimer?.cancel();
    super.dispose();
  }

  Future<void> sendMessage(String text, {String? displayText}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    state = state.copyWith(
      messages: [
        ...state.messages,
        AiChatMessage(sender: AiChatSender.user, content: displayText ?? trimmed),
      ],
      isSending: true,
      // Clear the previous step's quick replies immediately so they can't
      // be tapped again while the next reply is in flight.
      options: const [],
    );

    final result = await _repository.sendMessage(
      message: trimmed,
      conversationId: state.conversationId,
    );

    _applyResult(result);
  }

  /// Taps one of the current step's quick-reply chips — sends [option]'s
  /// backend [AiChatOption.value] as the next message while showing its
  /// human-readable [AiChatOption.label] in the user's own chat bubble.
  Future<void> sendOption(AiChatOption option) {
    return sendMessage(option.value, displayText: option.label);
  }

  /// Sends a photo for the current step (`expects == AiChatExpects.image`)
  /// — e.g. a photo of a damaged item during the return/refund wizard.
  /// [caption] is optional free text to go alongside the photo; the backend
  /// substitutes a default when it's empty.
  Future<void> sendImage({
    required Uint8List imageBytes,
    required String imageFileName,
    String caption = '',
  }) async {
    if (state.isSending) return;

    state = state.copyWith(
      messages: [
        ...state.messages,
        AiChatMessage(
          sender: AiChatSender.user,
          content: caption.trim().isEmpty
              ? (_isImageFileName(imageFileName) ? 'Photo' : '')
              : caption.trim(),
          // Only images can be drawn from memory; documents show a file chip.
          localImageBytes: _isImageFileName(imageFileName) ? imageBytes : null,
          photoName: imageFileName,
        ),
      ],
      isSending: true,
      options: const [],
    );

    final result = await _repository.sendMessage(
      message: caption,
      conversationId: state.conversationId,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
    );

    _applyResult(result);
  }

  void _applyResult(Result<AiChatReply> result) {
    result.when(
      success: (reply) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            AiChatMessage(
              sender: AiChatSender.assistant,
              content: reply.message,
              sources: reply.sources,
              photoUrl: reply.photoUrl,
              photoName: reply.photoName,
              navigateTo: reply.navigateTo,
            ),
          ],
          conversationId:
              reply.conversationId.isNotEmpty ? reply.conversationId : state.conversationId,
          isSending: false,
          expects: reply.expects,
          options: reply.options,
          handedOff: reply.handedOff || state.handedOff,
        );
      },
      failure: (ApiError error) {
        final lastUser = state.messages.lastWhere(
          (m) => m.sender == AiChatSender.user,
          orElse: () => const AiChatMessage(sender: AiChatSender.user, content: ''),
        );
        final isOrderQuery = RegExp(r'order|booking|technician|driver|status|track|where|assigned',
                caseSensitive: false)
            .hasMatch(lastUser.content);
        state = state.copyWith(
          messages: [
            ...state.messages,
            AiChatMessage(
              sender: AiChatSender.assistant,
              content: isOrderQuery
                  ? "I couldn't retrieve your order status right now. Please check your My Bookings page or try again in a moment."
                  : error.message,
              isError: true,
              navigateTo: isOrderQuery ? '/bookings' : null,
            ),
          ],
          isSending: false,
        );
      },
    );
  }

  /// Starts a fresh session — used by the sheet's "New chat" action.
  void reset() {
    state = const AiChatState();
  }

  /// Re-opens a saved session from the history list.
  Future<bool> loadConversation(String conversationId) async {
    final result = await _repository.getConversationHistory(conversationId);
    return result.when(
      success: (messages) {
        state = AiChatState(
          messages: messages,
          conversationId: conversationId,
          handedOff: messages.any((m) => m.handedOff),
        );
        return true;
      },
      failure: (_) => false,
    );
  }

  /// "Clear chat": deletes the current session on the server (when it has
  /// been saved) and starts over with an empty transcript.
  Future<void> clearChat() async {
    final id = state.conversationId;
    state = const AiChatState();
    if (id != null && id.isNotEmpty) {
      await _repository.deleteConversation(id);
    }
  }

  /// Deletes one saved session; resets the open chat when it was that one.
  Future<bool> deleteConversation(String id) async {
    final ok = await _repository.deleteConversation(id);
    if (ok && state.conversationId == id) state = const AiChatState();
    return ok;
  }

  /// Deletes every saved session and resets the open chat.
  Future<bool> deleteAllConversations() async {
    final ok = await _repository.deleteAllConversations();
    if (ok) state = const AiChatState();
    return ok;
  }
}

bool _isImageFileName(String name) {
  final i = name.lastIndexOf('.');
  final ext = i < 0 ? '' : name.substring(i + 1).toLowerCase();
  return const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'}.contains(ext);
}

final aiChatControllerProvider =
    StateNotifierProvider<AiChatController, AiChatState>((ref) {
  return AiChatController(ref.watch(aiAssistantRepositoryProvider));
});

/// The signed-in customer's saved chats, newest first (the "history" view).
final aiConversationsProvider =
    FutureProvider.autoDispose<List<AiConversationSummary>>((ref) async {
  final repository = ref.watch(aiAssistantRepositoryProvider);
  final result = await repository.listConversations();
  return result.when(
    success: (list) => list,
    failure: (error) => throw error,
  );
});

/// Fetches one authenticated support-intake photo's bytes for display with
/// `Image.memory` in the chat sheet — keyed by [photoPath] (the
/// `/api/ai/photos/<path>` value a message carries) so each distinct photo
/// in a transcript is only ever fetched once per sheet session.
final aiChatPhotoProvider =
    FutureProvider.family<Uint8List, String>((ref, photoPath) async {
  final repository = ref.watch(aiAssistantRepositoryProvider);
  final result = await repository.fetchPhotoBytes(photoPath);
  return result.when(
    success: (bytes) => bytes,
    failure: (error) => throw error,
  );
});
