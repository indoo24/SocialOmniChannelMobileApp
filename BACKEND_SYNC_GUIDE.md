# Backend Sync Guide — what the mobile app still has to build

**Generated:** 19 August 2026
**Mobile reviewed at:** `development` @ `3e9e010`
**Backend reviewed at:** `main` @ `702ee2a` (deployed to `https://scenariomnchnl.tech`)
**Frontend reviewed at:** `main` @ `24106e2`

---

## How to read this

The authoritative description of every backend endpoint is
`SocialOmniChannelBackend/docs/api/openapi.yaml`. It is generated from the code,
validated on every build, and byte-identical between runs — so where this
document and the schema disagree, **the schema is right**. Open it in Swagger at
<https://scenariomnchnl.tech/api/docs/> to see request and response shapes,
required fields, enums, and error bodies.

This file exists because the schema tells you what *exists*, not what the mobile
app is *missing*. That comparison was made mechanically: every `_api.get/post/
patch/put/delete` call in `lib/` was extracted with its path, normalised, and
matched against all 101 backend operations by method **and** path.

---

## 1. Where the app stands

| | Count | |
|---|---:|---|
| Backend operations | 101 | |
| Implemented in mobile | **38** | 37% |
| Missing | **63** | 3 of these are not for any client (see §5) |

The 38 that work cover the daily job of an agent — sign in, read the inbox, open
a thread, read and send messages, take notes, assign, change status/priority/
category, mark read, browse customers and orders, see the dashboard. **The core
loop is done.** What is missing is nearly everything an admin or supervisor does,
plus the intelligence layer the web app shows beside every conversation.

### Already implemented (38)

```
auth          POST /login/  POST /logout/  GET /me/  PATCH /me/
              POST /availability/  POST /password/  GET /csrf/
conversations GET /  GET /counts/  GET /{id}/  GET /{id}/messages/
              POST /{id}/reply/  GET+POST /{id}/notes/  POST /{id}/assign/
              POST /{id}/status/  POST /{id}/priority/  POST /{id}/category/
              POST /{id}/read/
customers     GET /  GET /{id}/conversations/  GET+POST /{id}/facts/
              POST /{id}/facts/{id}/review/  GET /{id}/orders/
orders        GET /  POST /  POST /{id}/confirm/  POST /{id}/cancel/
employees     GET /
teams         GET /
channels      GET /
dashboard     GET /  GET /channels/  GET /performance/
devices       POST /register/  POST /heartbeat/  POST /unregister/
```

---

## 2. Missing features, by priority

Priority is by **how much an agent loses without it**, not by effort.

### P0 — Intelligence: the panel the web app shows and mobile does not

This is the largest functional hole. The web app renders a full intelligence
panel beside every conversation; on mobile the data is simply absent, so an
agent on a phone cannot see lead score, purchase signals, or funnel stage, and
cannot act on them.

| Method | Path | Permission | What it is |
|---|---|---|---|
| `GET` | `/api/conversations/{id}/intelligence/` | any active employee | Lead score, stage, purchase status, sentiment, urgency, summary. **Returns literally `null`** before the analyzer has run — that is not an error and not a zero score. |
| `POST` | `/api/conversations/{id}/intelligence/` | `conversation.refresh_intelligence` | Re-run the analyzer now. No body. Returns the fresh read. |
| `POST` | `/api/conversations/{id}/lead-score/` | `intelligence.override_score` | Set the score by hand; send `{"score": null}` to hand it back to the analyzer. Returns the whole intelligence object. |
| `POST` | `/api/conversations/{id}/confirm-purchase/` | `conversation.confirm_purchase` | An employee ruling on a purchase claim. **The only route that ever produces `AGENT_CONFIRMED`.** |
| `GET` | `/api/conversations/{id}/purchase-confirmations/` | any active employee | History of those rulings. Plain array, not paginated. |

**Mobile work:** an `Intelligence` model (nullable throughout), a repository, and
a panel or tab on the conversation screen. Note `ConversationList.intelligence`
carries a *brief* (`stage`, `lead_score`, `purchase_status`,
`needs_human_review`) while `ConversationDetail.intelligence` carries the *full*
object — same field name, different payload. Model them as two types.

The `intelligence.updated` realtime event is **already handled** by
`realtime_bridge.dart`, so once the fetch exists the panel stays live for free.

---

