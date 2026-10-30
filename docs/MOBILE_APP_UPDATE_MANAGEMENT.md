# SEVO Mobile App – Update Management

Hybrid update system: the **Django backend** holds the update policy, the **Flutter app** detects its installed build and asks the backend, and **Google Play's In-App Updates API** performs the actual update. SEVO never downloads or installs an APK itself.

## 1. Architecture

```
Admin Panel (React)                Django (settings_hub)                    Flutter app
Version Management page  ──────►  MobileAppVersionConfig (+ audit)
 /admin/mobile-app/…        PATCH /api/mobile/admin/version-configs/…

                                   GET /api/mobile/version-check/  ◄──────  AppUpdateController
                                    (public, no auth)                        │  PackageInfo (installed build)
                                                                             │  Google Play Core (checkForUpdate,
                                                                             ▼   immediate / flexible update)
                                                                  Optional dialog / Mandatory screen
```

Policy (build numbers are the only comparison key; version names are display text):

| Condition (installed build `b`)                      | Result                | UI                       |
|------------------------------------------------------|-----------------------|--------------------------|
| `b >= latest`                                        | `UP_TO_DATE`          | nothing                  |
| `force_update` and `b < minimum_supported_build`     | `UPDATE_REQUIRED`     | mandatory screen         |
| `b < latest` and `update_enabled`                    | `UPDATE_AVAILABLE`    | optional dialog          |
| `b < latest` and not `update_enabled`                | `UP_TO_DATE`          | nothing (prompt off)     |
| no / inactive / invalid configuration                | `NOT_CONFIGURED` / `INVALID_CONFIGURATION` | nothing – app runs normally |

The mandatory rule does **not** depend on `update_enabled`: switching optional prompts off never unlocks an unsupported build. `force_update` is the on/off switch for mandatory enforcement. The client-supplied build is advisory (it only decides which screen is shown); it is not an integrity proof and authorises nothing.

## 2. Backend (customer backend repo: `backend/`)

| File | Purpose |
|---|---|
| `settings_hub/models.py` | `MobileAppVersionConfig`, `MobileAppVersionAudit` |
| `settings_hub/migrations/0020_mobile_app_version_management.py` | schema (additive only) |
| `settings_hub/mobile_version.py` | policy evaluation + validation rules (pure functions) |
| `settings_hub/views_mobile_version.py` | public check + Super Admin API |
| `settings_hub/urls_mobile.py` | routes, mounted at `/api/mobile/` in `quicktims/urls.py` |
| `quicktims/settings.py` | throttle scope `mobile_version_check` (default 60/minute, env `THROTTLE_MOBILE_VERSION_CHECK`) |
| `settings_hub/admin.py` | Django admin registration (audit is read-only) |
| `settings_hub/tests/test_mobile_version.py` | 43 tests |

Model `MobileAppVersionConfig`: `platform`, `application_id`, `channel` (`play_store`/`app_store`), `latest_version_name`, `latest_build`, `minimum_supported_version_name`, `minimum_supported_build`, `update_enabled`, `force_update`, `update_type` (`flexible`/`immediate`), `release_title`, `release_notes`, `store_url`, `is_active`, timestamps, `created_by`/`updated_by`.

Database guarantees: a partial unique constraint allows only **one active row per (platform, application_id, channel)**; a check constraint enforces `minimum_supported_build <= latest_build`.

Validation (model `clean()` and the admin API): application id format, version format, builds ≥ 1, minimum ≤ latest, `store_url` must be `https`, and for Android/Play must be `play.google.com` with `id=<application_id>`; a store URL is **required** when `force_update` is on.

### Public API – `GET /api/mobile/version-check/`

No authentication (an expired/invalid Bearer token does not block it). Throttled.

Query: `platform` (`android`|`ios`, required), `application_id` (required), `build` (non-negative int, required), `version` (display only), `channel` (default `play_store` / `app_store` for iOS).

