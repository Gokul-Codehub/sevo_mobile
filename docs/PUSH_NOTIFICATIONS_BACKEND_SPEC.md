# Push Notifications — Backend Spec

**Status:** Not started. This is a spec, not a plan of work already in
progress.

## Why this exists

The customer app can already show real notifications in the phone's
notification center (see `lib/core/services/notification_service.dart`
and `lib/core/services/booking_notification_watcher.dart`), but only
while the app process is alive — triggered locally, from inside the
running app, either right after a successful booking-create or by
periodically re-checking booking statuses. That's the best available
without server changes, but it can't do what a real push notification
does: arrive even when the app has been fully closed or the phone was
restarted.

Confirmed against the current backend (`accounts/`, `service_requests/`,
`logistics/`, `settings_hub/`): there is no device-token model, no
FCM/APNs integration, and no push dispatch anywhere. This is genuinely
new backend work, not a bug fix.

## What has to be built

### 1. A device-token registry

A new model, e.g.:

```python
class CustomerDeviceToken(models.Model):
    customer = models.ForeignKey('accounts.Customer', on_delete=models.CASCADE, related_name='device_tokens')
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=16, choices=[('android', 'Android'), ('ios', 'iOS')])
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)
```

Endpoints (mirroring the existing `accounts` auth patterns —
`CookieJWTAuthentication`, `IsAuthenticated`):

- `POST /api/notifications/devices/` — body `{ "token": "...", "platform": "android" | "ios" }`. Upserts by `token` (a token can be re-registered, e.g. after `flutter_local_notifications`'/Firebase's token refresh) and always (re)associates it with the calling customer, since the same physical token can belong to a different account after logout/login on a shared device.
- `DELETE /api/notifications/devices/` — body `{ "token": "..." }`. Called on logout so a signed-out device stops receiving that customer's pushes.

### 2. A push-sending service

A thin wrapper — e.g. `backend/notifications/push_service.py` — around
Firebase Cloud Messaging's HTTP v1 API (covers both Android and iOS
devices from one call when using FCM as the transport, which is the
standard approach even for iOS — no separate raw-APNs integration
needed). Something like:

```python
def send_push(customer_id: int, title: str, body: str, data: dict | None = None) -> None:
    tokens = CustomerDeviceToken.objects.filter(customer_id=customer_id).values_list('token', flat=True)
    for token in tokens:
        # fcm_admin.messaging.send(...) — remove the token from the DB
        # on an "unregistered/invalid token" response instead of retrying it.
        ...
```

Never raise from this function into the caller — a push failure must
never fail (or roll back) the booking-status transition that triggered
it.

### 3. The dispatch hook

Call `send_push(...)` from exactly one place:
`backend/service_requests/state_machine.py`'s `apply_transition` (or
wherever the transition is finally persisted), so every real status
change gets a push — not from individual views, which would miss
transitions triggered from the admin panel or an internal script.

Suggested title/body per transition (matches the copy the app's local
watcher already uses in `booking_notification_watcher.dart`, so the
experience is identical once real push replaces/joins it):

| New status | Title | Body |
| --- | --- | --- |
| `confirmed` | Booking Confirmed | `{service_title}` has been confirmed. |
| `assigned` | Technician Assigned | `{technician_name}` has been assigned to `{service_title}`. |
| `on_the_way` | Technician On The Way | `{technician_name}` is on the way for `{service_title}`. |
| `arrived` | Technician Has Arrived | Your technician has arrived for `{service_title}`. |
| `in_progress` | Service In Progress | `{service_title}` is now in progress. |
| `completed` / `closed` | Service Completed | `{service_title}` has been completed. Rate your experience! |
| `cancelled` / `rejected` | Booking Cancelled | `{service_title}` was cancelled. |
| `rescheduled` | Booking Rescheduled | `{service_title}` has been rescheduled. |

Include `data: { "route": "/bookings/{id}" }` in every payload — the
Flutter app's tap handler (`NotificationService._onNotificationTapped`)
already expects a route string and will push straight to it; migrating
from local-only to real push needs no client-side routing change.

### 4. Client-side wiring once this exists

Small, additive changes only:

- Add `firebase_messaging` (needs a Firebase project + `google-services.json`
  for Android, and an APNs key uploaded to that Firebase project for iOS —
  both must come from the project owner, not from an agent).
- On login success and app start, get the FCM token and
  `POST /api/notifications/devices/` it; on logout,
  `DELETE /api/notifications/devices/` it.
- Handle `FirebaseMessaging.onMessage` (foreground) by calling the
  existing `NotificationService.instance.show(...)` — same function
  already used for local notifications, so foreground push and local
  notifications look identical.
- Background/terminated messages are handled by FCM natively showing the
  system notification; only the tap-to-route wiring needs connecting to
  the existing `NotificationService._onNotificationTapped` logic.

`BookingNotificationWatcher`'s polling can be removed once this ships —
it exists only to approximate what real push will do properly.

## Note on the iOS platform folder

This Flutter project currently has no `ios/` directory at all (only
`android/`). Before any of the above can be tested on iOS, someone needs
to run `flutter create --platforms=ios .` from this project root
(normally done on a Mac, since building/signing an iOS app requires
Xcode) to generate it.