### P0 — WhatsApp templates: the only way to reopen a closed window

After 24 hours of customer silence WhatsApp accepts nothing but an approved
template. Today a mobile agent hitting that wall simply cannot answer.

| Method | Path | Permission | What it is |
|---|---|---|---|
| `POST` | `/api/conversations/{id}/send-template/` | `conversation.reply` | Send an approved template into an existing thread. Body: `template_name`, `language`, `parameters[]`. |
| `GET` | `/api/integrations/whatsapp/{channel_id}/templates/` | `channel.view` | List templates for a channel, read live from Meta. |
| `POST` | `/api/integrations/whatsapp/{channel_id}/templates/` | `channel.manage` | Submit a new template for Meta review. |
| `POST` | `/api/integrations/whatsapp/{channel_id}/templates/send/` | `channel.view` + `conversation.reply` | Send to **any** customer or phone number, from any connected number — opens a conversation if none exists. |

**Mobile work, minimum useful slice:** on a WhatsApp conversation, fetch the
channel's templates (`conversation.channel_id` is already on the detail
payload), offer only those with `can_send == true`, collect one value per
`variables` placeholder, and POST to `send-template/`.

Points worth respecting because the server enforces them anyway:
- `can_send` is `false` for anything not `APPROVED` **and** for approved
  templates whose components Scenario cannot fill (`unsupported[]` says which).
  Offering those produces a guaranteed 400.
- `rejected_reason` is `""` when nothing is wrong. Meta's literal `"NONE"` is
  already normalised away server-side — never render it.
- `parameters` must have exactly as many entries as `variables`.

---

### P1 — Conversation history and moderation

| Method | Path | Permission | What it is |
|---|---|---|---|
| `GET` | `/api/conversations/{id}/events/` | any active employee | Audit timeline: assignments, status/priority/category changes, notes, purchase rulings. Plain array. |
| `DELETE` | `/api/conversations/{id}/messages/{message_id}/` | `conversation.delete_message` | Soft-delete from the timeline. ADMIN/SUPERVISOR only. Optional body `{"reason": "..."}`. Does **not** unsend on the platform. |

---

### P1 — Categories

`POST /api/conversations/{id}/category/` is already implemented, but there is no
way to fetch the list of categories to choose from — so the picker cannot be
populated.

| Method | Path | Permission |
|---|---|---|
| `GET` | `/api/categories/` | any active employee — **not paginated** |
| `POST` `PUT` `PATCH` `DELETE` | `/api/categories/{id}/` | `team.manage` |

**Mobile work:** at minimum `GET /api/categories/`. The CRUD is admin
configuration and can wait.

---

### P2 — Directory and record management

Read paths exist; nothing can be created or edited from the phone.

| Domain | Missing |
|---|---|
| Customers | `POST /` (create), `GET/PUT/PATCH/DELETE /{id}/` |
| Employees | `POST /` (create), `GET/PUT/PATCH/DELETE /{id}/`, `POST /{id}/activate/`, `GET /online/` |
| Teams | `POST /` (create), `GET/PUT/PATCH/DELETE /{id}/` |
| Orders | `GET/PUT/PATCH/DELETE /{id}/` |

Two of these matter more than the rest:

- **`GET /api/employees/online/`** — currently-available agents, unpaginated.
  `employees_screen.dart` already offers an "online only" toggle, but it filters
  the paginated directory *client-side*, so it can only ever show whoever
  happens to be on the loaded page. This endpoint returns the whole set in one
  call and is the right source for a transfer picker.
- **`GET /api/customers/{id}/`** — the customer detail representation, which
  adds `confirmed_purchase_count` and the full `facts` list that the list
  representation omits.

---

### P2 — Conversions (Meta ads reporting)

| Method | Path | Permission |
|---|---|---|
| `GET` | `/api/conversations/{id}/conversions/` | any active employee |
| `POST` | `/api/conversations/{id}/report-conversion/` | `conversion.report` |

The POST answers **200 for all three outcomes** — read `status` to distinguish
`sent`, `already_reported`, `failed`, `skipped`, `unmatchable`. Treating a
non-`sent` status as failure would show an error for a working button.

---

### P3 — Channel administration

| Method | Path | Permission |
|---|---|---|
| `GET/PUT/PATCH/DELETE` | `/api/channels/{id}/` | `channel.view` / `channel.manage` |
| `POST` | `/api/channels/{id}/mute/` `/unmute/` `/test/` | `channel.manage` |
| `GET` | `/api/channels/providers/` | `channel.view` |
| — | all 8 `/api/integrations/*` connect/disconnect routes | `channel.manage` |