```json
{
  "success": true,
  "data": {
    "status": "UPDATE_REQUIRED",           // UP_TO_DATE | UPDATE_AVAILABLE | UPDATE_REQUIRED | NOT_CONFIGURED | INVALID_CONFIGURATION
    "update_available": true,
    "mandatory": true,
    "update_mode": "immediate",            // none | flexible | immediate (mandatory is always immediate)
    "latest":            { "version_name": "1.2.0", "build": 20 },
    "minimum_supported": { "version_name": "1.1.0", "build": 15 },
    "release": { "title": "…", "notes": ["…"], "notes_text": "…" },
    "store_url": "https://play.google.com/store/apps/details?id=com.caldim.sevo_customer",
    "installed": { "version_name": "1.0.9", "build": 10 },
    "checked_at": "2026-11-01T09:00:00+05:30"
  },
  "message": "Success."
}
```
`400` with `errors` for a missing/invalid parameter. No matching configuration is **200 `NOT_CONFIGURED`** (the app carries on) – failing closed would lock every user out because of an admin data problem.

### Admin API (Super Admin only; `403` for everyone else, `401` anonymous)

| Method | Path | Purpose |
|---|---|---|
| GET / POST | `/api/mobile/admin/version-configs/` | list / create (created **inactive**) |
| GET / PATCH | `/api/mobile/admin/version-configs/<id>/` | view / update |
| POST | `…/<id>/activate/` | make it the only active row (deactivates the previous one atomically) |
| POST | `…/<id>/deactivate/` | stop serving this policy |
| GET | `…/<id>/audit/` | change history |

Safety rules enforced by the API: enabling or raising a **mandatory** minimum (create, patch of an active row, activate) needs `confirm_mandatory: true`; lowering the `latest_build` of an active configuration (or activating one lower than the active one) needs `correction_reason` (≥ 10 chars, stored in the audit trail). Every create/update/activate/deactivate writes a `MobileAppVersionAudit` row (actor, before/after, reason).

## 3. Flutter (`calservices_customer`)

| File | Purpose |
|---|---|
| `pubspec.yaml` | `package_info_plus ^9.0.1`, `in_app_update ^5.0.0` (no other dependency changed) |
| `lib/features/app_update/domain/app_update_models.dart` | `InstalledApp`, `VersionPolicy`, `PlayUpdateInfo`, `AppUpdateState` |
| `lib/features/app_update/data/app_version_repository.dart` | backend call (8 s timeout, never throws), `PackageInfoReader`, `AppUpdateStore` (remembers a mandatory requirement and "Maybe later" snooze in secure storage) |
| `lib/features/app_update/data/play_update_client.dart` | seam over Play Core In-App Updates (mockable) |
| `lib/features/app_update/domain/app_update_controller.dart` | `AppUpdateController` + providers |
| `lib/features/app_update/presentation/update_widgets.dart` | `OptionalUpdateDialog`, `MandatoryUpdateScreen` |
| `lib/features/app_update/presentation/app_update_gate.dart` | lifecycle + overlay, mounted in `lib/main.dart` |

Behaviour:
* **When it checks:** at startup (background – the splash never waits), on resume (throttled to once per 15 min, immediately while locked), after sign-in (throttled to 1 min). Never on rebuild.
* **Optional:** dialog with installed/latest version and notes. *Update Now* → Play **flexible** update (or immediate when configured); a "downloaded – restart" prompt completes it. *Maybe Later* hides the prompt for that build for 24 h.
* **Mandatory:** a full-screen, non-dismissible screen over the whole app (also blocks Android back). *Update Now* → Play **immediate** update. If Play can't deliver the required build (not published to the device, older than the minimum, no Play Services, sideloaded) the screen says so and offers *Open Play Store* and *check again*. The app unlocks **only** after a re-check shows the installed build really meets the minimum – starting an update is never treated as success.
* **Offline while locked:** the requirement is remembered, so killing and reopening the app offline does not unlock it.
* **Backend down / timeout / invalid answer:** the app opens normally (unless a mandatory requirement is remembered).

## 4. Admin Panel (customer frontend repo: `frontend/`)

| File | Change |
|---|---|
| `src/ui/pages/MobileVersionManagementPage.jsx` | new page (list, current active config, create/edit form, activate/deactivate, confirmations, change history) |
| `src/ui/routes.js` | `mobile_version_management: /admin/mobile-app/version-management` |
| `src/ui/App.jsx` | lazy route inside the Super Admin guard |
| `src/ui/shell/AppShell.jsx` | nav group **Mobile App Management → Version Management** |

