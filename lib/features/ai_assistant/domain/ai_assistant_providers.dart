import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../data/ai_assistant_repository.dart';
import 'ai_assistant_models.dart';

/// State for one AI chat sheet session — the transcript shown, whether a
/// reply is in flight, and the backend's own conversation id (once the
/// first message has round-tripped) so a follow-up message continues the
/// same session instead of starting a new one every send.
class AiChatState {
  const AiChatState({
    this.messages = const [],
    this.conversationId,
    this.isSending = false,
  });

  final List<AiChatMessage> messages;
  final String? conversationId;
  final bool isSending;

  AiChatState copyWith({
    List<AiChatMessage>? messages,
    String? conversationId,
    bool? isSending,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      conversationId: conversationId ?? this.conversationId,
      isSending: isSending ?? this.isSending,
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

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    state = state.copyWith(
      messages: [
        ...state.messages,
        AiChatMessage(sender: AiChatSender.user, content: trimmed),
      ],
      isSending: true,
    );

    final result = await _repository.sendMessage(
      message: trimmed,
      conversationId: state.conversationId,
    );

    result.when(
      success: (reply) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            AiChatMessage(
              sender: AiChatSender.assistant,
              content: reply.message,
              sources: reply.sources,
            ),
          ],
          conversationId:
              reply.conversationId.isNotEmpty ? reply.conversationId : state.conversationId,
          isSending: false,
        );
      },
      failure: (ApiError error) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            AiChatMessage(
              sender: AiChatSender.assistant,
              content: error.message,
              isError: true,
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
}

final aiChatControllerProvider =
    StateNotifierProvider<AiChatController, AiChatState>((ref) {
  return AiChatController(ref.watch(aiAssistantRepositoryProvider));
});