These are desktop-shaped admin tasks (OAuth popups, pasting tokens, Embedded
Signup). **Recommendation: do not build the connect flows on mobile.** Mute,
unmute and test are cheap and genuinely useful on a phone; the rest are not.

---

### P3 — Operational

| Method | Path | Note |
|---|---|---|
| `GET` | `/api/health/` | Unauthenticated. Useful for a connectivity check. |
| `GET` | `/api/metrics/` | Requires `channel.manage`. Admin only. |
| `POST` | `/api/client-errors/` | Named for browsers but generic — a good sink for Flutter crash reports. Authenticated, 20/min, always answers 204. |

---

## 3. Realtime — one gap, and it is a correctness gap

`realtime_bridge.dart` handles nine of the ten events the backend publishes:

```
handled   conversation.assigned      conversation.created
          conversation.status_changed conversation.updated
          intelligence.updated        message.created
          message.deleted             note.created
          presence.changed

MISSING   conversation.access_changed
```

**`conversation.access_changed` is not cosmetic.** Group membership for
`conversation.<id>` is granted at subscribe time, and the channel layer offers
no way to evict a member — so revocation is *cooperative*. The event carries no
content; it means "re-check that you still may watch this thread".

A client that ignores it keeps its subscription after losing access, and keeps
receiving that conversation's events. On the web app this is handled. On mobile
it is not, which means an agent who has a conversation reassigned away from them
continues to receive its messages over the socket.

**Mobile work:** on `conversation.access_changed`, re-fetch
`GET /api/conversations/{id}/`. A **404** means access was lost — unsubscribe,
drop it from the inbox list, and pop the conversation screen if it is open.

---

## 4. Push notifications

### 4.1 Backend — ready, verified in production today

I checked the deployed server rather than the code alone:

| Check | Result |
|---|---|
| `SCENARIO_PUSH_ENABLED` | `true` |
| `SCENARIO_FIREBASE_CREDENTIALS` | `/srv/scenario/secrets/firebase-adminsdk.json` |
| Credentials file | present, `2382` bytes, `scenario:scenario`, mode `400` |
| `firebase_admin` | `7.5.0` installed |
| Firebase Admin initialises | **YES** — project `scenario-d77de` |
| FCM round-trip (dry run) | **YES** — reached Google and got a token-validation response back, which proves auth and connectivity |
| Devices registered | 1 active, with a real 142-char FCM token |

**Nothing on the backend needs configuring. It is live and working.**

### 4.2 One backend bug found and fixed

`send_assignment_push` documents itself as covering "every later handoff", and
this app already handles the `conversation_assigned` payload it produces — but
**only auto-allocation ever called it.** `assign_conversation`, which is what
`POST /api/conversations/{id}/assign/` runs, published its realtime event and
then returned without notifying anyone.

The effect: a supervisor handing a conversation to an agent whose app was
backgrounded reached nobody until that agent next opened the app. The function
was tested from the start; its caller was not.

Fixed in `apps/conversations/services.py` — the push is now queued on commit
when a handoff actually changes the assignee. Deliberately silent for three
cases: releasing a thread, re-saving the same assignee, and claiming a thread
for yourself. Seven tests cover the wiring.

### 4.3 Mobile — code complete, configuration missing

The Flutter side is **built and correct**. `push_service.dart`,
`device_repository.dart` and `push_bridge.dart` cover initialisation, permission,
token refresh, registration on login, heartbeat on resume, unregistration on
logout, and deep-linking a tap to the conversation. `PushDataKeys` matches the
backend payload exactly (`type`, `conversation_id`, values `new_message` and
`conversation_assigned`).

The blocker is that **the Firebase platform config is not in the repository**:

```
android/app/google-services.json      ABSENT
ios/Runner/GoogleService-Info.plist   ABSENT
lib/firebase_options.dart             ABSENT
```

`android/app/build.gradle.kts` applies the Google Services plugin only
`if (file("google-services.json").exists())`, and `PushService.ensureInitialized()`
swallows the failure and sets `_available = false`. So a build made from a clean
clone runs fine with push **silently disabled** — no crash, no error, no
notifications.

