import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Added 2026-09-30 — models for the CalServices AI Assistant chat feature.
/// Backed by the Django `ai_assistant` app (`POST/GET /api/ai/chat/`,
/// `/api/ai/conversations/`) — see [AiAssistantRepository]'s doc comment for
/// the full request/response contract.
///
/// Extended 2026-10-08 ("go to the AI module in Cus folder, there are many
/// changes made by that developer, could you get it and implement in our
/// app"): the backend had grown a full deterministic "return / refund /
/// replacement" support-intake flow (AIChatView, 1200+ lines) on top of the
/// plain chat this app originally wired up — a guided wizard that walks the
/// customer through picking an order, a reason, optionally a photo of the
/// issue, then hands the conversation off to a live human agent — but none
/// of its richer response fields (`expects`, `options`, `handed_off`,
/// `photo_url`/`photo_name`) were ever modeled or rendered here, so the
/// app only ever showed the step's plain text and left the customer with no
/// way to tap a choice or attach a photo.

enum AiChatSender { user, assistant }

/// One selectable quick-reply the backend offers for the current step (e.g.
/// "Damaged", "Wrong item", an order to pick, or "Skip") — [value] is what
/// gets sent back as the next chat message, [label] is what the chip shows.
class AiChatOption extends Equatable {
  const AiChatOption({required this.label, required this.value});

  final String label;
  final String value;

  factory AiChatOption.fromJson(Map<String, dynamic> json) {
    return AiChatOption(
      label: (json['label'] ?? json['value'] ?? '').toString(),
      value: (json['value'] ?? json['label'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [label, value];
}

/// What kind of reply the backend is waiting for after this message —
/// drives which input affordance the chat sheet shows next.
enum AiChatExpects { text, choice, image }

AiChatExpects _parseExpects(dynamic raw) {
  switch ((raw ?? 'text').toString().toLowerCase()) {
    case 'choice':
      return AiChatExpects.choice;
    case 'image':
      return AiChatExpects.image;
    default:
      return AiChatExpects.text;
  }
}

/// One turn in the chat transcript, as rendered in the chat sheet.
class AiChatMessage extends Equatable {
  const AiChatMessage({
    required this.sender,
    required this.content,
    this.sources = const [],
    this.isError = false,
    this.photoUrl,
    this.photoName,
    this.localImageBytes,
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

  /// Set when this turn carried a support-intake photo — `/api/ai/photos/…`,
  /// an AUTHENTICATED path (PhotoAccessGateView), never a plain public
  /// image URL. Shown as a small thumbnail in the bubble.
  final String? photoUrl;
  final String? photoName;

  /// Raw bytes of a photo this device just picked and sent, kept only in
  /// memory for an instant local preview — never persisted, never set when
  /// a message is rebuilt from `fromHistoryJson` (use [photoUrl] via the
  /// authenticated fetch for anything that survived a sheet reopen).
  final Uint8List? localImageBytes;

  factory AiChatMessage.fromHistoryJson(Map<String, dynamic> json) {
    final senderRaw = (json['sender'] as String? ?? 'assistant').toLowerCase();
    return AiChatMessage(
      sender: senderRaw == 'user' ? AiChatSender.user : AiChatSender.assistant,
      content: json['content']?.toString() ?? '',
      sources: (json['sources'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      photoUrl: (json['photo_url'] ?? '').toString().trim().isEmpty
          ? null
          : json['photo_url'].toString().trim(),
      photoName: (json['photo_name'] ?? '').toString().trim().isEmpty
          ? null
          : json['photo_name'].toString().trim(),
    );
  }

  @override
  List<Object?> get props =>
      [sender, content, sources, isError, photoUrl, photoName, localImageBytes];
}

/// The parsed `data` object from `POST /api/ai/chat/`.
class AiChatReply {
  const AiChatReply({
    required this.conversationId,
    required this.message,
    required this.agent,
    this.sources = const [],
    this.expects = AiChatExpects.text,
    this.options = const [],
    this.handedOff = false,
    this.photoUrl,
    this.photoName,
  });

  final String conversationId;
  final String message;
  final String agent;
  final List<String> sources;

  /// What the backend wants back next — plain text, a tap on one of
  /// [options], or a photo upload (the deterministic support-intake wizard
  /// steps through all three in sequence).
  final AiChatExpects expects;

  /// Quick-reply choices for this step (e.g. which order, a return reason,
  /// "Talk to support agent" / "I will wait"). Empty when [expects] is
  /// [AiChatExpects.text].
  final List<AiChatOption> options;

  /// True once this conversation has been handed off to a live human
  /// support agent — the chat sheet shows a "connected to support" banner
  /// and stops offering quick replies once this flips true.
  final bool handedOff;

  /// Echoed back when this reply's own turn carried a photo (e.g. the
  /// assistant's handoff confirmation after an upload).
  final String? photoUrl;
  final String? photoName;

  factory AiChatReply.fromJson(Map<String, dynamic> json) {
    return AiChatReply(
      conversationId: json['conversation_id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      agent: json['agent']?.toString() ?? '',
      sources:
          (json['sources'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      expects: _parseExpects(json['expects']),
      options: (json['options'] as List?)
              ?.whereType<Map>()
              .map((m) => AiChatOption.fromJson(Map<String, dynamic>.from(m)))
              .where((o) => o.label.isNotEmpty)
              .toList() ??
          const [],
      handedOff: json['handed_off'] == true,
      photoUrl: (json['photo_url'] ?? '').toString().trim().isEmpty
          ? null
          : json['photo_url'].toString().trim(),
      photoName: (json['photo_name'] ?? '').toString().trim().isEmpty
          ? null
          : json['photo_name'].toString().trim(),
    );
  }
}
