import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/ai_assistant_models.dart';

/// Repository for the CalServices AI Assistant chat gateway.
///
/// Added 2026-09-30 — backs the bottom-nav "AI" tab (replacing the old
/// "Support" tab per explicit request). Talks to the real, already-built
/// Django `ai_assistant` app in the Cus backend (mounted at `/api/ai/` in
/// quicktims/urls.py), not a placeholder:
///   POST   /api/ai/chat/                  — send a message, get a reply
///   GET    /api/ai/conversations/         — list past sessions (auth only)
///   GET    /api/ai/conversations/<uuid>/  — full history for one session
///   DELETE /api/ai/conversations/<uuid>/  — delete one session
/// `AIChatView` on the backend allows guests (AllowAny) as well as signed-in
/// customers, so this works before login too, matching the app's existing
/// guest-booking pattern.
class AiAssistantRepository {
  AiAssistantRepository({required this.api});

  final ApiClient api;

  /// POST /api/ai/chat/ — sends one message and returns the assistant's
  /// reply. Pass the previous [conversationId] to continue that session;
  /// omit it (or pass null/empty) to start a new one — the backend creates
  /// one and returns its id on the reply.
  Future<Result<AiChatReply>> sendMessage({
    required String message,
    String? conversationId,
  }) async {
    try {
      final response = await api.post('/ai/chat/', data: {
        'message': message,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversation_id': conversationId,
      });
      return ResponseNormalizer.extract(response, (data) {
        return AiChatReply.fromJson(Map<String, dynamic>.from(data as Map));
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// GET /api/ai/conversations/<uuid>/ — full message history for one
  /// session, used to restore the transcript if the sheet is reopened with
  /// an existing [conversationId] still held in memory.
  Future<Result<List<AiChatMessage>>> getConversationHistory(
    String conversationId,
  ) async {
    try {
      final response = await api.get('/ai/conversations/$conversationId/');
      return ResponseNormalizer.extract(response, (data) {
        final map = Map<String, dynamic>.from(data as Map);
        final messages = (map['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => AiChatMessage.fromHistoryJson(Map<String, dynamic>.from(m)))
            .toList();
        return messages;
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) {
      return e.error! as ApiError;
    }
    return UnknownError(e.toString());
  }
}

final aiAssistantRepositoryProvider = Provider<AiAssistantRepository>((ref) {
  return AiAssistantRepository(api: ref.watch(apiClientProvider));
});