A real FCM token is registered against the production server, so whoever built
that APK had the file locally. It is simply not committed, and it is not in
`.gitignore` either — so this is an omission rather than a decision.

### 4.4 What the mobile app must do to finish push

1. **Add the Android config.** Firebase console → project `scenario-d77de` →
   Android app with this app's `applicationId` → download `google-services.json`
   → commit it to `android/app/`. It contains project identifiers and an
   API key restricted by package name and signing certificate; it is not a
   secret, and Google's own documentation expects it in source control. The
   Gradle plugin then applies itself and Firebase initialises.

2. **Add the iOS config** if iOS is in scope: register the bundle id, download
   `GoogleService-Info.plist` into `ios/Runner/`, add it to the Xcode target,
   and upload an **APNs Authentication Key (.p8)** to Firebase → Project
   Settings → Cloud Messaging. Without the APNs key, iOS push fails even with a
   valid plist. `UIBackgroundModes: remote-notification` is already in
   `Info.plist`.

3. **Verify the permission prompt on Android 13+.** `POST_NOTIFICATIONS` is
   already declared. Confirm `requestPermission()` is reached on a fresh install
   and that a denial degrades quietly rather than retrying in a loop.

4. **Handle `not_registered` from the heartbeat.** `DeviceRepository.heartbeat`
   documents it; make sure the caller acts on it by calling `register()` again.
   The backend returns 404 with code `not_registered` when the row is gone —
   for example after the server pruned a token Firebase permanently rejected.
   Without this, a device goes quiet forever after one prune.

5. **Add a foreground notification presenter.** iOS does not display a banner
   for a foreground push, and on Android the OS shows one only because the
   payload carries a `notification` block. `onForegroundMessage` is already
   subscribed; decide whether to show an in-app banner or rely on the socket,
   and make it deliberate rather than incidental.

6. **Then test end to end**, in this order:
   - launch signed in → `POST /api/devices/register/` returns 201/200 with
     `created` true/false;
   - background the app → have someone send a WhatsApp message to a conversation
     assigned to you → banner arrives;
   - kill the app → have a supervisor reassign a conversation to you → banner
     arrives (this is the path that was broken until today's fix);
   - tap the banner → app opens on the right conversation;
   - sign out → `POST /api/devices/unregister/` → no further notifications.

**Not needed:** there is no notification list and no `Notification` model on
either side, by design. Unread state lives on `Conversation.unread_count` and
`GET /api/conversations/counts/`, both already implemented. Push and the socket
are both only "something changed, go look" signals.

---

## 4b. Follow-up flag — shipped on backend and web, not yet on mobile

Added 30 August 2026. Backend and web are live; mobile is the only client
without it.

**Why it was not built here at the same time.** Every file it needs —
`conversation_actions_sheet.dart`, `inbox_filters_sheet.dart`,
`core/models/conversation.dart`, `app_en.arb`, `app_ar.arb` — is a file changed
by the unmerged `development` work. Adding a feature to all five while that work
is in flight would collide with it, so the contract shipped first and the mobile
side is specified here instead.

### What the feature is

An agent marks a conversation for follow-up, optionally with a calendar day. It
stays marked until somebody removes it.

**It is not a reminder.** Nothing schedules, notifies, escalates, reassigns or
unflags — not on the server, and nothing should on the client. No local
notification, no time picker, no recurrence, no "overdue" styling. The date is
stored and displayed, and that is the whole feature. Do not use the word "due".

It is **shared conversation state**, not a private bookmark: Agent A marks it,
the thread moves to Agent B, and B sees the same flag with A still credited.

### API

| Method | Path | Permission |
|---|---|---|
| `POST` | `/api/conversations/{id}/follow-up/` | `conversation.change_category` |

`follow_up_date` is **three-valued**, and this is the part most likely to be got
wrong:

```jsonc
{"is_follow_up": true}                              // keep whatever date is stored
{"is_follow_up": true, "follow_up_date": "2026-09-05"} // set the date
{"is_follow_up": true, "follow_up_date": null}      // clear the date, stay flagged
{"is_follow_up": false}                             // remove the flag entirely
```

Sending the key with `null` is not the same as omitting it. If the client
collapses "empty picker" into "omit the field", a user can never clear a date,
and re-marking a dated conversation silently keeps a date they thought they had
removed.

Returns the full `ConversationDetail`. Never send `follow_up_marked_by` or
`follow_up_marked_at` — the server takes both from the session and ignores them
in the body.

### Read fields (already on both list and detail payloads)

```
is_follow_up             bool
follow_up_date           "YYYY-MM-DD" | null
follow_up_marked_at      ISO datetime | null
follow_up_marked_by_name string   // "" when not flagged
```

Because they are on the **list** representation, the inbox row can draw its
indicator with no extra request.

### Filtering

`GET /api/conversations/?follow_up=true` — server-side, and it composes with
everything else: `&assigned_to=`, `&status=`, `&provider=`, `&view=`, `&search=`.
Paginates normally.

Show **all** flagged conversations the employee may see. It is shared state, so
this is not "my follow-ups".

### Mobile work remaining

1. **`core/models/conversation.dart`** — add the four fields. Keep
   `followUpDate` as a **`String`** (`''` when absent), not a `DateTime`.
   `DateTime.parse("2026-09-05")` is midnight local and re-formatting it can
   move the day; the value is a calendar day and the API speaks `YYYY-MM-DD`.
   Add them to `copyWith` too.

2. **`features/conversations/conversation_repository.dart`** — one method beside
   `changeCategory`:

   ```dart
   Future<void> setFollowUp(
     int conversationId, {
     required bool isFollowUp,
     String? followUpDate,     // null clears
     bool dateProvided = false, // false omits the key entirely
   }) => _api.post<dynamic>(
     '/conversations/$conversationId/follow-up/',
     body: {
       'is_follow_up': isFollowUp,
       if (dateProvided) 'follow_up_date': followUpDate,
     },
   );
   ```

   The `dateProvided` flag is what preserves the three-valued contract.

3. **`features/messages/conversation_actions_sheet.dart`** — a "Mark for
   follow-up" / "Edit follow-up" tile. Use `showDatePicker` (date-only; there is
   no `showTimePicker` here by design), plus "Remove date" and "Remove
   follow-up". Read-only roles see the state without the control.

