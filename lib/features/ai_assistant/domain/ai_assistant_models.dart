import 'package:equatable/equatable.dart';

/// Added 2026-09-30 — models for the CalServices AI Assistant chat feature.
/// Backed by the Django `ai_assistant` app (`POST/GET /api/ai/chat/`,
/// `/api/ai/conversations/`) — see [AiAssistantRepository]'s doc comment for
/// the full request/response contract.

enum AiChatSender { user, assistant }

/// One turn in the chat transcript, as rendered in the chat sheet.
class AiChatMessage extends Equatable {
  const AiChatMessage({
    required this.sender,
    required this.content,
    this.sources = const [],
    this.isError = false,
  });

  final AiChatSender sender;
  final String content;

  /// Titles of any RAG knowledge-base chunks the backend cited for this
  /// answer (`data.sources` on the chat response) — shown as small
  /// "Sources:" chips under an assistant message when non-empty.
  final List<String> sources;

  /// True for a locally-synthesized message shown when a send fails (e.g.
  /// no network) — styled distinctly so it never looks like a real answer
  /// from the assistant.
  final bool isError;

  factory AiChatMessage.fromHistoryJson(Map<String, dynamic> json) {
    final senderRaw = (json['sender'] as String? ?? 'assistant').toLowerCase();
    return AiChatMessage(
      sender: senderRaw == 'user' ? AiChatSender.user : AiChatSender.assistant,
      content: json['content']?.toString() ?? '',
      sources: (json['sources'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  @override
  List<Object?> get props => [sender, content, sources, isError];
}

/// The parsed `data` object from `POST /api/ai/chat/`.
class AiChatReply {
  const AiChatReply({
    required this.conversationId,
    required this.message,
    required this.agent,
    this.sources = const [],
  });

  final String conversationId;
  final String message;
  final String agent;
  final List<String> sources;

  factory AiChatReply.fromJson(Map<String, dynamic> json) {
    return AiChatReply(
      conversationId: json['conversation_id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      agent: json['agent']?.toString() ?? '',
      sources:
          (json['sources'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
    );
  }
}
