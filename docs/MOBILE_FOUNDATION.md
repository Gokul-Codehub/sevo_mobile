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

## Not done yet (honest list)

* Kill switch is enforced server-side for **Goods Transport only** (booking create returns 409 `FEATURE_DISABLED`); other modules still need `flag_is_on` checks. A global 503 maintenance middleware was deliberately **not** added (it can lock out the whole API).
* In the app only the Goods Transport route is guarded (`FeatureGuard`, also covers deep links). Home tiles are not hidden individually yet; other modules (groceries, wallet…) need their entry route wrapped the same way.
* **Server side of session revocation**: the backend never returns `SESSION_REVOKED` yet (no `AppSession` model / admin sign-out); the app side is ready and unit-tested. Proactive token refresh (<2 min left) was not added - the existing single-flight 401 refresh already makes expiry invisible. The new interceptors are wired into `ApiClient` but only unit-tested in isolation (not run on a device). PermissionManager, DeepLinkManager, analytics, Crashlytics/FCM/Performance (**need the Firebase project**), integrity, lifecycle, feedback/help, reminders, payment recovery (Phase 2–3).
* Device registration from the app uses the config call only (adds platform/version/build); OS version, model and FCM token are not sent yet (needs `device_info_plus` + Firebase).
* Not committed; backend `migrate` (`settings_hub 0021`, `app_foundation 0001`) and web build not deployed.
