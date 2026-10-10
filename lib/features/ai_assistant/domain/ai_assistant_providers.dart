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
          content: caption.trim().isEmpty ? 'Photo' : caption.trim(),
          localImageBytes: imageBytes,
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
