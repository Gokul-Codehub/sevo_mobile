# SEVO Mobile Foundation – status

Implements the "SEVO Mobile Platform Foundation – Development Guide" step by step. Rule 3 of the guide holds everywhere: **a config outage never blocks the app** – only an explicit `maintenance.enabled = true` from the server does.

## Built and tested

| Guide item | What exists | Where |
|---|---|---|
| §4 backend contract | `app_foundation` Django app: MaintenanceWindow, FeatureFlag, RemoteSetting, Announcement, DeviceRegistration, ClientErrorLog, AppConfigAudit (migration `0001`, additive) | `backend/app_foundation/` |
| `GET /api/app/config/` | maintenance + update + flags + settings + announcements in one call; ETag/304; throttled; works with a bad token | `views.py`, `services.py` |
| 5.1 update | the config's `update` block (`none`/`soft`/`force`) is computed from the existing Update Management (`settings_hub`); no second policy table | `services.update_block` |
| 5.7 maintenance | whole app or per module, scheduled start/end, ETA, staff + bypass users exempt; app shows `MaintenanceScreen` with countdown, polls every 30 s, reopens by itself | `foundation_gate.dart` |
| 6.1 remote config | typed settings with compiled defaults; wrong-typed values rejected by the admin API and ignored by the server | `SETTING_DEFAULTS`, `foundation_models.dart` |
| 6.2 feature flags | percentage rollout (stable SHA-256 bucket), min version, platform, allow-list, kill switch; `featureFlagProvider(name)`; unknown flag = on | `services.py`, `foundation_controller.dart` |
| 6.8 announcements | scheduled, version-ranged; delivered in config (UI host not built yet) | `services.announcements_for` |
| 6.7 device registry | `POST/PATCH/DELETE /api/app/devices/…`; reinstall collapses by FCM token; logout detaches the user | `views.py` |
| 5.3 fallback errors | `POST /api/app/errors/` (batched, strict rate limit, fingerprinted) | `views.py` |
| §9 admin | **Mobile App Management → App Control**: maintenance (confirm before ON), flags (confirm kill switch), settings catalogue, announcements, devices, audit log. Super Admin only; every write audited | `frontend/.../MobileFoundationPage.jsx` |
| §3 app side | `lib/core/foundation/`: models, repository (3 s budget, ETag), cache (secure storage), controller (resume refresh ≥ `config_refresh_minutes`), `FoundationGate` mounted in `main.dart` | `lib/core/foundation/` |

Tests: backend `python manage.py test app_foundation` (39) ; Flutter `flutter test test/core/foundation` (18). Update-management + push suites still pass (100 backend tests, 81 Flutter tests in the two folders).

## Decisions taken (guide §10 open items)

* D2: foundation lives **inside this app** (`lib/core/foundation`) for now; extract to the shared `sevo_core` package when the Vendor app adopts it.
* Update management stays at `/api/mobile/version-check/`; `/api/app/config/` embeds the same policy. The earlier `MobileAppDevice` table (update analytics) and the new `DeviceRegistration` overlap – plan: make `DeviceRegistration` the single registry when the Firebase work lands.
* Permission group `mobile_ops` is not created; Super Admin only for now.

## Also built (round 2)

* `FeatureGuard` + Goods Transport route guard, server 409 kill switch (3 tests in `service_requests/tests/test_gt_kill_switch.py`).
* `AnnouncementBanner` (dismissals remembered; banner/info/modal all render as a non-blocking banner so a booking or payment screen is never covered).
* Release-mode error card replaces the red 'please screenshot this' widget; errors are queued by `ErrorReporter` and uploaded to `/api/app/errors/` after the next successful config fetch.

## Also built (round 3): network + session

* `RetryInterceptor` (in `ApiClient`): GET/HEAD, and writes carrying an `Idempotency-Key`, are retried up to 3 times (0.5 s / 1.5 s / 4.5 s + jitter) on network errors and 502/503/504. Never retried: plain writes, anything under a payment path, 4xx, `503 MAINTENANCE`. The short-budget calls (config, version check, error upload) opt out with `skipRetry`.
* `networkStateProvider` (online / offline / serverUnreachable) and a slim amber `ServerUnreachableBanner` when the phone is online but SEVO cannot be reached; the config is re-probed every 30 s until it answers.
* `DeviceIdInterceptor`: every request carries `X-Device-Id` (the anonymous install id; not sent on web).
* `SessionRevokedInterceptor`: a `401 {"code": "SESSION_REVOKED"}` clears tokens, routes to login and shows "You were signed out. Please sign in again." without attempting a token refresh.
* Tests: `test/core/network/network_resilience_test.dart` (11).

## Also built (round 4): push (FCM) client