Validation mirrors the backend (minimum ≤ latest, https Play URL for the application id, store URL required for mandatory). Activating a mandatory update requires ticking an explicit confirmation that the build is live on Google Play.

## 5. Release procedure

1. Develop; bump `version:` in `pubspec.yaml` (`name+build`, e.g. `1.1.0+15`) – the build number must increase on every Play upload.
2. `flutter build appbundle --release` (signed with the upload key).
3. Upload to an **internal testing** track; install an *older* build from Play on a device and verify the update flow (In-App Updates only work for Play-installed apps).
4. Promote to production; wait until the new version is **visible on Google Play** for the target users (review time, staged rollout %, regional availability).
5. In Version Management create a configuration (`latest` = the new version/build, `minimum` = lowest still-supported build, store URL), keep *Mandatory* **off**, **Activate** → users on older builds get the optional prompt.
6. Monitor. Only when the minimum build is fully available to the affected users: raise `minimum_supported_build`, tick *Mandatory update* and activate with the confirmation.
7. Never force an update right after uploading an AAB.

## 6. Testing

* Backend: `python manage.py test settings_hub.tests.test_mobile_version` and `python manage.py makemigrations settings_hub --check --dry-run`.
* Flutter: `flutter test test/features/app_update` (unit + widget tests with a mocked Play client).
* On device (not automatable): internal-testing track, older build installed from Play → check optional (flexible), mandatory (immediate), cancel, retry, offline, resume. Sideloaded/debug APKs cannot use Play In-App Updates (they get the "Play unavailable" state).

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No prompt although a newer build exists | configuration not **active**, `update_enabled` off, wrong `application_id`/`channel`, or the snooze (24 h) is active |
| Mandatory screen but *Update Now* says unavailable | the build isn't visible to that device on Play yet (rollout/region/account), or the app wasn't installed from Play |
| `NOT_CONFIGURED` | no active row for that app id + platform + channel |
| `INVALID_CONFIGURATION` | an active row fails validation (e.g. edited in the DB); fix it in Version Management |
| Activation refused | missing `confirm_mandatory`, or lower latest build without `correction_reason` |

## 8. Rollback

* **Stop forcing:** open the active configuration → untick *Mandatory update* (needs no confirmation when turning enforcement **off**) or **Deactivate**. Apps re-check on resume/start; a device that remembered a lock clears it on the next successful check.
* **Withdraw a bad release:** create/edit a configuration with the previous build as latest and activate it with a `correction_reason`.
* The feature is additive: removing the app-side gate (one line in `lib/main.dart`) or leaving the backend unconfigured returns the app to the previous behaviour; the migration only adds two tables.

## 9. Phase 2 - adoption analytics, release history, update reminders (push)

**Built and tested (backend 61 tests, Flutter 63 tests):**

* `MobileAppDevice` - one anonymous row per install. The app creates a random id on first use (secure storage) and sends it as `device_id` with each version check; the server stores only its SHA-256. No user, phone or hardware data. Migration `0021` (additive).
* `POST /api/mobile/device/register/` (public, throttled) - registers/refreshes an install and optionally its FCM token.
* Super Admin: `GET .../version-configs/<id>/adoption/` (installs per build, % on latest, outdated, below minimum, reachable by push - active in the last 30 days), `GET .../admin/release-history/`, `GET|POST .../version-configs/<id>/notify/`.
* Reminders: `POST notify` is a **preview by default** (`dry_run`); a real send needs `confirm: true`, an active config with updates enabled, and server Firebase credentials. Each preview/send is logged in `MobileAppUpdateNotification`; dead tokens are cleared.
* Admin page: "Adoption & reminders" and "Release history" modals next to "Change history".

**Server configuration (secret - environment only, never committed):** `FCM_SERVICE_ACCOUNT_JSON` or `FCM_SERVICE_ACCOUNT_FILE` (Firebase service account).

**NOT done / unverified:** the Flutter side of push (firebase_core + firebase_messaging, token registration, handling the `APP_UPDATE` message) needs a Firebase project (`google-services.json` / `GoogleService-Info.plist`). Until it exists no install has a token, so reminders reach 0 devices; sending to real devices has not been tested. Analytics works without Firebase. iOS/Vendor apps and channels need no schema change - add a configuration with that platform/application id/channel.
