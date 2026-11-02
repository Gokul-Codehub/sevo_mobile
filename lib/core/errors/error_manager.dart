import 'api_error.dart';

/// What to show a customer for a failure: plain language, never a stack trace or raw server text
/// unless the server wrote it for people (validation / business-rule messages).
class UserMessage {
  const UserMessage({required this.title, required this.body, this.retryable = true, this.kind = UserMessageKind.generic});
  final String title;
  final String body;

  /// A "Try again" button makes sense.
  final bool retryable;
  final UserMessageKind kind;
}

enum UserMessageKind { generic, offline, server, signIn, maintenance, featureOff, notFound, forbidden, validation }

/// One place that decides what a failure looks like, so screens stop inventing their own messages.
abstract final class ErrorManager {
  ErrorManager._();

  static const String _tryAgain = 'Please try again in a moment.';

  static UserMessage present(Object? error) {
    if (error is ApiError) {
      switch (error) {
        case NetworkError():
          return const UserMessage(
            title: 'No connection',
            body: 'We could not reach SEVO. Check your internet connection and try again.',
            kind: UserMessageKind.offline,
          );
        case UnauthorizedError():
          return const UserMessage(
            title: 'Please sign in again',
            body: 'Your session has ended. Sign in to continue.',
            retryable: false,
            kind: UserMessageKind.signIn,
          );
        case ForbiddenError():
          return const UserMessage(
            title: 'Not allowed',
            body: 'This account cannot do that.',
            retryable: false,
            kind: UserMessageKind.forbidden,
          );
        case NotFoundError():
          return const UserMessage(
            title: 'Not found',
            body: 'We could not find what you were looking for. It may have been removed.',
            retryable: false,
            kind: UserMessageKind.notFound,
          );
        case ValidationError():
          final code = error.code ?? '';
          if (code == 'MAINTENANCE') {
            return const UserMessage(
              title: 'We are upgrading SEVO',
              body: 'This part of the app is under maintenance. $_tryAgain',
              kind: UserMessageKind.maintenance,
            );
          }
          if (code == 'FEATURE_DISABLED') {
            return UserMessage(
              title: 'Temporarily unavailable',
              body: _readable(error.message) ?? 'This service is temporarily unavailable. $_tryAgain',
              kind: UserMessageKind.featureOff,
            );
          }
          if (code == 'SESSION_REVOKED') {
            return const UserMessage(
              title: 'You were signed out',
              body: 'Please sign in again.',
              retryable: false,
              kind: UserMessageKind.signIn,
            );
          }
          // The server writes these for customers (slot full, minimum order...): show them.
          return UserMessage(
            title: 'Please check and try again',
            body: _readable(error.message) ?? 'Some details need your attention.',
            kind: UserMessageKind.validation,
          );
        case ServerError():
          return const UserMessage(
            title: 'Something went wrong',
            body: 'Our server had a problem. $_tryAgain',
            kind: UserMessageKind.server,
          );
        case ParseError() || ApiContractError() || UnknownError():
          return const UserMessage(title: 'Something went wrong', body: 'We could not complete that. $_tryAgain');
      }
    }
    return const UserMessage(title: 'Something went wrong', body: 'We could not complete that. $_tryAgain');
  }

  /// A server message is shown only if it reads like text for people (short, no code or markup).
  static String? _readable(String message) {
    final m = message.trim();
    if (m.isEmpty || m.length > 200) return null;
    if (RegExp(r'[{}<>]|Traceback|Exception|stack|\bat \w+\.').hasMatch(m)) return null;
    return m;
  }

  /// Whether retrying the same request could help (used by retry buttons and the retry interceptor's UI).
  static bool isRetryable(Object? error) => present(error).retryable;
}
