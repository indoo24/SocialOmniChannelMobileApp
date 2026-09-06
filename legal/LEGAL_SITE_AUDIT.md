# Legal Website Audit — Scenario OmniChannel

Companion document to the site in this folder (`legal/index.html`, `privacy-policy/`, `data-deletion/`, `terms/`). Explains exactly what came from where, so the content can be trusted and maintained without re-deriving it.

**Sources used:**
- Live pages, fetched and reproduced in full: `https://scenariomnchnl.tech/privacy-policy/`, `/data-deletion/`, `/terms/` (all dated effective August 5, 2026).
- Direct review of this repository's Flutter source: `pubspec.yaml`, `lib/core/**`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `android/app/build.gradle.kts`.
- Two backend facts supplied directly by the app owner (Meta Conversions API behavior; employee deletion = deactivation) — see §6 for how these are sourced, since the backend's own code is not in this repository.

---

## 1. Existing information imported from the live pages

Reproduced in full, unchanged in substance, in the new site:

- **Privacy Policy** — all 15 original sections (Information We Process; How We Use Information; Meta Platform Data; WhatsApp and Messaging Data; Legal Bases and Business Instructions; How We Share Information; Data Retention; Security; Access Tokens and Credentials; International Processing; Your Choices and Rights; Data Deletion; Children's Privacy; Changes to This Policy; Contact), effective date, and privacy contact.
- **Data Deletion** — the full request process (email + subject line + identifying details), the verification/retention-exception language, the Meta-disconnect note, and the response-timeframe language.
- **Terms of Service** — all 13 original sections, effective date, and contact block.
- Company identifiers used throughout: contact email `Mohamed.gad0487@gmail.com`, website `scenariodm.com`, copyright line `© 2026 Scenario`.

Nothing from the live pages was removed. Where mobile content was added inside an existing section (e.g., Privacy Policy §1, §2, §8–10, §13), the original paragraphs/bullets remain intact and the additions are visually marked with a **Mobile App** badge so a reader can tell what's new.

## 2. Mobile-app information added, verified from the Flutter code

| Fact | Verified in |
|---|---|
| Session-cookie + CSRF authentication, same backend as the web app, no self-registration | `lib/core/auth/auth_repository.dart`, `lib/core/api/api_client.dart` |
| Employee account fields (email, name, title, phone, role, permissions, avatar, availability) | `lib/core/models/employee.dart`, `auth_repository.dart` |
| Passwords sent once over encrypted connection, never stored on device | `auth_repository.dart` (`login()`), `Environment` (TLS enforcement) |
| HTTPS/WSS enforced in release builds, cannot be downgraded | `lib/core/config/environment.dart` (`isReleaseBuild`, `useTls`) |
| Secure OS storage for session/email/device-id/theme/locale (Keychain / EncryptedSharedPreferences) | `lib/core/storage/secure_store.dart` |
| App-generated installation ID — `Random.secure()`, 128-bit, hex-encoded, **not** derived from hardware | `secure_store.dart` (`_generateId()`) |
| Session cookie persisted to app-sandboxed local storage, cleared on logout | `lib/core/providers.dart` (`buildCookieJar`), `auth_repository.dart` (`clearLocalSession`) |
| Firebase Cloud Messaging: push token + platform registered/heartbeat/unregistered with backend | `lib/core/notifications/push_service.dart`, `device_repository.dart`, `push_bridge.dart` |
| No Firebase Analytics, no Firebase Crashlytics | `pubspec.yaml` dependency list (only `firebase_core`, `firebase_messaging`) |
| No advertising SDK, no third-party analytics SDK | `pubspec.yaml` dependency list |
| Crash/error reports sent to Scenario's own backend (`/api/client-errors/`), not a third-party service | `lib/core/logging/client_error_reporter.dart` |
| Android permissions: only `INTERNET`, `POST_NOTIFICATIONS` | `android/app/src/main/AndroidManifest.xml` |
| No camera, microphone, contacts, or location permission or plugin | `AndroidManifest.xml`, `ios/Runner/Info.plist` (no usage-description keys), `pubspec.yaml` (no such plugin) |
| Log redaction: emails, tokens, and search terms are not written to device logs in plain text | `lib/core/logging/app_log.dart` |
| Customer/conversation data displayed is fetched from the backend, not collected from the device | `lib/core/models/customer_detail.dart`, `conversation.dart`, `message.dart` |

## 3. Third-party services detected

- **Google — Firebase Cloud Messaging.** Confirmed in mobile code (`firebase_core`, `firebase_messaging`). Used only for push delivery; no Analytics/Crashlytics dependency present.
- **Meta platform APIs (WhatsApp Business Platform, Facebook, Instagram, Messenger).** Confirmed by the live Privacy Policy (§3, §4) — server-side, not mobile-app code.
- **Meta Conversions API.** Confirmed present but disabled by default, per the app owner (backend-side; see §6 for sourcing).
- **No** ad network, **no** third-party analytics SDK, **no** third-party crash-reporting SDK, **no** social-login SDK, found in either the live pages or the mobile codebase.

## 4. Data collected/processed by the mobile app

- Employee: email, password (in transit only), name, title, phone, role, permissions, avatar, availability.
- Device/app: FCM push token, platform (Android/iOS), app-generated installation ID, crash diagnostics (error message, stack trace, section, screen path).
- Session: session cookie, CSRF token (both server-issued, stored locally, cleared on logout).
- Customer/business data (viewed, not device-collected): name, email, phone, city, country, preferred language, messages, notes, tags, purchase confirmations — sourced from the Organization's backend.
- Standard technical/connection metadata (IP address, timestamps) inherent to any HTTP/WebSocket API traffic.

## 5. Data shared with third parties

- **Google (Firebase Cloud Messaging)** — push token + platform, for notification delivery only.
- **Meta** — per the live policy, Meta platform identifiers/messages/metadata needed to operate connected integrations (§3–5 of the Privacy Policy); additionally, SHA-256 hashed phone/email only, via the Meta Conversions API, **only if a business has enabled it** (§4 of the new Privacy Policy — see §6 below for sourcing).
- **No sale** of personal information or conversation data, per the live policy — preserved unchanged.
- The mobile app itself does not add any new third-party data-sharing relationship beyond Firebase.

## 6. Remaining UNKNOWN / NEEDS CONFIRMATION items

Not published on the site (the public pages state only what's verified), tracked here instead:

- **Legal entity name and registered postal address** — not stated on any of the three live pages or requested from the app owner; still needed for full GDPR/CCPA controller identification and some app-store developer-identity requirements.
- **Data Protection Officer**, if applicable — not stated live.
- **Named hosting/infrastructure providers** — the live policy says "technology and hosting providers" without naming them.
- **Concrete retention periods** (a number of days/months per data type) — the live policy intentionally uses "as long as reasonably necessary"; that wording was preserved as-is rather than replaced with an invented number.
- **Whether the backend encrypts data at rest** — not stated live, not verifiable from the mobile repository.
- **Two facts in this site were supplied directly by you (the app owner), not independently verified against backend source code, because the backend repository was not available to this review:**
  1. Meta Conversions API is implemented but disabled by default, and — when enabled — sends only SHA-256-hashed phone/email (never raw contact data, IP, customer ID, or cookie identifiers), for ad-delivery optimization.
  2. Deleting a Scenario employee account currently means deactivation (`is_active = false`) with the record retained, not permanent erasure.

  Both are written into the public pages as stated, per your instruction. If backend code ever contradicts either claim, the corresponding page (`privacy-policy/index.html` §4, `data-deletion/index.html` "Scenario Mobile App Employee Accounts") needs updating to match.
- **iOS Firebase config is missing.** `android/app/google-services.json` exists, but no `GoogleService-Info.plist` was found under `ios/` — iOS push notifications are not yet functional. This doesn't affect the policy's accuracy (it correctly describes what the Android/configured side does) but is worth fixing before an iOS release, since Play/App Store review sometimes checks that declared functionality actually works.
- **No in-app link to these legal pages exists yet.** Nothing under `lib/` links to a privacy policy or terms page from within the app itself — recommend adding one (e.g., in `lib/features/settings/settings_screen.dart`) pointing at `https://scenariomnchnl.tech/privacy-policy/`.
- **Production API host** — `lib/core/config/environment.dart` requires `SCENARIO_API_HOST` via `--dart-define` for a `production` build (intentionally empty by default); confirm the release pipeline actually points at `scenariomnchnl.tech` (or wherever this site is ultimately hosted) so the Privacy Policy's description of the backend matches the shipped app.

## 7. Google Play Data Safety items this Privacy Policy supports

| Play Data Safety category | Supported by this policy | Section |
|---|---|---|
| Personal info — Name, Email, Phone | Yes | Privacy Policy §1.1, §1 |
| Messages — other in-app messages | Yes | Privacy Policy §1, §5 |
| Financial info — purchase history | Yes | Privacy Policy §1 |
| Device or other IDs | Yes — collected, shared with Google for app functionality | Privacy Policy §1.2, §6.3, §6.4, §8 |
| Diagnostics — crash logs | Yes — collected, not shared with a third party | Privacy Policy §1.2, §6.5 |
| Data shared with Meta (hashed, advertising) | Yes — conditional on a business enabling the feature | Privacy Policy §4, §8 |
| "Data is encrypted in transit" | Supported | Privacy Policy §6.2, §10 |
| "You can request data be deleted" | Supported | Privacy Policy §14, full `data-deletion/` page |
| Location, Camera, Microphone, Contacts | Correctly declarable as **not collected** | Privacy Policy §6.6 |
| No third-party advertising/analytics SDK in the app | Supported | Privacy Policy §6.7 |

Use this table alongside the actual Play Console form — Google's category names/groupings shift periodically, so re-check against the live form rather than this table's exact wording.

## 8. Deployment instructions

See `README.md` in this same folder for the full walkthrough. Short version:

**Give the entire `legal/` folder to the backend developer.** It is a complete, relative-linked static site (`index.html`, `privacy-policy/index.html`, `data-deletion/index.html`, `terms/index.html`, `assets/`) with no build step and no server-side requirement. They should deploy it so it's reachable at the same paths the live site already uses (`/`, `/privacy-policy/`, `/data-deletion/`, `/terms/` on `scenariomnchnl.tech`), replacing whatever currently serves those routes, so existing links (Play Console, Meta app review, etc.) keep working unchanged.

---

## Verification performed before finishing

- ✅ All three documents are linked from the homepage, from each other's nav bar, and from each other's footer.
- ✅ The Privacy Policy contains the mobile-app data flows listed in this task (auth, session cookie, secure storage, installation ID, FCM, push token sharing, employee account info, API communication, crash reporting, and explicit "not collected" statements for camera/mic/contacts/location and analytics/crashlytics/ads).
- ✅ The Data Deletion page's employee-account section describes deactivation (`is_active = false`, record retained), not permanent erasure, matching what you specified.
- ✅ The Terms page preserves all 13 original sections; only additive mobile-app clarifications were made (§1, §3, §5, §6, §8, §9).
- ✅ Checked all four HTML pages for placeholder text — none found; the real contact email (`Mohamed.gad0487@gmail.com`) and website (`scenariodm.com`) are used consistently everywhere.
- ✅ No data collection claim was added that isn't backed by either the live pages or the source-code citations in §2 above.
- ✅ The site uses only relative links and local assets (one CSS file, one inline SVG icon) — no external dependencies, so it deploys as-is to any static host or path.
