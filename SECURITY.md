# Security

Notes for anyone building, releasing or changing this app. The reasoning behind
each control lives in a comment next to the code that implements it; this file
is the map.

## The one assumption everything else follows from

The app runs on a device its user controls. Assume an attacker can extract the
APK, decompile it, hook it at runtime, read its storage and intercept its own
traffic. Nothing shipped inside the binary is secret.

So the client's job is not to hold secrets. It is to hold *as little as
possible*, for *as short as possible*, and to make sure that a compromised
device costs the organisation one agent's session rather than the customer
database. Authorisation, visibility scoping and rate limiting are the backend's
job, and no amount of client hardening substitutes for them.

## Building a release

Release builds need a signing keystore. This is not optional and there is no
fallback — the project used to sign releases with the Android SDK's debug key,
which is public and identical on every machine, meaning anyone could modify the
APK, re-sign it, and have Android accept the result as the same app.

```bash
cp android/key.properties.example android/key.properties
# create the keystore (the example file has the keytool command), fill in paths
```

`key.properties` and `*.jks` are git-ignored. **Back the keystore up.** Losing it
means never being able to ship an update under this app's identity again.

Then:

```bash
flutter build apk --release \
  --dart-define=SCENARIO_ENV=production \
  --dart-define=SCENARIO_API_HOST=your.backend.host \
  --obfuscate \
  --split-debug-info=build/symbols \
  --strip
```

`--obfuscate --split-debug-info` renames Dart symbols and writes the mapping to
`build/symbols`. Keep that directory for the release — without it, crash reports
are unreadable. `--strip` drops the DWARF debug info the build otherwise warns
about. Obfuscation is defence in depth: it raises the cost of reading the app's
structure and protects nothing on its own.

Debug and profile builds need none of this and are unchanged.

## What the build mode changes

`SCENARIO_ENV` selects a backend. It does **not** grant trust — those were
conflated once, and because the environment defaults to `development`, a
release build made without `--dart-define` counted as a development build and
accepted any certificate for the default host.

Every relaxation is now gated on `kReleaseMode` as well:

| | debug / profile | release |
|---|---|---|
| Accept an unverified TLS certificate for the dev host | if `SCENARIO_ENV=development` | never |
| Cleartext `http://` / `ws://` | if `SCENARIO_USE_TLS=false` | never — forced to TLS |
| API host printed on the login screen | yes, in development | never |
| `ngrok-skip-browser-warning` header | yes, in development | never |
| Verbose realtime + API logging | yes | compiled out |

A release build pointed at a self-signed dev server will fail its handshake.
That is deliberate. Use a debug build, or install the CA on the device.

## Where the credential lives

The backend authenticates with a Django session cookie, so the cookie **is** the
credential. It is persisted by `PersistCookieJar` as files in the app's
documents directory.

That means:

* `android:allowBackup="false"`, plus `backup_rules.xml` and
  `data_extraction_rules.xml` excluding the cookie directory. Otherwise Google
  cloud backup and device-to-device transfer copy a live session onto another
  phone.
* Signing out and any 401 both clear the jar. A rejected cookie is still a
  credential sitting in a file.

## Logging

`debugPrint` is **not** stripped from release builds — it compiles to `print`,
which lands in logcat. Route diagnostics through `core/logging/app_log.dart`:

* `AppLog.debug` — development only, compiled out of release.
* `AppLog.warn` — kept in release; use only for messages naming no data.
* `AppLog.redact` / `redactEmail` / `redactUri` — for anything else.

Never log a session cookie, an FCM token, a customer identifier, message text,
a full request URI (the query string carries the inbox search term), or a
response body.

## Adding a screen

If it displays conversation content or customer PII, wrap its route in
`sensitive(...)` in `app/router.dart`. That sets Android's `FLAG_SECURE` while
the screen is mounted, keeping it out of screenshots and the app-switcher
snapshot.

## Parsing anything the app did not produce

Use the helpers in `core/utils/json_safe.dart` rather than casting. A cast is
not a check: `json['id'] as int` throws `TypeError` on a string, and `TypeError`
is not `ApiException`, so none of the repository or controller handlers catch
it. Server data, WebSocket payloads and push payloads are all untrusted input,
including from a backend you trust — a serializer change breaks a cast exactly
as effectively as an attacker would.

Server-supplied URLs go through `core/utils/safe_url.dart` before being fetched.
Customer avatars come from WhatsApp and Instagram, which means they are
ultimately customer-controlled.

## Known gaps

* **iOS app-switcher snapshots are unprotected.** iOS has no `FLAG_SECURE`
  equivalent; it needs a native overlay on `sceneWillResignActive` in
  `SceneDelegate.swift`. The Dart API is platform-agnostic already, so wiring it
  needs no call-site changes.
* **`flutter_secure_storage` is on 9.2.4**, two majors behind 11.0.0. The
  upgrade changes the Android options API and needs device testing on both
  platforms.
* **The Firebase Android API key** in `google-services.json` is public by
  design, but should be restricted in the GCP console to this package name plus
  the release signing certificate's SHA-1.
* **No certificate pinning.** Deliberate: with Let's Encrypt certificates and
  their 90-day rotation, pinning turns a routine renewal into an app-update
  emergency. Revisit if the backend moves to a long-lived certificate with a
  managed rotation process, and only with a backup pin.
