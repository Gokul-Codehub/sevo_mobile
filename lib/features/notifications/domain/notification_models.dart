import 'package:equatable/equatable.dart';

/// One row of the customer's in-app inbox — `CustomerNotification` on the
/// backend (`GET /api/accounts/notifications/`).
///
/// [deepLink] / [actionUrl] are WEB paths (the same rows power the website's
/// bell), e.g. `/booking/services?category=ac_appliance&service=...&waitlist_claim=<token>`;
/// the app maps them onto its own screens (see `resolveWebLink`).
class CustomerNotification extends Equatable {
  const CustomerNotification({
    required this.id,
    required this.eventKey,
    required this.category,
    required this.level,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.actionLabel,
    required this.actionUrl,
    required this.isRead,
    required this.requiresAction,
    required this.createdAt,
    this.expiresAt,
  });

  final int id;
  final String eventKey;

  /// BOOKING | ORDER | PAYMENT | SUPPORT | ACCOUNT | OFFER
  final String category;

  /// INFO | SUCCESS | WARNING | CRITICAL
  final String level;
  final String title;
  final String body;
  final String deepLink;
  final String actionLabel;
  final String actionUrl;
  final bool isRead;

  /// Stays pinned until acted on (e.g. "a slot opened, book it now").
  final bool requiresAction;
  final DateTime createdAt;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// Where tapping the row (or its action button) should go, if anywhere.
  String? get target {
    final a = actionUrl.trim();
    if (a.isNotEmpty) return a;
    final d = deepLink.trim();
    return d.isEmpty ? null : d;
  }

  CustomerNotification copyWith({bool? isRead}) => CustomerNotification(
        id: id,
        eventKey: eventKey,
        category: category,
        level: level,
        title: title,
        body: body,
        deepLink: deepLink,
        actionLabel: actionLabel,
        actionUrl: actionUrl,
        isRead: isRead ?? this.isRead,
        requiresAction: requiresAction,
        createdAt: createdAt,
        expiresAt: expiresAt,
      );

  factory CustomerNotification.fromJson(Map<String, dynamic> j) {
    DateTime? dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return CustomerNotification(
      id: int.tryParse('${j['id']}') ?? 0,
      eventKey: (j['event_key'] ?? '').toString(),
      category: (j['category'] ?? '').toString(),
      level: (j['level'] ?? 'INFO').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      deepLink: (j['deep_link'] ?? '').toString(),
      actionLabel: (j['action_label'] ?? '').toString(),
      actionUrl: (j['action_url'] ?? '').toString(),
      isRead: j['is_read'] == true,
      requiresAction: j['requires_action'] == true,
      createdAt: dt(j['created_at']) ?? DateTime.now(),
      expiresAt: dt(j['expires_at']),
    );
  }

  @override
  List<Object?> get props => [id, isRead, title, body, expiresAt];
}

/// The list endpoint's page: newest first, plus the unread total.
class NotificationPage {
  const NotificationPage({required this.items, required this.unreadCount});

  final List<CustomerNotification> items;
  final int unreadCount;
}
