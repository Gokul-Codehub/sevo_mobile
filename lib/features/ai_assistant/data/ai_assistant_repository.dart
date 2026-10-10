import 'dart:typed_data';

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
///   GET    /api/ai/photos/<path>          — authenticated support photo
/// `AIChatView` on the backend allows guests (AllowAny) as well as signed-in
/// customers, so this works before login too, matching the app's existing
/// guest-booking pattern.
///
/// Extended 2026-10-08 to carry an optional photo alongside a message
/// (`sendMessage`'s [imageBytes]/[imageFileName]) — the backend's
/// deterministic support-intake wizard can ask for a photo of the issue
/// (`expects: "image"`) partway through a return/refund/replacement flow,
/// and `AIChatView.post` already accepts a multipart `image` field
/// alongside `message`/`conversation_id` for exactly this.
class AiAssistantRepository {
  AiAssistantRepository({required this.api});

  final ApiClient api;

  /// POST /api/ai/chat/ — sends one message (optionally with a photo) and
  /// returns the assistant's reply. Pass the previous [conversationId] to
  /// continue that session; omit it (or pass null/empty) to start a new one
  /// — the backend creates one and returns its id on the reply.
  ///
  /// [imageBytes]/[imageFileName] are both required together to attach a
  /// photo — when present this sends multipart form data instead of plain
  /// JSON, matching `AIChatView`'s `parser_classes = [JSONParser,
  /// MultiPartParser, FormParser]`. [message] may be empty when only a
  /// photo is being sent — the backend substitutes a default caption.
  Future<Result<AiChatReply>> sendMessage({
    required String message,
    String? conversationId,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
    try {
      final hasImage = imageBytes != null && imageFileName != null;
      final response = await api.post(
        '/ai/chat/',
        data: hasImage
            ? FormData.fromMap({
                'message': message,
                if (conversationId != null && conversationId.isNotEmpty)
                  'conversation_id': conversationId,
                'image': MultipartFile.fromBytes(imageBytes, filename: imageFileName),
              })
            : {
                'message': message,
                if (conversationId != null && conversationId.isNotEmpty)
                  'conversation_id': conversationId,
              },
      );
      return ResponseNormalizer.extract(response, (data) {
        return AiChatReply.fromJson(Map<String, dynamic>.from(data as Map));
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// GET /api/ai/photos/<path> — fetches the raw bytes of an authenticated
  /// support-intake photo (the current user's own, or a guest's own via the
  /// shared `guest_session_token` cookie) so the chat sheet can render it
  /// with `Image.memory`. A bare `Image.network` would never attach this
  /// app's Bearer token, and the endpoint 403s without it, so this goes
  /// through the same authenticated [api] every other request uses.
  Future<Result<Uint8List>> fetchPhotoBytes(String photoPath) async {
    try {
      final response = await api.get<List<int>>(
        photoPath,
        options: Options(responseType: ResponseType.bytes),
      );
      final raw = response.data;
      if (raw == null) return Failure(UnknownError('Empty photo response'));
      return Success(Uint8List.fromList(raw));
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