* `lib/core/push/`: guarded Firebase start (6 s budget; unavailable => push off, app unaffected), token + permission registration to `/api/app/devices/`, re-register on token refresh and sign-in, `detach_user` on sign-out, `APP_UPDATE` pushes trigger the update check, other pushes open their in-app `route` (URLs / `//` rejected), foreground pushes shown locally. `PushGate` is mounted in `main.dart`. Channel `sevo_updates` created.
* Android: `google-services.json` + Google services plugin 4.5.0 configured by the owner; debug APK builds (needs Gradle metaspace > 512 MB on this machine - not changed in the repo).
* Tests: `test/core/push/push_manager_test.dart` (12) - all pass; backend `app_foundation` 40 tests.
* **Not verified on a real device**: no push has been sent yet. Needs the Firebase service-account key on the server (`FCM_SERVICE_ACCOUNT_FILE`).

## Also built (round 5)

* **Device name in admin**: the app sends model + OS (`device_info_plus`) and registers even when Firebase is unavailable; Admin → App Control → Devices shows it, with a **Sign out** button per device.
* **Backend push** (`app_foundation/push.py`): every new inbox row (`service_requests/notifications._inbox`) also pushes to the customer's phones. No-op until the Firebase key is configured; respects `CustomerNotificationPreference` (promotions opt-in); records each attempt in `PushDelivery`; dead tokens cleared; never raises.
* **Forced sign-out** (server side): `DeviceRegistration.revoked_at`; tokens issued before it are refused with `401 {code: SESSION_REVOKED}` for that device (`X-Device-Id`), including the refresh endpoint; web unaffected. Endpoints: admin `POST /api/admin/app/devices/<id>/revoke/`, `.../users/<id>/revoke-devices/`; customer `GET /api/app/sessions/`, `POST .../sessions/<device_id>/revoke/`, `POST .../sessions/revoke-all/`. A data push `force_logout` makes a running app sign out immediately (app handles it).
* **Crash reporting**: `firebase_crashlytics` + Gradle plugin; fatal Flutter/async errors reported, off in debug, remote switch `crash_reporting_enabled`; keys only app/version/build. Debug APK builds.
* Tests: backend `app_foundation` 68; Flutter core folders 61. Not run on a device; no crash/push seen in the Firebase console yet.

**Deploy needed for the above**: backend `migrate` (settings_hub 0021, app_foundation 0001-0003) + env `FCM_SERVICE_ACCOUNT_FILE`; new app build.

## Also built (round 6)

* **Remote settings used**: network timeouts (`api_*_timeout_s`, clamped 5-120 s) and `booking_poll_seconds` now drive the app.
* **Permission manager** (`lib/core/permissions`): explain -> ask -> Open-settings recovery for location/notifications/camera/photos; wired into the two address screens (permission_handler pinned to 12.x - 13.x needs Android SDK 37).
* **Analytics + performance** (`lib/core/analytics`): typed event catalogue, PII sanitizer, automatic `screen_view` via the router observer, `app_open`, API latency per endpoint template; off in debug, remote switch `analytics_enabled`. Funnel events (booking_submitted, payment_*, ...) are defined but **not yet called from the booking/payment screens**.
* **Account screens**: Profile -> *Notification settings* (per-category switches, existing API), *Your devices* (list / sign out one / sign out others), *Send feedback* (`/send-feedback`, new backend `AppFeedback` + admin Feedback tab).
* **Admin**: Overview tab (active devices, push success rate, errors, versions, controls in effect), Feedback tab, Devices Sign-out.
* **Booking reminders**: Celery task `app_foundation.send_booking_reminders` every 10 min -> 24 h and 1 h reminders as inbox rows + push (idempotent, reschedule-aware, respects preferences).
* **Payment failure classification** (cancelled / bank declined / connection lost / timeout / gateway / unknown) with next steps in the payment error message; **rating prompt** (4-5 stars, never first rating, once per 90 days, flag `rating_prompt`); **Groceries** routes behind flag `groceries`.
* Fixed along the way: route/class name clash with the existing post-service `FeedbackScreen`; analytics filter dropping `screen_name`.
* Verified: backend 148 tests (foundation + update + push + GT switch), Flutter 175 tests in the owned folders, debug APK builds. Not verified on a device.

## Not done yet (honest list)

* **Needs outside input**: Play Integrity / App Attest (needs Google Cloud + Apple setup), iOS (Apple account, APNs key), deep-link verification files (`assetlinks.json` needs the release signing SHA-256), real push/crash/analytics delivery (needs the live backend + a build + the service-account key).
* **Deliberately skipped**: a second deep-link handler (go_router + the manifest filters already open https/sevo links; no pending-link-after-login yet), background tasks (workmanager - battery cost, little need), a global 503 maintenance middleware (can lock out the API).
* **Still open**: funnel analytics call sites, flags for the remaining modules (wallet, packers...) and their server-side checks, shared ErrorState/EmptyState/loading widgets and the SevoException family, a LocationManager wrapper (existing geolocator flows left as tuned), localization (ARB + Tamil/Hindi), proactive token refresh, payment-recovery UI beyond the clearer message (retry/other method/cash), operations alert rules (email/chat), release rollout percentage per AppRelease.
* Not committed. Deploy: `migrate` (settings_hub 0021, app_foundation 0001-0004), env `FCM_SERVICE_ACCOUNT_FILE`, Celery beat reload, web build, new app build.