4. **Inbox row** — a small flag chip showing `Follow-up` or the formatted day.
   Keep it quieter than unread state and the channel badge.

5. **`features/conversations/inbox_filters_sheet.dart`** — a Follow-up toggle
   that sets `follow_up=true`. A toggle, not another radio option, so it
   combines with the existing filters.

6. **l10n** — new strings in `app_en.arb` and `app_ar.arb`, then
   `flutter gen-l10n`. Suggested keys: `followUp`, `followUpDate`,
   `markForFollowUp`, `removeFollowUp`, `removeFollowUpDate`,
   `followUpMarkedBy`. **Have the Arabic reviewed by a native speaker** rather
   than accepting a machine translation into a shipped product.

7. **Realtime** — nothing to add. The change is broadcast as
   `conversation.updated`, which `realtime_bridge.dart` already handles.

8. **Tests** — model parsing of all four fields, the three-valued body
   (especially that an empty picker sends `null` rather than omitting), the
   filter, and the row indicator.

Verify with `flutter analyze` and `flutter test`; both were clean on
`development` @ `3e9e010` before this work.

---

## 5. Deliberately not for mobile

| Endpoint | Why |
|---|---|
| `GET`/`POST` `/api/integrations/meta/webhook/` | Called by Meta. Authenticated by HMAC signature, not by a session. |
| `GET` `/api/integrations/meta/callback/` | OAuth redirect target for a browser. Always answers 302. |

These three are in the 63 but no client should ever call them. The real mobile
backlog is **60 operations**.

---

## 6. Keeping this current

- The contract is `docs/api/openapi.yaml` in the backend repo, browsable at
  <https://scenariomnchnl.tech/api/docs/>. It is committed, deterministic, and
  covered by tests, so it can be diffed between branches to see exactly what
  changed.
- Every response error shares one shape:
  `{"error": {"code", "message", "details"}}` — `details` carries
  `{field: [messages]}` for validation failures, `{}` otherwise.
- Authentication is a session cookie (`scenario_session`), and **unsafe methods
  additionally require an `X-CSRFToken` header** read from the
  `scenario_csrftoken` cookie. This app already does both.
- A resource in another organization answers **404, not 403** — a 403 would
  confirm the row exists. Do not treat 404 on a known id as a bug.
- `GET /api/auth/me/` returns the signed-in employee's full capability list.
  Gate UI on that rather than on role names; the backend re-checks every call
  regardless.
