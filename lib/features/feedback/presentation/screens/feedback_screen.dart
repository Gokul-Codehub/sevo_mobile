import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../data/feedback_repository.dart';
import '../../domain/feedback_models.dart';

/// Screen 19: Completed & Rating Screen
/// Matches reference screen 19 with celebration banner, 5-star rating selector,
/// compliment chips, feedback comment box, and submit action.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  int _overallRating = 5;
  final int _punctualityRating = 5;
  final int _qualityRating = 5;
  final int _behaviorRating = 5;
  final _commentController = TextEditingController();
  final Set<String> _selectedTags = {'On Time ⏱️', 'Clean & Tidy 🧹'};
  bool _isLoading = false;
  bool _isSubmitted = false;

  static const _availableTags = [
    'On Time ⏱️',
    'Polite Behavior 🤝',
    'Clean & Tidy 🧹',
    'Expert Quality 🛠️',
    'Reasonable Pricing 💰',
    'Great Communication 📞',
  ];

  static const _ratingLabels = [
    '',
    'Poor 😞',
    'Fair 😐',
    'Good 🙂',
    'Very Good 😊',
    'Excellent! 🌟',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    setState(() => _isLoading = true);

    final submission = FeedbackSubmission(
      token: widget.token,
      rating: _overallRating,
      punctualityRating: _punctualityRating,
      qualityRating: _qualityRating,
      behaviorRating: _behaviorRating,
      comments: _commentController.text.trim(),
      tags: _selectedTags.toList(),
    );

    final result = await ref
        .read(feedbackRepositoryProvider)
        .submitFeedback(submission);

    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case Success():
        setState(() => _isSubmitted = true);
      case Failure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not submit feedback: ${error.message}'),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedbackAsync = ref.watch(feedbackDetailsProvider(widget.token));

    if (_isSubmitted) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.sentiment_very_satisfied_rounded,
                      color: AppColors.primary,
                      size: 54,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Thank You for Your Feedback!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your review helps us maintain high quality standards across all SEVO service professionals.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.go('/'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Back to Home'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Rate Your Experience',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.pop(),
        ),
      ),
      body: feedbackAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              ShimmerCard(height: 120, borderRadius: 16),
              SizedBox(height: 20),
              ShimmerLine(width: 160, height: 16),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShimmerBox(width: 40, height: 40, shape: BoxShape.circle),
                  SizedBox(width: 8),
                  ShimmerBox(width: 40, height: 40, shape: BoxShape.circle),
                  SizedBox(width: 8),
                  ShimmerBox(width: 40, height: 40, shape: BoxShape.circle),
                  SizedBox(width: 8),
                  ShimmerBox(width: 40, height: 40, shape: BoxShape.circle),
                  SizedBox(width: 8),
                  ShimmerBox(width: 40, height: 40, shape: BoxShape.circle),
                ],
              ),
              SizedBox(height: 24),
              ShimmerCard(height: 120, borderRadius: 12),
            ],
          ),
        ),
        error: (err, stackTrace) => ErrorStateWidget(
          message: err.toString(),
          onRetry: () =>
              ref.refresh(feedbackDetailsProvider(widget.token)),
        ),
        data: (data) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Service & Technician Card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        data.serviceTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (data.technicianName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Serviced by ${data.technicianName}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Booking ID: ${data.requestId}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── 1. Star Rating ──
                const Text(
                  'How was your overall service?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _overallRating = starValue),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          starValue <= _overallRating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 44,
                          color: starValue <= _overallRating
                              ? AppColors.star
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  _ratingLabels[_overallRating],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _overallRating >= 4
                        ? AppColors.primary
                        : AppColors.navy,
                  ),
                ),

                const SizedBox(height: 28),

                // ── 2. Compliments Tags ──
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What went well?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableTags.map((tag) {
                    final isSelected = _selectedTags.contains(tag);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedTags.remove(tag);
                          } else {
                            _selectedTags.add(tag);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFF0FDF4)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                            width: isSelected ? 1.5 : 0.8,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.navy
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // ── 3. Comments Box ──
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Additional Feedback (Optional)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Tell us what you liked or how we can improve...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textHint,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.border, width: 0.8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.border, width: 0.8),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Submit Button ──
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Submit Review',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}

