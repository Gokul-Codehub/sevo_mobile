import 'dart:async';

import 'package:flutter/material.dart';

import 'branded_loading_screen.dart';
import 'common_widgets.dart';

/// Blinkit-style loading skeleton for a listing page: the real app bar stays
/// on screen while grey placeholders stand in for the left category rail and
/// the product grid / package list, so the page already looks "built" while
/// the data arrives.
class ListingSkeleton extends StatelessWidget {
  const ListingSkeleton({super.key, this.grid = false, this.showRail = true});

  /// Two-column product grid (groceries) instead of a single-column list
  /// (service packages).
  final bool grid;

  /// Left category rail placeholder. Turn off when the real rail is already
  /// on screen around this skeleton.
  final bool showRail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showRail)
          Container(
            width: 78,
            color: Colors.white,
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: List.generate(
                8,
                (_) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ShimmerCircle(size: 48),
                      SizedBox(height: 6),
                      ShimmerLine(width: 40, height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              // Filter-chip row.
              const Row(
                children: [
                  ShimmerBox(width: 72, height: 30, borderRadius: 15),
                  SizedBox(width: 8),
                  ShimmerBox(width: 64, height: 30, borderRadius: 15),
                  SizedBox(width: 8),
                  ShimmerBox(width: 84, height: 30, borderRadius: 15),
                ],
              ),
              const SizedBox(height: 14),
              if (grid)
                ...List.generate(3, (_) => const _GridRowSkeleton())
              else
                ...List.generate(
                  4,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: ShimmerCard(height: 130),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GridRowSkeleton extends StatelessWidget {
  const _GridRowSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget cell() => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(height: 120, borderRadius: 12),
            SizedBox(height: 8),
            ShimmerLine(height: 10),
            SizedBox(height: 6),
            ShimmerLine(width: 70, height: 10),
          ],
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cell()),
          const SizedBox(width: 12),
          Expanded(child: cell()),
        ],
      ),
    );
  }
}

/// Blinkit-style loading sequence: the branded illustration + tagline first,
/// then (if the data is still not here) the page skeleton. Only ever visible
/// while something is genuinely loading — as soon as the real content builds,
/// this widget is simply replaced.
class IllustrationThenSkeleton extends StatefulWidget {
  const IllustrationThenSkeleton({
    super.key,
    required this.skeleton,
    this.introDuration = const Duration(milliseconds: 1000),
  });

  final Widget skeleton;
  final Duration introDuration;

  @override
  State<IllustrationThenSkeleton> createState() => _IllustrationThenSkeletonState();
}

class _IllustrationThenSkeletonState extends State<IllustrationThenSkeleton> {
  bool _showSkeleton = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.introDuration, () {
      if (mounted) setState(() => _showSkeleton = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _showSkeleton
          ? KeyedSubtree(key: const ValueKey('skeleton'), child: widget.skeleton)
          : Container(
              key: const ValueKey('intro'),
              color: Colors.white,
              child: const BrandedLoader(),
            ),
    );
  }
}
