# Firebase & FCM for SEVO – Why, How to Set Up, Where We Can Use It

Prepared for: Team Lead review  
Project: SEVO Customer App (`com.caldim.sevo_customer`), Django backend, Admin Panel  
Status: proposal – Firebase is **not yet set up**; the backend side of update reminders is already built and tested.

---

## 1. Why we need FCM

**FCM (Firebase Cloud Messaging)** is Google's free service for sending push notifications to Android and iOS apps, even when the app is closed. It is the standard way to reach a phone, because Android only accepts pushes delivered through Google's own channel.

Without FCM the app can only learn about things when the user opens it. With FCM the server can reach the user.

### Why it matters for Update Management
Today the app checks for updates only when opened or resumed. Users who rarely open the app stay on old builds, including builds with bugs. With FCM:

| Without FCM | With FCM |
|---|---|
| Outdated users find out only when they open the app | Admin can send an "Update available" reminder to outdated installs |
| No way to nudge users before a mandatory cut-off | Reminder can go out days before a mandatory update |
| Admin cannot tell who is reachable | Admin sees how many outdated installs can receive a push |

### Why FCM specifically
- **Free** for sending notifications, with no per-message charge.
- Works for **Android and iOS** with one backend integration (iOS delivers through Apple's service, and FCM bridges to it).
- Targets one device, a group, or everyone, using a per-install token.
- Official Flutter support (`firebase_messaging`).
- No need to run our own push infrastructure.

### What is already built (no Firebase needed to review)
- Backend stores one anonymous record per install and its push token.
- Admin page "Adoption & reminders": shows installs per build, % on latest, outdated count, and how many are reachable by push.
- Reminders default to **Preview** (counts only). A real send needs an explicit confirmation, an active config, and server credentials.
- Everything is tested; real delivery to devices is **not** tested until Firebase exists.

---

## 2. How to create the Firebase account / project

Prerequisite: a Google account. We recommend a **company-owned** Google account (not personal), so the project survives staff changes.

### A. Create the project
1. Go to <https://console.firebase.google.com> and sign in.
2. **Add project** → name it (e.g. `sevo-production`) → continue.
3. Google Analytics for Firebase: optional. Can be left off for push only.
4. Create. Choose the **Spark (free)** plan; FCM does not require the paid plan.
5. Project settings → **Users and permissions** → add the TL / owner as **Owner** so access is not tied to one person.

### B. Register the Android app
1. Project overview → **Add app → Android**.
2. Android package name: `com.caldim.sevo_customer` (must match exactly).
3. Add the **SHA-1 / SHA-256** of the signing keys (debug and the Play upload/app-signing key). Needed for some features; harmless for plain FCM.
4. Download **`google-services.json`** and give it to the developer (placed in `android/app/`).
5. Repeat for the Vendor app (its own package name) if needed.

### C. Register the iOS app (only when we ship iOS)
1. **Add app → iOS**, enter the bundle ID.
2. Download `GoogleService-Info.plist`.
3. In Apple Developer account create an **APNs key (.p8)** and upload it under Firebase → Project settings → **Cloud Messaging**. Requires a paid Apple Developer membership.

### D. Create the server credential (for the Django backend)
1. Firebase → Project settings → **Service accounts** → **Generate new private key**. This downloads a JSON file.
2. This file is a **secret**. Never put it in git, chat, or email.
3. Give it to whoever manages the server and set **one** of:
   - `FCM_SERVICE_ACCOUNT_JSON` – the JSON content as an environment variable, or
   - `FCM_SERVICE_ACCOUNT_FILE` – path to the file on the server (outside the code folder).
4. Make sure the **Firebase Cloud Messaging API (V1)** is enabled for the project (Google Cloud console → APIs).

### E. What we need back from the TL / owner
- Firebase project created under the company account.
- `google-services.json` (Android app config – not secret, but keep it internal).
- Service-account JSON delivered securely to the server admin.

Then development work needed: add `firebase_core` and `firebase_messaging` to the Flutter app, request notification permission (Android 13+), register the token with `/api/mobile/device/register/`, and open the update check when an `APP_UPDATE` push arrives. Estimated effort is small because the backend is done.

---

## 3. Where else we can use Firebase

### FCM (push notifications) – most relevant
| Use | Example |
|---|---|
| App update reminders | "SEVO 1.2.0 is available" |
| Booking status | Technician assigned, on the way, work started/completed |
| Payment | Advance paid, receipt ready, refund processed |
| Quote / scope approval | "Your quote is ready – approve to proceed" |
| Order & delivery | Grocery order packed, out for delivery |
| Offers & coupons | New coupon, expiring coupon (with opt-out) |
| Slot / reminder | "Your technician arrives tomorrow at 10:00" |
| Vendor app | New job request, payout processed |

Note: an unused `CustomerDevice` model already exists in the backend for user-bound tokens; logged-in notification features could reuse that design.

### Other Firebase products worth considering
| Product | Use for SEVO | Priority |
|---|---|---|
| **Crashlytics** | Real-time crash reports from customer devices; far better than waiting for user complaints | High |
| **Analytics** | Funnel data: where users drop off in booking/checkout | Medium |
| **Performance Monitoring** | Slow screens and slow API calls on real devices | Medium |
| **Remote Config** | Change app values (feature flags, texts) without a new release; could complement our admin-controlled settings | Medium |
| **Dynamic/App Links alternatives** | Deep links from messages into the app (Firebase Dynamic Links is discontinued – use Android App Links/Universal Links) | Low |
| **App Distribution** | Send test builds to testers before Play release | Low |
| **App Check** | Helps block fake clients calling our APIs | Later |

We do **not** need Firebase Auth, Firestore, or Hosting – we already have our own Django backend, database and login.

---

## 4. Privacy, security and risks

- Push token and install id are anonymous; the install id is stored only as a hash. No phone number, name or hardware ID is used for update analytics.
- Tokens change over time; the server removes dead tokens automatically.
- Users can disable notifications in Android settings; those users simply are not reachable. Android 13+ asks for permission – we should ask at a sensible moment, not at first launch.
- Sending to real users is protected: preview first, confirmation checkbox, only for an active config.
- The service-account JSON is the one sensitive item. Rotate it if it is ever exposed.
- Dependency on Google services: devices without Google Play services (some China-market phones) will not receive pushes. In-app update checks still work for them.
- Marketing pushes need user opt-out to respect consent rules; update and transactional notices are lower risk.

## 5. Cost
FCM sending is free. Crashlytics, Analytics, Remote Config and App Distribution are also free on the Spark plan. Cost arises only if we later add paid products (e.g. Blaze-plan features); not required for the above.

## 6. Decision requested from the TL
1. Approve creating a company-owned Firebase project (`sevo-production`).
2. Nominate who owns the Google account and who stores the server credential.
3. Confirm scope: FCM for update reminders now; Crashlytics next; booking/payment notifications as a follow-up phase.
4. Confirm iOS timing (needs Apple Developer membership and APNs key).

## 7. Next steps once approved
1. Create project and register the Android app → hand over `google-services.json`.
2. Set the server credential on the backend environment.
3. Add the Flutter integration; test on a real device: permission, token registration, preview, real send, tap-to-open.
4. Release, then use Admin → Version Management → **Adoption & reminders**.

Related document: `docs/MOBILE_APP_UPDATE_MANAGEMENT.md` (section 9).
