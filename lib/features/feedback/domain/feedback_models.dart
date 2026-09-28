import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';

/// Feedback request details loaded via token.
class FeedbackData extends Equatable {
  const FeedbackData({
    required this.token,
    required this.bookingId,
    required this.requestId,
    required this.serviceTitle,
    this.technicianName,
    this.completedAt,
    this.alreadySubmitted = false,
  });

  final String token;
  final int bookingId;
  final String requestId;
  final String serviceTitle;
  final String? technicianName;
  final String? completedAt;
  final bool alreadySubmitted;

  factory FeedbackData.fromJson(Map<String, dynamic> json, String token) {
    return FeedbackData(
      token: token,
      bookingId: parseInt(json['booking_id'] ?? json['id']),
      requestId: (json['request_id'] ?? json['booking_code'] ?? 'CAL-$token').toString(),
      serviceTitle: (json['service_title'] ?? json['service'] ?? 'Home Service').toString(),
      technicianName: json['technician_name']?.toString() ?? json['technician']?.toString(),
      completedAt: json['completed_at']?.toString(),
      alreadySubmitted: parseBoolOrDefault(json['is_submitted'] ?? json['submitted'], false),
    );
  }

  @override
  List<Object?> get props => [
        token,
        bookingId,
        requestId,
        serviceTitle,
        technicianName,
        completedAt,
        alreadySubmitted,
      ];
}

/// Submission payload for customer rating & review.
class FeedbackSubmission extends Equatable {
  const FeedbackSubmission({
    required this.token,
    required this.rating,
    this.punctualityRating = 5,
    this.qualityRating = 5,
    this.behaviorRating = 5,
    this.comments,
    this.tags = const [],
  });

  final String token;
  final int rating; // 1 to 5
  final int punctualityRating;
  final int qualityRating;
  final int behaviorRating;
  final String? comments;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'token': token,
        'rating': rating,
        'punctuality_rating': punctualityRating,
        'quality_rating': qualityRating,
        'behavior_rating': behaviorRating,
        if (comments != null && comments!.isNotEmpty) 'comments': comments,
        'tags': tags,
      };

  @override
  List<Object?> get props => [
        token,
        rating,
        punctualityRating,
        qualityRating,
        behaviorRating,
        comments,
        tags,
      ];
}
