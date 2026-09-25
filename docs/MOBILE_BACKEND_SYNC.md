# OmniChannel Backend ↔ Mobile Sync Contract

**This document is the canonical coordination file for backend changes that may
require mobile work.** A mobile developer should be able to open it and answer:
what changed, when, in which endpoint or event, whether it breaks anything, and
what the app has to do about it.

**Source of truth, in order:**

1. The running backend and its OpenAPI document — `docs/api/openapi.yaml`,
   also served live at `GET /api/schema/`.
2. This document.
3. The mobile implementation.

If this document and OpenAPI disagree, **OpenAPI and the backend win** and this
document must be corrected. OpenAPI says *what the contract is*; this document
says *what changed and what mobile must do about it*. It is not a second API
reference.

- Last full audit: **2026-09-14**, backend `ede15e0`, mobile `development` @ `51a428f`.
- Production: `https://scenariomnchnl.tech` (API `/api/`, realtime `wss://…/ws/inbox/`).

---

## Contents

1. [Change classification](#change-classification)
2. [Authentication & Security Contract](#authentication--security-contract)
3. [API conventions](#api-conventions)
4. [Realtime contract](#realtime-contract)
5. [Known contract issues](#known-contract-issues)
6. [Mobile Implementation Queue](#mobile-implementation-queue)
7. [API inventory (mobile-relevant)](#api-inventory-mobile-relevant)
8. [Changelog](#changelog)
9. [Maintenance rule](#maintenance-rule)

---

## Change classification

Every changelog entry carries one **compatibility** label and one **impact** label.

| Label | Meaning |
|---|---|
| **BREAKING** | An app built before the change can fail or misbehave: a removed or renamed field or endpoint, a newly required request field, a changed type or enum value, a changed status code for an existing flow. |
| **BACKWARD COMPATIBLE** | Old apps keep working: a new optional field, new endpoint, new enum value on a field the app already tolerates, new event type. |
| **REQUIRED** | Mobile must implement it for correct behaviour: data would be wrong, stale or lost without it. |
| **RECOMMENDED** | Mobile should implement it for parity or daily usability; nothing is broken without it. |
| **OPTIONAL** | Nice to have on mobile; the product works without it. |
| **WEB-ONLY** | Deliberately not planned for mobile (admin tooling, exports). |
| **BACKEND-ONLY** | No client-visible contract change; listed only when a mobile developer might otherwise ask. |

Examples: a new optional response field is *BACKWARD COMPATIBLE / RECOMMENDED*;
making a request field required is *BREAKING / REQUIRED*; a new admin endpoint is
*OPTIONAL* or *WEB-ONLY* depending on the product decision.

**Mobile status** on each entry: *Not implemented* · *Partial* · *Implemented*.

---

## Authentication & Security Contract

Verified against code and production configuration on 2026-09-14. No secrets or
real credentials appear here.

### Mechanism

**Django session cookie + CSRF token.** Not JWT, not DRF tokens, not OAuth for
employees, no static API key. The API's only authentication class is DRF
`SessionAuthentication`; `djangorestframework-simplejwt` and
`rest_framework.authtoken` are not installed.

| Credential | Format | Issued by | Stored server-side | Stored on mobile | Sent as |
|---|---|---|---|---|---|
| `scenario_session` cookie | Opaque random session key | `POST /api/auth/login/` (Django `login()` + `cycle_key()`) | Redis cache (`SESSION_ENGINE=cache`); session data holds the employee id and a password-hash fingerprint | Cookie jar (`PersistCookieJar`) | `Cookie:` header, HttpOnly, Secure, SameSite=Lax |
| `scenario_csrftoken` cookie | Opaque token | `GET /api/auth/csrf/`, also returned in the login body | Derived from the session | Cookie jar | `X-CSRFToken:` header on POST/PUT/PATCH/DELETE (plus `Referer` over HTTPS) |

### Identity: the credential identifies one employee session

Each session belongs to **one employee on one login** (option C/E in the audit
question): it is not shared by users or organizations and carries no claims.
Every request resolves identity server-side from the database:

```
Cookie scenario_session
  → Redis session → employee id (+ password-hash fingerprint check)
  → accounts.Employee (AUTH_USER_MODEL — the employee *is* the user)
  → employee.organization_id  — tenant for every query
  → employee.role             — read from the row on this request
  → permissions_for_role(role) — capability set, computed per request
```

Nothing is trusted from the client: organization, role and permissions are never
read from a request parameter, header or token claim. A role change or
deactivation takes effect on the employee's **next request**.

### Lifetimes

| | Value |
|---|---|
| Session lifetime | 12 hours, **sliding** (`SESSION_SAVE_EVERY_REQUEST`): every authenticated request renews it |
| Access/refresh split | None. There is no refresh token and no refresh endpoint |
| Expired session | The next request is rejected (see error codes below); the app must sign in again |
| Session fixation | Session key rotated on login |

### Logout and revocation

| Event | Effect |
|---|---|
| `POST /api/auth/logout/` | Flushes **this** session server-side and sets the employee OFFLINE. Other devices' sessions stay valid. |
| Employee changes own password (`POST /api/auth/password/`) | Current session kept; every **other** session fails its password-hash check on its next request. |
| Admin sets a new password (`PATCH /api/employees/{id}/`) | All of that employee's sessions fail on their next request. |
| Employee deactivated | Every REST request is refused immediately (`IsActiveEmployee` checks `is_active` on every request). Sessions are not deleted: if the employee is reactivated within 12 hours, an old session works again. See [Known contract issues](#known-contract-issues) for open realtime sockets. |
| Redis restart with empty data | Everyone is signed out. |

### Permissions

**Role-based, expressed as permissions.** `ROLE_PERMISSIONS` maps each role
(`ADMIN`, `SUPERVISOR`, `TEAM_LEADER`, `AGENT`, `QA`) to capabilities such as
`conversation.reply`, `conversation.assign_any`, `channel.manage`,
`team.manage`, `employee.manage`, `customer_field.manage`, `crm.export`.
Enforced on the server:

- **ViewSets and APIViews:** `HasPermission` with `required_permission` or
  `required_write_permission` on the view.
- **Function views:** `require_permission(Perm.X)`.
- **Service layer:** rules such as `can_assign_to` and ownership checks.

`GET /api/auth/me/` returns `permissions` and `visibility_scope` **for UX only**.
Hiding a button on mobile is presentation: the backend rejects the request
regardless.

### Tenant isolation

The organization always comes from the signed-in employee, never from the
payload:

- `OrganizationScopedViewSet` filters every queryset by
  `request.user.organization_id` and sets it on create.
- Conversation-derived resources use `Conversation.objects.visible_to(employee)`,
  which also applies role scope (`ALL`, `TEAM`, `ASSIGNED`).
- Foreign keys in payloads (team, assignee, channel, schedule) are looked up
  inside the caller's organization.
- Cross-tenant ids answer **404**, never 403, so a response never confirms that
  a row exists.

### Realtime authentication

- `wss://scenariomnchnl.tech/ws/inbox/`, authenticated by the **same session
  cookie** sent in the `Cookie` header (Channels `AuthMiddlewareStack`).
- An `Origin` header is required and must match an allowed host (mobile sends
  `https://scenariomnchnl.tech`).
- No token in the URL or query string.
- On connect the server re-reads the employee from the database. Close code
  `4401` means unauthenticated; `4403` means deactivated or without an
  organization.
- Groups are namespaced `org.{organization_id}.…`, so cross-organization delivery
  is impossible by construction.
- Group membership is computed **at connect time** (see Known contract issues).

### Transport

- HTTPS only; HTTP answers `301` to HTTPS. HSTS, `X-Frame-Options: DENY` and
  `nosniff` are set. WSS only.
- Mobile release builds force TLS and keep full certificate validation. The
  development-only `badCertificateCallback` (`DevTlsOverrides`) is compiled in
  but only installed in non-release development builds, for the configured dev
  host. iOS ATS `NSAllowsArbitraryLoads` is false; Android `allowBackup` is false.

### CSRF and CORS

- **CSRF applies to mobile**, because mobile authenticates with a cookie: every
  unsafe method must send `X-CSRFToken`. Prime it with `GET /api/auth/csrf/`
  before the first unsafe request.
- `CSRF_TRUSTED_ORIGINS` is the production web origins only.
- **CORS:** no cross-origin browser origins are allowed (the SPA is same-origin).
  CORS does not apply to the native app.

### Rate limits

| Scope | Rate | Keyed by |
|---|---|---|
| `login` | 10/min | client address (see Known contract issues) |
| `anon_sustained` | 60/min | client address |
| `user_sustained` | 600/min | employee |
| `message_send` | 120/min | employee |
| `crm_export` | 10/min | employee |
| `client_error` | 20/min | |
| `whatsapp_status_check` | 10/min | |

There is no password-reset or OTP endpoint. Login errors do not reveal whether
an address exists.

### Mobile storage expectation

The session cookie is a live credential. It must live in OS-protected storage
(Keychain/Keystore-backed, excluded from backups) and be deleted on logout and on
session expiry. It must never be logged. See Known contract issues for the
current state.

### Auth error codes

| HTTP | `error.code` | Meaning | Mobile handling |
|---|---|---|---|
| **403** | `not_authenticated` | No session, session expired, or session invalidated | **Treat as session expired**: clear cookies, go to login. It is *not* a permission error, and it is 403, not 401 (see Known contract issues). |
| 403 | `permission_denied` | Signed in, but the role lacks the capability | Show "not allowed"; stay signed in. |
| 400 | `invalid` | Login with wrong credentials (same response for unknown address or deactivated account) | Show "invalid credentials". |
| 429 | `throttled` | Rate limited | Back off. |
| 403 | `permission_denied` with a message starting `CSRF Failed` | Unsafe method without a valid `X-CSRFToken` | Re-prime the CSRF token (`GET auth/csrf/`) and retry once. |

---

## API conventions

| Topic | Contract |
|---|---|
| Base path | `/api/`. No version prefix; the OpenAPI document is the version. |
| Authentication | Every endpoint needs a session except `auth/csrf`, `auth/login`, `health`, provider webhooks and OAuth callbacks. |
| Pagination | Page-number pagination. `?page=` and `?page_size=` (default 25, max 100). Envelope `{count, page, page_size, total_pages, next, previous, results}`. A few endpoints are documented as plain arrays (notes, events, order history). |
| Timestamps | ISO 8601 with offset; stored and served in UTC. Dashboard periods resolve calendar days in the organization's timezone (`organization.timezone`). |
| IDs | Integer `id` for every row, used in URLs and foreign keys. UUID `public_id` on most models, for external references. Attachment content URLs use the attachment's UUID. |
| Enums | `UPPER_SNAKE` values (`OPEN`, `WHATSAPP`, `AGENT`). A few lower-case exceptions are documented per field (for example team responsibility `scope`: `all`/`selected`). Clients must tolerate unknown enum values. |
| Errors | Always `{"error": {"code": str, "message": str, "details": object}}`. |
| Validation errors | `400`, `code: "invalid"`, `details` = `{field: [messages]}`. Domain rule refusals are `400` with the exception's default code (for example `message_send_error`, `assignment_error`, `channel_not_allowed_for_employee`). |
| Not found and cross-tenant | `404`, `not_found`. |
| Conflicts | `409` (`conflict`, `ownership_conflict`). |
| Uploads | Two steps. `POST /api/conversations/{id}/attachments/` (multipart `file`, optional `is_voice`, `duration_ms`) returns a draft; then `POST …/reply/` with `attachment_ids`. Size and type limits come from the conversation's `media_capabilities`. |
| Media download | `GET /api/attachments/{public_id}/content/` with the session cookie; supports `Range` (206). |
| Idempotent sends | Send `client_message_id` (UUID) on reply; a retried request with the same id returns the existing message instead of sending twice. |
| Capabilities | Server-driven: `me.permissions`, `me.visibility_scope`, `me.channel_availability`, `conversation.media_capabilities`, `conversation.messaging_policy`. Mobile must not hard-code these. |

---

## Realtime contract

**Envelope:** every frame is `{"event": "<type>", "payload": {...}}`.

**Client → server actions:**
- `{"action": "subscribe", "conversation_id": int}`, at most 25 threads at once
- `{"action": "unsubscribe", "conversation_id": int}`
- `{"action": "ping"}`, which refreshes presence and gets a `pong` reply

**Server → client events:**

| Event | Payload (all conversation events include `conversation_id`) | Mobile handling |
|---|---|---|
| `connection.ready` | `organization_id`, `employee_id` | Handled |
| `subscribed` / `pong` / `error` | `conversation_id` / `{}` / `message` | Handled |
| `message.created` | `message_id`, `direction`, `preview`, `sent_at`, `sender_name` or `customer_name` | Handled |
| `message.updated` | **Delivery form:** `reason: "delivery_status"`, `message_ids`, `messages: [{id, delivery_status, delivery_error, delivered_at, read_at}]`, `last_message_id`. **Media form:** `message_id` (attachment finished or failed downloading). | **Not handled (P0)** |
| `message.deleted` | `message_id`, `reason`, `deleted_by` | Handled |
| `conversation.created` / `conversation.updated` | `reason` plus changed fields (`priority`, `category_id`, `is_follow_up`, `follow_up_date`, `unread_count`, `read_receipt`, `customer_name`) | Handled |
| `conversation.assigned` | `assigned_to_id`, `assigned_to_name`, `assigned_team_id`, `status` | Handled |
| `conversation.status_changed` | `status`, `previous_status` | Handled |
| `conversation.access_revoked` | `conversation_id`: sent to a socket subscribed to a thread its employee can no longer see | **Not handled (P1)**. Mobile listens for `conversation.access_changed`, which the server never forwards to clients. |
| `note.created` | `note_id`, `author_name`, `created_at` | Handled |
| `intelligence.updated` | `stage`, `lead_score`, `purchase_status`, `needs_human_review`, `confirmed_by` | Handled |
| `presence.changed` | employee presence | Handled |
| `notification.created` | `notification_id`, `kind`, `severity` (no content; refetch the feed) | Handled |

Payloads carry ids and statuses, not message text, beyond a short preview. After
a reconnect, clients refetch; missed events are not replayed.

---

## Known contract issues

Found in the 2026-09-14 audit. Severity is for security findings; the rest are
contract bugs.

| # | Issue | Severity / type | Owner | Resolution |
|---|---|---|---|---|
| K1 | **An expired or missing session returns `403 not_authenticated`, not 401.** OpenAPI documents `401` on 76 operations, and mobile only treats 401 as session expired, so an expired session shows "You do not have permission" and the app stays "signed in". | Contract bug, **P0** | Backend + mobile | **Now:** mobile treats `403` + `error.code == "not_authenticated"` as expired. **Later (backend decision):** return 401 for unauthenticated requests, which aligns OpenAPI; web already accepts both. |
| K2 | **Pre-send refusals lose their specific code.** `POST …/reply/` answers `400 message_send_error` with only a message for `tiktok_messaging_limit`, `tiktok_no_customer_message`, `channel_unavailable` and similar; the exception handler emits the class default code. Stored failures do carry `delivery_error_code`. | Contract bug, P1 | Backend | Emit the specific code in `error.code`. Until then mobile shows `error.message` and relies on `conversation.messaging_policy` to prevent the send. |
| K3 | **The login throttle can be bypassed.** DRF `NUM_PROXIES` is unset and nginx appends to a client-supplied `X-Forwarded-For`, so the throttle key is client-controlled. There is no per-account lockout. | **Medium** security | Backend | Set `REST_FRAMEWORK["NUM_PROXIES"] = 1` (nginx is the single proxy). Consider per-account failure throttling. |
| K4 | **Mobile stores the session cookie in a plain file** (`PersistCookieJar(FileStorage(<Documents>/.cookies/))`), not Keychain/Keystore. A code comment claims secure storage. On iOS the Documents directory is included in device backups by default. Android disables backup. Mitigated by the app sandbox and the 12-hour sliding lifetime. | **Medium** security | Mobile | Store the cookie jar through secure storage, or at least exclude it from iOS backup. |
| K5 | **Open WebSocket after deactivation, role or team change.** Group membership is fixed at connect, so an already-open socket keeps receiving events for its old scope until it reconnects; REST is cut off immediately. No cross-org leakage. | **Low** security | Backend | On deactivation or role change, publish a close to that employee's sockets. |
| K6 | Session rows are not deleted on deactivation; reactivating within 12 hours revives old sessions. | Low | Backend | Optionally flush sessions on deactivation. |
| K7 | Production HSTS `max-age` is 3600 (environment override; the code default is one year). | Low | Ops | Raise `DJANGO_HSTS_SECONDS` once HTTPS is confirmed stable. |
| K8 | Login is CSRF-exempt, which is standard for DRF session login (login-CSRF). SameSite=Lax limits it. | Informational | — | None. |
| K9 | Mobile does not handle close codes `4401` or `4403`; it backs off and retries. | Low | Mobile | Treat `4401` as session expired and `4403` as signed out. |

---

## Mobile Implementation Queue

Starting state: the 2026-09-14 comparison of backend `ede15e0` with mobile
`51a428f`. Update the status when work lands.

### P0 — correctness

| Item | Backend capability | Endpoint / event | Mobile change | Status | Depends on |
|---|---|---|---|---|---|
| P0-1 | Session-expiry signal | any `403 not_authenticated` | Treat as expired: clear cookies, go to login (K1) | Not implemented | — |
| P0-2 | Live status and media updates | `message.updated` | Patch bubble status, error and timestamps from `messages[]`; on the media form, refetch that message or thread; update the inbox row tick when `last_message_id` matches | Not implemented | — |
| P0-3 | Retry failed messages stored on the server | `POST /api/conversations/{id}/messages/{message_id}/retry/` | Offer Retry on server-side `FAILED` outbound messages; 409 means already retried or sent | Not implemented | P0-2 for the resulting status |

### P1 — daily UX and workflow

| Item | Backend capability | Endpoint / event | Mobile change | Status | Depends on |
|---|---|---|---|---|---|
| P1-1 | Quoted replies | `Message.reply_to`, reply `reply_to_id` | Show the quote block; add Reply; send `reply_to_id` | Not implemented | — |
| P1-2 | Messages sent from the platform's own app | `Message.sent_from_platform` | Mark those bubbles ("Sent from WhatsApp/TikTok app"), with no agent name | Not implemented | — |
| P1-3 | Inbox row ticks | `ConversationList.last_message_direction`, `last_message_delivery_status` | Show the tick on the row | Not implemented | P0-2 |
| P1-4 | Access revoked while viewing | `conversation.access_revoked` | Close the thread, remove it from the list | Not implemented | — |
| P1-5 | Timeline wording | `ConversationEvent.metadata.automatic` / `mode` | Word automatic, fallback, reassignment, release and reroute events like web (claim and restore are done) | Partial | — |
| P1-6 | Channel scope error | `400 channel_not_allowed_for_employee` on assign and reply | Show the message and keep the draft | Not implemented | — |
| P1-7 | Realtime close codes | close `4401` / `4403` | K9 | Not implemented | P0-1 |

### P2 — admin parity

| Item | Backend capability | Endpoint | Mobile change | Status |
|---|---|---|---|---|
| P2-1 | Employee channel scope | `Employee.routing_channel_scope`, `routing_providers` | All / Selected control in the employee form | Not implemented |
| P2-2 | Channel readiness and setup | `ChannelConnection.readiness_status`, `setup_completion`, `connection_mode` | Badge and setup action per connection (TikTok readiness done) | Partial |
| P2-3 | Strict responsibility | `RoutingPolicy.strict_responsibility` | Toggle in routing settings | Not implemented |
| P2-4 | Team channel responsibilities | `TeamWrite.responsibilities` | Section in the team form | Not implemented |
| P2-5 | Employee reactivation | `POST /api/employees/{id}/activate/` | Reactivate action | Not implemented |
| P2-6 | Conversation ownership details | `ConversationDetail.claimed_by`, `first_response_at`, `resolved_at`, `last_agent_message_at` | Show in conversation info | Not implemented |
| P2-7 | Order history | `GET /api/orders/{id}/events/` | History list in order detail | Not implemented |

### P3 — optional / web-first

| Item | Capability | Endpoint | Status |
|---|---|---|---|
| P3-1 | Customer field definitions admin | `/api/customer-fields/`, `…/reorder/` | Not implemented (values: Implemented) |
| P3-2 | Saved replies management | `POST/PATCH/DELETE /api/saved-replies/` | Not implemented (insert: Implemented) |
| P3-3 | Categories admin | `/api/categories/{id}/` | Not implemented |
| P3-4 | CSV export | `/api/{customers,conversations,orders}/export/` | WEB-ONLY |
| P3-5 | Routing responsibility rules list | `/api/routing/responsibilities/` | WEB-ONLY |

---

## API inventory (mobile-relevant)

Canonical request and response shapes live in `docs/api/openapi.yaml` under the
named component. This table exists to find them.

| Group | Endpoints | OpenAPI components |
|---|---|---|
| Auth | `GET auth/csrf/` · `POST auth/login/` · `POST auth/logout/` · `GET/PATCH auth/me/` · `POST auth/availability/` · `POST auth/password/` | `Login`, `LoginResponse`, `CurrentEmployee`, `EmployeeWrite` |
| Devices (push) | `POST devices/register/` · `POST devices/unregister/` · `POST devices/heartbeat/` | device operations |
| Inbox | `GET conversations/` · `GET conversations/grouped/` · `GET conversations/counts/` · `GET conversations/channels/` · `GET conversations/{id}/` | `ConversationList`, `ConversationGroup`, `ConversationDetail`, `ConversationCounts` |
| Conversation actions | `POST …/assign/` · `…/status/` · `…/priority/` · `…/category/` · `…/follow-up/` · `…/read/` · `…/intelligence/` · `…/lead-score/` · `…/confirm-purchase/` · `…/report-conversion/` · `GET/POST …/notes/` · `GET …/events/` | `ConversationDetail`, `InternalNote`, `ConversationEvent` |
| Messages | `GET …/messages/` · `POST …/reply/` · `POST …/messages/{mid}/retry/` · `DELETE …/messages/{mid}/` · `POST/DELETE …/attachments/` · `GET attachments/{public_id}/content/` · `POST …/send-template/` | `Message`, `QuotedMessage`, `Reply`, `AttachmentDraft` |
| Customers | `GET/PATCH customers/` · `…/{id}/` · `…/{id}/conversations/` · `…/{id}/orders/` · `…/{id}/facts/` · `…/{id}/fields/` · `…/facts/{fid}/review/` | `CustomerList`, `CustomerDetail`, `CustomerFact`, `CustomerFieldValue` |
| Customer fields | `GET/POST customer-fields/` · `PATCH customer-fields/{id}/` · `POST customer-fields/reorder/` | `CustomerFieldDefinition` |
| Orders | `GET/POST orders/` · `GET/PATCH orders/{id}/` · `POST …/confirm/` · `POST …/cancel/` · `GET …/events/` | `Order`, `OrderWrite`, `OrderEvent` |
| Employees | `GET/POST employees/` · `GET/PATCH/DELETE employees/{id}/` · `POST employees/{id}/activate/` · `GET employees/online/` | `Employee`, `EmployeeWrite` |
| Teams | `GET/POST teams/` · `GET/PATCH/DELETE teams/{id}/` | `Team`, `TeamWrite`, `TeamResponsibilityInput` |
| Routing | `GET/PATCH routing/policy/` · `routing/responsibilities/` | `RoutingPolicy`, `RoutingResponsibility` |
| Channels | `GET channels/` · `GET/DELETE channels/{id}/` · `POST …/test/` · `…/mute/` · `…/unmute/` · `GET channels/providers/` | `ChannelConnection` |
| Integrations | `integrations/{meta,instagram,whatsapp,tiktok}/…` connect / authorize / disconnect · `integrations/whatsapp/{id}/check-status/` · `…/templates/` | per operation |
| Saved replies | `GET/POST saved-replies/` · `GET/PATCH/DELETE saved-replies/{id}/` | `SavedReply`, `SavedReplyWrite` |
| Dashboard | `GET dashboard/` · `dashboard/channels/` · `dashboard/performance/` (`from`, `to`, `preset`) | `DashboardSummary`, `EmployeePerformanceResponse` |
| Notifications | `GET notifications/` · `…/unread-count/` · `POST …/{id}/read/` · `POST …/read-all/` | `Notification` |
| Categories | `GET categories/` | `Category` |
| Client errors | `POST client-errors/` | — |

---

## Changelog

Newest first. Every entry below is **deployed to production** unless marked
otherwise. Dates are UTC.

### 2026-09-14 — Employee channel scope

**Backend commit:** `ede15e0`
**Deployment:** Production
**Impact:** RECOMMENDED (P1-6 error handling), OPTIONAL admin form (P2-1)
**Compatibility:** BACKWARD COMPATIBLE
**Mobile status:** Not implemented

#### API changes
- Changed: `GET/POST/PATCH /api/employees/…`, `GET /api/auth/me/` gain the fields below.
- Changed: `POST /api/conversations/{id}/assign/` and `POST …/reply/` can refuse with a new error.

#### Request changes (`EmployeeWrite`)
| Field | Type | Required | New | Notes |
|---|---|---|---|---|
| `routing_channel_scope` | enum `ALL` \| `SELECTED` | no | added | Default `ALL` |
| `routing_providers` | array of `FACEBOOK` \| `INSTAGRAM` \| `WHATSAPP` \| `TIKTOK` | when `SELECTED` | added | At least one; `MOCK` refused |

#### Response changes (`Employee`, `CurrentEmployee`)
| Field | Type | Nullable | Notes |
|---|---|---|---|
| `routing_channel_scope` | enum | no | `ALL` for every existing employee |
| `routing_providers` | string[] | no | Empty when `ALL` |

#### New error codes
| HTTP | Code | Meaning | Mobile handling |
|---|---|---|---|
| 400 | `channel_not_allowed_for_employee` | The assignee or replier does not handle this channel | Show `error.message`; keep the draft |

#### Mobile action required
Handle the error on assign and reply (P1-6). An employee-form control is P2-1.

#### Backward compatibility
Old apps ignore the new fields. Only the new error can appear, and it arrives in
the standard error envelope.

#### Notes
A hard limit on **ownership** (automatic routing, fallback, strict mode, manual
assignment, claim by reply), not on visibility. It is separate from routing
responsibility, which is a preference. Narrowing a scope never removes
conversations the employee already owns.

### 2026-09-14 — Claim-by-reply writes one timeline row; event target fields

**Backend commit:** `3e55a71`
**Deployment:** Production
**Impact:** RECOMMENDED
**Compatibility:** BACKWARD COMPATIBLE
**Mobile status:** Implemented (claim wording, dedupe)

#### Response changes (`ConversationEvent`)
| Field | Type | Nullable | Notes |
|---|---|---|---|
| `target_employee_id` | int | yes | Who the event is about |
| `target_employee_name` | string | no | Use when `to_value` is empty |

#### Mobile action required
Done: claim wording, plus hiding the historical double claim row. Assigning the
current owner again is now a no-op on the server (no event is written).

### 2026-09-14 — TikTok Business Messaging (public)

**Backend commits:** `295ece9` (A), `ca09a88` (B), `c28c281` (C), `6f49fe8` (D). Public availability via production configuration.
**Deployment:** Production, `SCENARIO_TIKTOK_AVAILABILITY=enabled`
**Impact:** REQUIRED for TikTok users
**Compatibility:** BACKWARD COMPATIBLE
**Mobile status:** Implemented, except native quoting (depends on P1-1)

#### Response changes
| Resource | Field | Notes |
|---|---|---|
| `CurrentEmployee` | `channel_availability` | `{provider: "AVAILABLE" \| "COMING_SOON"}`; render Coming Soon from it |
| `Message` | `content_notice` | `{kind: share_post \| template \| unsupported, provider_type, url, title, video_id}` or null |
| `Message` | `delivery_error_code` | Stable failure code (`tiktok_*`, `channel_unavailable`) |
| `ConversationDetail` | `messaging_policy` | `{state, allowed, remaining_count, window_expires_at, reason}`; TikTok only, otherwise null |
| `ChannelConnection` | `tiktok_readiness` | `{state: READY \| BLOCKED \| UNKNOWN, reason, provider_code, request_id, log_id, missing_scopes, checked_at}` |

#### New error / delivery codes
`tiktok_token_invalid`, `tiktok_permission_denied`, `tiktok_invalid_request`,
`tiktok_messaging_limit`, `tiktok_rate_limited`, `tiktok_not_eligible`,
`tiktok_unavailable`, `tiktok_media_rejected`, `tiktok_unknown_error`,
`tiktok_not_ready`, `tiktok_no_customer_message`, `channel_unavailable`.
They appear in `Message.delivery_error_code`; synchronous refusals currently
arrive as `message_send_error` (K2).

#### Notes
TikTok accepts no outbound media (`media_capabilities.outbound_media` is false).
A reply quotes natively only for TEXT replies to TEXT, IMAGE or SHARE_POST
messages.

### 2026-09-14 — CSV export

**Backend commit:** `1e52244` · **Deployment:** Production · **Impact:** WEB-ONLY · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Not implemented (not planned)

- Added: `GET /api/customers/export/`, `/api/conversations/export/`, `/api/orders/export/` (`text/csv`, same filters as the list, needs `crm.export`, throttled 10/min).

### 2026-09-13 — Team channel responsibilities and strict responsibility

**Backend commits:** `8d8d020` (responsibility, strict), `9b36537` (team form) · **Deployment:** Production · **Impact:** OPTIONAL (P2-3, P2-4) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Not implemented

#### Request changes
| Resource | Field | Type | Notes |
|---|---|---|---|
| `TeamWrite` | `responsibilities` | array of `{provider, scope: "all" \| "selected", channel_connection_ids}` | Omit to leave unchanged; the list is the team's complete responsibility |
| `RoutingPolicy` (PATCH) | `strict_responsibility` | bool | |

#### Added
- `GET/POST /api/routing/responsibilities/`, `PATCH/DELETE /api/routing/responsibilities/{id}/`

#### Notes
Responsibility ranks eligible employees first; it never changes visibility.
Strict mode leaves a conversation unassigned when nobody responsible can take it.

### 2026-09-13 — Typed customer fields

**Backend commit:** `aedf43b` · **Deployment:** Production · **Impact:** RECOMMENDED (values), OPTIONAL (definitions) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Partial (values implemented)

- Added: `GET/POST /api/customer-fields/`, `PATCH /api/customer-fields/{id}/`, `POST /api/customer-fields/reorder/` (write needs `customer_field.manage`).
- Added: `GET /api/customers/{id}/fields/` (`CustomerFieldValue`: `definition`, `value`, `fact_id`, `updated_at`, `updated_by_name`).

### 2026-09-13 — Rich orders

**Backend commit:** `b0601bb` · **Deployment:** Production · **Impact:** RECOMMENDED · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Partial (fields implemented; history not)

- Response and request (`Order`, `OrderWrite`) gain delivery, pricing and payment fields: `recipient_name`, `recipient_phone`, `alternative_phone`, `governorate`, `city`, `address`, `landmark`, `location_url`, `delivery_notes`, `shipping_method`, `shipping_cost`, `discount`, `subtotal`, `payment_method`, `payment_status`, `expected_delivery_date`, `fulfilment_status`, `fulfilment_status_display`, `internal_note`, `external_reference`, `items[]`.
- Added: `GET /api/orders/{id}/events/` (`OrderEvent[]`, append-only history), P2-7.

### 2026-09-13 — Saved replies

**Backend commit:** `28e3277` · **Deployment:** Production · **Impact:** RECOMMENDED (insert), OPTIONAL (manage) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Partial (insert implemented)

- Added: `GET/POST /api/saved-replies/`, `GET/PATCH/DELETE /api/saved-replies/{id}/` (`SavedReply`: `title`, `shortcut`, `body`, `category`, `scope`, `team`, `can_edit`, `is_active`).
- There is no send endpoint: a saved reply is text inserted into the composer and sent through `reply/`.

### 2026-09-08 — Messages sent from the platform's own app

**Backend commit:** `76cc3d0` · **Deployment:** Production · **Impact:** RECOMMENDED (P1-2) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Not implemented

| Resource | Field | Type | Notes |
|---|---|---|---|
| `Message` | `sent_from_platform` | bool | True for an outbound message typed in WhatsApp/Instagram/TikTok itself (no employee) |

### 2026-09-08 — Quoted replies

**Backend commits:** `a3a6cd9`, `83cf083` (native quoting) · **Deployment:** Production · **Impact:** RECOMMENDED (P1-1) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Not implemented

#### Request changes (`POST /api/conversations/{id}/reply/`)
| Field | Type | Required | Notes |
|---|---|---|---|
| `reply_to_id` | int | no | A message id in the same conversation; not an optimistic (negative) id |

#### Response changes (`Message`)
| Field | Type | Nullable | Notes |
|---|---|---|---|
| `reply_to` | `QuotedMessage` `{id, text, truncated, message_type, direction, sender_name, sent_at, is_deleted, available}` | yes | A snapshot: still rendered when the original is deleted or not loaded |

Also: inbound quotes from customers populate `reply_to`. The provider quotes
natively where supported (Meta; TikTok for text, image and shared post).

### 2026-09-04 — Answering takes ownership (claim by reply)

**Backend commits:** `d675965`, `31bf25e`, `3148b5d`, `729f299` · **Deployment:** Production · **Impact:** REQUIRED (409 handling, implemented), RECOMMENDED (timeline, P1-5) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Partial

#### Response changes
| Resource | Field | Notes |
|---|---|---|
| `ConversationDetail` | `claimed_by` (`EmployeeBrief`, nullable) | Who took the conversation by replying (P2-6) |
| `ConversationEvent.metadata` | `automatic: true`, `mode` | Modes: *(absent)* router assignment · `fallback` (with `reasons`) · `reassignment` (with `previous_employee_*`) · `claim` · `claimed_owner_restored`. Automatic `TRANSFERRED` means rerouted; `UNASSIGNED` + `reassignment` means released. |

#### New error codes
| HTTP | Code | Meaning | Mobile handling |
|---|---|---|---|
| 409 | `ownership_conflict` | Someone else owns the conversation; nothing was sent | Implemented: remove the optimistic bubble, keep the text |

#### Notes
A reply to an unassigned conversation assigns it to the sender. A resolved
conversation can be answered (it reopens); a closed one cannot.

### 2026-09-03 — Optimistic send, delivery-status events, inbox ticks

**Backend commits:** `138baa8`, `d2104ea`, `db4e83b` (event introduced) · **Deployment:** Production · **Impact:** REQUIRED (P0-2), RECOMMENDED (P1-3) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Partial (`client_message_id` implemented)

#### Request changes
| Field | Endpoint | Notes |
|---|---|---|
| `client_message_id` | `POST …/reply/` | Idempotency key and optimistic-bubble correlation (implemented) |

#### Response changes
| Resource | Field | Notes |
|---|---|---|
| `Message` | `client_message_id`, `delivered_at`, `read_at` | |
| `ConversationList` | `last_message_direction`, `last_message_delivery_status` | Row tick (P1-3) |

#### Realtime events
| Event | Change | Payload | Required mobile action |
|---|---|---|---|
| `message.updated` | Added; delivery form added in `138baa8`/`d2104ea` | See [Realtime contract](#realtime-contract) | Handle both forms (P0-2) |

### 2026-09-01 — Channel readiness and setup completion

**Backend commits:** `547fe00`, `e3f53b8`, `5e3dcdc` (Instagram), `f5b0936` (`connection_mode`, 2026-08-31) · **Deployment:** Production · **Impact:** OPTIONAL (P2-2) · **Compatibility:** BACKWARD COMPATIBLE · **Mobile status:** Partial

| Resource | Field | Type | Notes |
|---|---|---|---|
| `ChannelConnection` | `readiness_status` | `READY` \| `PENDING_SETUP` \| `BLOCKED` \| `UNKNOWN` | Can the provider actually use this channel |
| `ChannelConnection` | `setup_completion` | `{required, action: COMPLETE_SIGNUP \| WAIT_FOR_PROVIDER \| CONTACT_SUPPORT \| CONNECT_INSTAGRAM_DIRECTLY \| NONE, can_check_status}` | Render the action the server names |
| `ChannelConnection` | `connection_mode` | string | WhatsApp `cloud_api` / `coexistence`; Instagram `instagram_login` / `facebook_derived` |

### Pre-existing endpoints mobile does not use yet

Present since the initial backend (`22689b9`, 2026-08-13); listed so they are
not mistaken for new work.

- `POST /api/conversations/{id}/messages/{message_id}/retry/`, P0-3
- `POST /api/employees/{id}/activate/`, P2-5
- `ConversationDetail.first_response_at`, `resolved_at`, `last_agent_message_at`, P2-6

---

## Maintenance rule

**Any backend change to a mobile-consumed endpoint, request field, response
field, enum, error code, realtime event, authentication behaviour or permission
behaviour must update this file in the same PR or commit.** If there is no mobile
impact, no entry is needed.

How to keep it honest:

1. Regenerate the OpenAPI snapshot when the API changes:
   `DATABASE_URL=postgres://… DJANGO_SETTINGS_MODULE=config.settings.test python manage.py spectacular --file docs/api/openapi.yaml`
2. `tests/test_openapi_snapshot.py` fails whenever the generated schema and the
   committed `docs/api/openapi.yaml` differ. When it fails, regenerate the
   snapshot **and decide whether the change needs an entry here**.
3. Add the entry at the top of the Changelog using the template below, then
   update the Implementation Queue.
4. When mobile ships an item, update its **Mobile status** and queue row.

### Entry template

```markdown
### YYYY-MM-DD — Change title

**Backend commit:** `<hash>`
**Deployment:** Production / Not deployed
**Impact:** REQUIRED / RECOMMENDED / OPTIONAL / WEB-ONLY
**Compatibility:** BACKWARD COMPATIBLE / BREAKING
**Mobile status:** Not implemented / Partial / Implemented

#### API changes
- Added / Changed / Deprecated / Removed: `METHOD /api/path/`

#### Request changes
| Field | Type | Required | Previous | New | Notes |

#### Response changes
| Field | Type | Nullable | Previous | New | Notes |

#### New error codes
| HTTP | Code | Meaning | Mobile handling |

#### Realtime events
| Event | Change | Payload | Required mobile action |

#### Mobile action required
#### Backward compatibility
#### Notes
```
