import '../../core/l10n/locale_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors/error_manager.dart';
import '../theme/app_colors.dart';

/// Full-area error: icon, plain-language message and a Retry that re-runs the request.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.compact = false});

  /// Build one from any error: `ErrorState.from(error, onRetry: () => ref.invalidate(provider))`.
  factory ErrorState.from(Object? error, {Key? key, VoidCallback? onRetry, bool compact = false}) =>
      ErrorState(key: key, message: ErrorManager.present(error), onRetry: onRetry, compact: compact);

  final UserMessage message;
  final VoidCallback? onRetry;
  final bool compact;

  IconData get _icon => switch (message.kind) {
        UserMessageKind.offline => Icons.wifi_off_rounded,
        UserMessageKind.maintenance || UserMessageKind.featureOff => Icons.construction_rounded,
        UserMessageKind.signIn => Icons.lock_outline_rounded,
        UserMessageKind.notFound => Icons.search_off_rounded,
        _ => Icons.error_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: compact ? 36 : 52, color: AppColors.navy),
            const SizedBox(height: 14),
            Text(message.title,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 6),
            Text(message.body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black54)),
            if (message.retryable && onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size(140, 46)),
                child: Text(context.l10n.tryAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Nothing here yet" - always says what and what to do, never just "No data".
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 34, backgroundColor: const Color(0xFFEAF0F6), child: Icon(icon, size: 34, color: AppColors.navy)),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black54)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder that appears only after [delay] (default 300 ms), so quick loads do not flicker.
class LoadingState extends StatefulWidget {
  const LoadingState({super.key, this.delay = const Duration(milliseconds: 300), this.lines = 4});
  final Duration delay;
  final int lines;

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.expand();
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < widget.lines; i++)
            Container(
              height: 64,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: const Color(0xFFE3E8EE), borderRadius: BorderRadius.circular(12)),
            ),
        ],
      ),
    );
  }
}
