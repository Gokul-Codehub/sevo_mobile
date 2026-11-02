import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/errors/error_manager.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../../../shared/utils/app_toast.dart';

/// How the server wants this call to happen.
///  * bridge       - masked: the server is ringing the customer now and will connect them (nobody sees a real number)
///  * direct       - masking is not set up (or failed) and direct calling is still allowed: the app dials the number
///  * unavailable  - calling is not possible right now (the message says why)
enum CallMode { bridge, direct, unavailable }

class CallOutcome {
  const CallOutcome(this.mode, [this.message]);
  final CallMode mode;
  final String? message;
}

class CallRepository {
  CallRepository({required this.api});
  final ApiClient api;

  /// `POST /booking/<id>/call/`
  Future<Result<CallOutcome>> start(int bookingId) async {
    try {
      final response = await api.post('/booking/$bookingId/call/', data: <String, dynamic>{});
      return ResponseNormalizer.extract(response, (d) {
        final m = d is Map ? d : const {};
        final mode = switch (m['mode']) {
          'bridge' => CallMode.bridge,
          'direct' => CallMode.direct,
          _ => CallMode.unavailable,
        };
        return CallOutcome(mode, m['message']?.toString());
      });
    } on ApiError catch (e) {
      return Failure(e);
    } on DioException catch (e) {
      return Failure(e.error is ApiError ? e.error! as ApiError : const NetworkError());
    } catch (_) {
      return const Failure(UnknownError());
    }
  }
}

final callRepositoryProvider = Provider<CallRepository>((ref) => CallRepository(api: ref.watch(apiClientProvider)));

/// Call the assigned technician / driver. Asks the server first so the call can be masked; only dials the number
/// directly when the server says that is allowed. [launcher] is a test seam.
Future<void> callProfessional(
  BuildContext context,
  WidgetRef ref, {
  required int? bookingId,
  required String? directNumber,
  Future<bool> Function(Uri uri)? launcher,
}) async {
  final launch = launcher ?? (uri) => launchUrl(uri);

  Future<void> dial() async {
    if (directNumber == null || directNumber.trim().isEmpty) return;
    await launch(Uri(scheme: 'tel', path: directNumber.trim()));
  }

  if (bookingId == null || bookingId <= 0) {
    await dial(); // no booking to ask the server about (should not happen on these screens)
    return;
  }
  final result = await ref.read(callRepositoryProvider).start(bookingId);
  if (!context.mounted) return;
  switch (result) {
    case Success(:final data):
      switch (data.mode) {
        case CallMode.bridge:
          AppToast.show(context, data.message ?? 'We are calling you now. Pick up to be connected.', type: AppToastType.info);
        case CallMode.direct:
          await dial();
        case CallMode.unavailable:
          AppToast.show(context, data.message ?? 'Calling is not available right now.', type: AppToastType.info);
      }
    case Failure(:final error):
      AppToast.show(context, ErrorManager.present(error).body, type: AppToastType.error);
  }
}
