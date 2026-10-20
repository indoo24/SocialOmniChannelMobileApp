# Scenario Omnichannel API — Reference for Claude Code

> Generated from the live OpenAPI 3.0.3 schema at `https://scenariomnchnl.tech/api/schema/` (Swagger UI: `/api/docs/`), API version 1.0.0, on 2026-10-20.
> 133 operations, 25 tag groups. If something here disagrees with the live schema, the live schema wins — regenerate this file.

Scenario is a customer-service backend (Django REST Framework + drf-spectacular): one shared inbox across **WhatsApp, Messenger, Instagram and TikTok**, with conversation intelligence (lead scoring, purchase detection), orders, customers, routing and teams.

---

## 0. Rules Claude must follow when writing client code

1. **Base URL:** `https://scenariomnchnl.tech`. Every path below already starts with `/api/`. **Trailing slashes are required** (`/api/conversations/`, not `/api/conversations`).
2. **Auth is a session cookie, not a bearer token.** Never add `Authorization: Bearer …`. Persist cookies (browser: `credentials: 'include'`; Flutter/Dart: a cookie jar).
3. **Every POST / PUT / PATCH / DELETE needs an `X-CSRFToken` header.** Get the token from the login response body, from `GET /api/auth/csrf/`, or from the `scenario_csrftoken` cookie. This is *not* in the Swagger security scheme — the client must add it itself.
4. **Errors always have one shape** — `{"error": {"code", "message", "details"}}`. Show `message` to users; map `details` (`{field: [msg…]}`) onto form fields.
5. **404 can mean "forbidden"**: resources in another organization or outside your visibility return 404, never 403. Don't treat 404 as "deleted" blindly.
6. **Check the response type before paginating.** Most lists return the paginated envelope; many sub-resources return a **plain array** (marked `[]` below).
7. **Bodies are JSON** unless marked *multipart* (file uploads). Endpoints also accept form-encoded, but use JSON.
8. **Gate UI with `GET /api/auth/me/` → `permissions`**, but still handle 403 — the server re-checks everything.
9. **Realtime (WebSocket) is not documented in this schema.** Don't invent a WebSocket contract; poll or ask.
10. Some deletes are **soft** (deactivate/retire) and return **200 with the object**, not 204. Each is noted.

---

## 1. Authentication flow

| Step | Call | Notes |
|---|---|---|
| 1 | `GET /api/auth/csrf/` | Optional before login. Sets `scenario_csrftoken` cookie, returns `{csrf_token}`. Public. |
| 2 | `POST /api/auth/login/` `{email, password}` | Public. Sets httpOnly `scenario_session` cookie. Returns `{employee: CurrentEmployee, csrf_token}`. Moves user OFFLINE→ONLINE. Throttled **10/min**. Bad password / unknown email / deactivated are indistinguishable (400). |
| 3 | Any request | Send cookies. Unsafe methods add `X-CSRFToken: <csrf_token>`. |
| 4 | `GET /api/auth/me/` | `CurrentEmployee` incl. `permissions[]`, `organization`, `visibility_scope`. |
| 5 | `POST /api/auth/logout/` | 204. Clears session, sets OFFLINE. No body. |

### Minimal clients

```ts
// TypeScript / browser
let csrf = '';
async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const method = (init.method ?? 'GET').toUpperCase();
  const headers = new Headers(init.headers);
  if (init.body && !(init.body instanceof FormData)) headers.set('Content-Type', 'application/json');
  if (!['GET', 'HEAD', 'OPTIONS'].includes(method)) headers.set('X-CSRFToken', csrf);
  const res = await fetch(`https://scenariomnchnl.tech${path}`, { ...init, headers, credentials: 'include' });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => null);
  if (!res.ok) throw Object.assign(new Error(data?.error?.message ?? res.statusText), { status: res.status, api: data?.error });
  return data as T;
}
const login = async (email: string, password: string) => {
  const r = await api<{ employee: CurrentEmployee; csrf_token: string }>('/api/auth/login/', { method: 'POST', body: JSON.stringify({ email, password }) });
  csrf = r.csrf_token; return r.employee;
};
```

```dart
// Flutter / Dart — dio + cookie_jar + dio_cookie_manager
final jar = PersistCookieJar(storage: FileStorage('${appDocDir.path}/.cookies/'));
final dio = Dio(BaseOptions(baseUrl: 'https://scenariomnchnl.tech', contentType: 'application/json'))
  ..interceptors.add(CookieManager(jar))
  ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
    if (!['GET', 'HEAD', 'OPTIONS'].contains(o.method)) {
      final cookies = await jar.loadForRequest(Uri.parse('https://scenariomnchnl.tech/'));
      final c = cookies.where((c) => c.name == 'scenario_csrftoken');
      if (c.isNotEmpty) o.headers['X-CSRFToken'] = c.first.value;
    }
    h.next(o);
  }));
// login: await dio.post('/api/auth/login/', data: {'email': e, 'password': p});
```

---

## 2. Conventions

**Error body** (every non-2xx):
```json
{"error": {"code": "validation_error", "message": "Human readable", "details": {"field": ["msg"]}}}
```
`code` examples: `validation_error`, `not_found`, `throttled`. `details` is `{}` when not a validation error.

**Status codes used:** 400 validation/provider refusal · 401 no session · 403 missing capability · 404 not found *or not visible* · 409 state conflict (e.g. retrying a non-failed message, deleting a live channel) · 429 throttled · 502/503 upstream (Meta) problems.

**Pagination envelope** — `Paginated<X>List`:
```json
{"count": 123, "page": 1, "page_size": 30, "total_pages": 5, "next": "url|null", "previous": "url|null", "results": [ X ]}
```
Query: `?page=` and `?page_size=` (capped per endpoint). Conversations default 30/page, messages 50/page.

**Common list params:** `ordering` (field name, prefix `-` for desc), `search` (free text).

**Throttles:** login 10/min · reply & send-template 120/min · CSV exports throttled (429).

**Swagger quirk:** several conversation sub-routes (`/{id}/events/`, `/{id}/notes/`, `/{id}/conversions/`, `/{id}/purchase-confirmations/`, `/reviewers/`…) list all the inbox filters as query params. They are a framework artifact — **don't send them**.

### Roles & capabilities

Roles (`RoleEnum`): `ADMIN | SUPERVISOR | TEAM_LEADER | AGENT | QA`.

Capabilities referenced by endpoints (read the caller's real list from `/api/auth/me/`):
`conversation.reply`, `conversation.note`, `conversation.assign_self`, `conversation.assign_any`, `conversation.change_status`, `conversation.change_priority`, `conversation.change_category`, `conversation.confirm_purchase`, `conversation.refresh_intelligence`, `conversation.delete_message` (ADMIN, SUPERVISOR), `conversation.review` (ADMIN, SUPERVISOR), `intelligence.override_score`, `conversion.report`, `customer.view`, `customer.manage`, `customer_field.manage`, `order.manage` (QA lacks it), `employee.view` (all roles), `employee.manage` (ADMIN), `team.view`, `team.manage`, `channel.view`, `channel.manage`, `routing.manage`, `saved_reply.manage`, `analytics.view`, `notification.view` (ADMIN).

---

## 3. Endpoints

Notation: `→ 200 Type` success · `[]` = plain array (not paginated) · `Paginated<X>` = envelope above · **cap:** required capability · `{id}` is an integer unless noted.

### 3.1 auth

| Method & path | Purpose |
|---|---|
| `GET /api/auth/csrf/` | Public. Prime CSRF cookie. → 200 `CsrfTokenResponse` |
| `POST /api/auth/login/` | Public. Body `Login`. → 200 `LoginResponse` · 400, 429 |
| `POST /api/auth/logout/` | → 204 |
| `GET /api/auth/me/` | → 200 `CurrentEmployee` |
| `PATCH /api/auth/me/` | Edit own profile. Body `EmployeeWrite` (partial). `role`, `is_active`, `team_ids` are **silently discarded**. → 200 `CurrentEmployee` |
| `POST /api/auth/password/` | Body `PasswordChange`. Session survives. → 204 |
| `POST /api/auth/availability/` | Body `Availability`. Drives routing & presence. → 200 `CurrentEmployee` |

### 3.2 conversations (the inbox)

**`GET /api/conversations/`** → 200 `Paginated<ConversationList>` (30/page). Muted channels excluded unless `include_muted`.
Filters:
- `view` string · `status` string[] (`NEW|OPEN|WAITING_CUSTOMER|WAITING_INTERNAL|RESOLVED|CLOSED`) · `priority` string[] (`LOW|NORMAL|HIGH|URGENT`) · `provider` string[] (`FACEBOOK|INSTAGRAM|TIKTOK|WHATSAPP|MOCK`)
- `assigned_to` id · `team` id · `category` id · `customer` id · `custom_state` int[] (comma-separated)
- `channel_connection` id · `channel_connections` id[] (comma-separated)
- `stage` string (sales stage) · `min_lead_score` int · `review` string
- `unread` bool · `follow_up` bool · `pinned` bool · `include_muted` bool (`1|true|yes`)
- `search` · `ordering` · `page` · `page_size`

| Method & path | Purpose |
|---|---|
| `GET /api/conversations/{id}/` | → 200 `ConversationDetail`. **Side effect: marks the thread read.** |
| `GET /api/conversations/counts/` | Sidebar badges. `?channel_connection=` optional. → 200 `ConversationCounts` |
| `GET /api/conversations/grouped/` | Same filters as list, one row per customer (nothing merged). `page` counts groups, `page_size` max 100. → 200 `Paginated<ConversationGroup>` |
| `GET /api/conversations/channels/` | Accounts an agent can scope the inbox to (any employee). → 200 `Paginated<InboxChannel>` |
| `GET /api/conversations/reviewers/` | Colleagues holding `conversation.review`, excluding caller. → 200 `EmployeeBrief[]` |
| `GET /api/conversations/export/` | CSV (UTF-8 + BOM), one row per conversation, metadata only. Accepts the list filters. → 200 `text/csv` · 429 |
| `POST /api/conversations/{id}/read/` | Mark read, no body, idempotent. → 200 `MarkReadResponse` |

**Messages**

| Method & path | Purpose |
|---|---|
| `GET /api/conversations/{id}/messages/` | → 200 `Paginated<Message>`, 50/page, **newest first** (page 1 = end of thread). `?order=asc` for oldest first. Deleted messages omitted. |
| `POST /api/conversations/{id}/reply/` | **cap:** `conversation.reply`. Body `Reply`. → 201 `Message` · 400 carries provider refusal (expired token, closed WhatsApp 24h window) · 429 (120/min) |
| `POST /api/conversations/{id}/send-template/` | WhatsApp only — the only way to message after the 24h window closes. Body `SendTemplate`; `parameters` must match the template's variable count. Approval checked live at Meta. → 201 `Message` · 429 |
| `DELETE /api/conversations/{id}/messages/{message_id}/` | **cap:** `conversation.delete_message`. Soft delete; does **not** unsend on the platform. Optional JSON body `{"reason": "..."}`. → 204 |
| `POST /api/conversations/{id}/messages/{message_id}/retry/` | Resend a **FAILED** outgoing media message (no re-upload). `message_id` is a string here. → 200 `Message` · 409 if not FAILED / already retrying |

**Attachments (send flow: stage draft → reply with `attachment_ids`)**

| Method & path | Purpose |
|---|---|
| `POST /api/conversations/{id}/attachments/` | *multipart*: `file` (binary), `is_voice` bool?, `duration_ms` int?. Server re-derives type from bytes; size limit = platform's. → 201 `AttachmentDraft` |
| `POST /api/conversations/{id}/attachments/from-saved-reply/` | Body `{saved_reply_id}`. Copies a saved reply's file into a draft (does not send). → 201 `AttachmentDraft` |
| `DELETE /api/conversations/{id}/attachments/{draft_id}/` | Discard draft (`draft_id` = uuid string). Idempotent. → 204 |
| `GET /api/attachments/{public_id}/content/` | Download/stream bytes (`public_id` uuid). Supports `Range` (→ 206). 404 if not visible, 409 possible. |

Typical send-with-file:
```
POST /api/conversations/42/attachments/   (multipart file=@photo.jpg)   → {id: "uuid", ...}
POST /api/conversations/42/reply/         {"text": "", "attachment_ids": ["uuid"], "client_message_id": "local-123"}
```

**State changes** (all → 200 `ConversationDetail` unless noted)

| Method & path | Body | Notes |
|---|---|---|
| `POST /api/conversations/{id}/assign/` | `Assign` | `assignee_id` / `team_id`, `null` releases; omitted = unchanged. Self-claim/release needs `conversation.assign_self`; moving others' work needs `conversation.assign_any`. |
| `POST /api/conversations/{id}/status/` | `Status` | **cap:** `conversation.change_status`. Exactly one of `status` or `custom_state_id`. |
| `POST /api/conversations/{id}/priority/` | `Priority` | **cap:** `conversation.change_priority` |
| `POST /api/conversations/{id}/category/` | `CategoryUpdate` | **cap:** `conversation.change_category`. `category_id: null` clears. |
| `POST /api/conversations/{id}/follow-up/` | `FollowUp` | Shared flag. `follow_up_date`: omit = keep, `null` = clear date (stay flagged), `YYYY-MM-DD` = set. Past dates accepted. |
| `POST /api/conversations/{id}/pin/` | — | Personal pin (only affects caller's sort). |
| `DELETE /api/conversations/{id}/pin/` | — | Unpin. |
| `POST /api/conversations/{id}/reopen/` | — | **cap:** `change_status`. Resolve was *right*, new work begins (new episode; old resolution still counts). 409 on invalid state. |
| `POST /api/conversations/{id}/undo-resolve/` | — | **cap:** `change_status`. Resolve was a *mistake*: restores previous status/custom state, resolution stops counting. 409 on invalid state. |
| `POST /api/conversations/{id}/review/` | `ReviewRequestInput` | **cap:** `conversation.reply`. Ask a named supervisor to review. Not an assignment; no lock. 409 possible. |
| `DELETE /api/conversations/{id}/review/` | — | Cancel the review request. |
| `POST /api/conversations/{id}/review/complete/` | — | Only the named reviewer. Replying does **not** clear a review. 409 possible. |

**Notes, history, intelligence**

| Method & path | Purpose |
|---|---|
| `GET /api/conversations/{id}/notes/` | → 200 `InternalNote[]` (never sent to customer) |
| `POST /api/conversations/{id}/notes/` | **cap:** `conversation.note`. Body `NoteCreate`. → 201 `InternalNote` |
| `GET /api/conversations/{id}/events/` | Audit timeline. → 200 `ConversationEvent[]` |
| `GET /api/conversations/{id}/intelligence/` | → 200 `ConversationIntelligence` **or literal `null`** if never analyzed (≠ score 0) |
| `POST /api/conversations/{id}/intelligence/` | **cap:** `conversation.refresh_intelligence`. Re-run analyzer synchronously. → 200 `ConversationIntelligence` |
| `POST /api/conversations/{id}/lead-score/` | **cap:** `intelligence.override_score`. Body `LeadScoreRequest`; `score: null` returns control to analyzer. → 200 `ConversationIntelligence` |
| `POST /api/conversations/{id}/confirm-purchase/` | **cap:** `conversation.confirm_purchase`. Body `ConfirmPurchaseRequest`. Only way to reach `AGENT_CONFIRMED`. → 200 `ConversationIntelligence` |
| `GET /api/conversations/{id}/purchase-confirmations/` | → 200 `PurchaseConfirmation[]` |
| `POST /api/conversations/{id}/report-conversion/` | **cap:** `conversion.report`. No body; sends current stage to Meta Conversions API. Always 200 — read `status` (`already_reported` = no-op). → 200 `ReportConversionResponse` |
| `GET /api/conversations/{id}/conversions/` | What was reported to Meta, newest first. → 200 `ConversionEvent[]` |

### 3.3 conversation-states (custom statuses)

Any active employee can read; writes need `team.manage`.

| Method & path | Purpose |
|---|---|
| `GET /api/conversation-states/` | `?ordering&search` → 200 `ConversationCustomState[]` |
| `POST /api/conversation-states/` | Body `ConversationCustomState` (`label`, `color?`, `base_status`, `display_order?`) → 201 |
| `GET / PUT / PATCH / DELETE /api/conversation-states/{id}/` | Retrieve/replace/update/archive. `base_status` is write-once (create only). DELETE → 204 (archives). |
| `POST /api/conversation-states/{id}/restore/` | Restore archived state. → 200 `ConversationCustomState` |
| `GET /api/conversation-states/distribution/` | Snapshot of where conversations are now. → 200 `ConversationStateDistribution` |
| `GET /api/conversation-states/system/` | Built-in statuses: visibility + labels. → 200 `SystemStateVisibility[]` |
| `PATCH /api/conversation-states/system/` | **cap:** `team.manage`. Body `{hidden?: string[], labels?: {STATUS: "label"}}` — each is the complete set. → 200 `SystemStateVisibility[]` |

### 3.4 categories (conversation taxonomy)

| Method & path | Purpose |
|---|---|
| `GET /api/categories/` | Any employee. `?ordering&search` → 200 `Category[]` |
| `POST /api/categories/` | **cap:** `team.manage`. Body `Category` → 201 |
| `GET / PUT / PATCH /api/categories/{id}/` | → 200 `Category` |
| `DELETE /api/categories/{id}/` | **cap:** `team.manage`. Deactivates (system categories can't be removed → 400). → 204 |

### 3.5 customers

**`GET /api/customers/`** → 200 `Paginated<CustomerList>`. Filters:
`search` (name/email/phone/username) · `lifecycle_stage` (`UNKNOWN|NEW_CUSTOMER|PROSPECT|EXISTING_CUSTOMER|REPEAT_BUYER`) · `preferred_language` · `country` · `channel` (has identity on platform) · `tag` · `created_after|created_before` (date) · `last_seen_after|last_seen_before` (date) · `has_orders` bool · `order_status` (comma list) · `ordered_after|ordered_before` · `last_order_after|last_order_before` · `order_count__exact|__gte|__lte` · `total_spent__gte|__lte` (requires `currency`, e.g. `EGP`) · custom fields: `field__<key>=<value>`, `field__<key>__contains=<text>` and other operators · `page` · `page_size`.

| Method & path | Purpose |
|---|---|
| `POST /api/customers/` | **cap:** `customer.manage`. Body `CustomerWrite` → 201 `CustomerWrite` |
| `GET /api/customers/{id}/` | → 200 `CustomerDetail` (incl. `confirmed_purchase_count`) |
| `PUT / PATCH /api/customers/{id}/` | **cap:** `customer.manage`. Body `CustomerWrite` (partial for PATCH) → 200 `CustomerDetail` |
| `DELETE /api/customers/{id}/` | **cap:** `customer.manage` → 204 |
| `GET /api/customers/{id}/conversations/` | Newest first, visibility-filtered. → 200 `Paginated<ConversationList>` |
| `GET /api/customers/{id}/orders/` | → 200 `Order[]` |
| `GET /api/customers/{id}/facts/` | Confirmed facts + unreviewed analyzer suggestions. → 200 `CustomerFact[]` |
| `POST /api/customers/{id}/facts/` | **cap:** `order.manage` (not `customer.manage`). Upserts on `key`. Body `CustomerFactWrite` → 201 `CustomerFact` |
| `POST /api/customers/{id}/facts/{fact_id}/review/` | **cap:** `order.manage`. Body `CustomerFactReview` (`confirmed`, optional corrected `value`) → 200 `CustomerFact` |
| `GET /api/customers/{id}/fields/` | Every active custom field + this customer's value or null. **cap:** `customer.view` → 200 `CustomerFieldValue[]` |
| `PATCH /api/customers/{id}/fields/` | **cap:** `customer.manage`. Body `{values: {field_key: value|null}, conversation?: id}`. All-or-nothing validation. → 200 `CustomerFieldValue[]` |
| `GET /api/customers/export/` | CSV, accepts list filters. → 200 `text/csv` · 429 |

### 3.6 customer-fields (custom field definitions)

| Method & path | Purpose |
|---|---|
| `GET /api/customer-fields/` | **cap:** `customer.view`. Display order. `?include_inactive=true`. → 200 `CustomerFieldDefinition[]` |
| `POST /api/customer-fields/` | **cap:** `customer_field.manage`. Body `CustomerFieldDefinitionWrite`. `key` defaults to normalized label; immutable. → 201 `CustomerFieldDefinition` |
| `GET /api/customer-fields/{id}/` | → 200 `CustomerFieldDefinition` |
| `PATCH /api/customer-fields/{id}/` | `is_active: false` turns off (values kept). Type locked once values exist; in-use options can't be removed. → 200 |
| `POST /api/customer-fields/reorder/` | Body `{order: [id…]}`; omitted fields follow. → 200 `CustomerFieldDefinition[]` (all, incl. inactive) |

No DELETE — fields are never deleted, only turned off.

### 3.7 orders

**`GET /api/orders/`** → 200 `Paginated<Order>`. Filters: `customer`, `conversation`, `assigned_to`, `recorded_by` (ids) · `status` (`SUGGESTED|RECORDED|CONFIRMED|CANCELLED|REFUNDED`) · `fulfilment_status` (`NEW|PROCESSING|PACKING|SHIPPED|DELIVERED|ON_HOLD|CANCELLED`) · `page` · `page_size`. Visibility follows conversation visibility.

| Method & path | Purpose |
|---|---|
| `POST /api/orders/` | **cap:** `order.manage`. Body `OrderWrite` (only `customer` and `items` required) → 201 `Order` |
| `GET /api/orders/{id}/` | → 200 `Order` |
| `PUT /api/orders/{id}/` | Body `OrderWrite` (items sent whole) → 200 `Order` |
| `PATCH /api/orders/{id}/` | Partial. Fulfilment/payment fields never change `status`. → 200 `Order` |
| `DELETE /api/orders/{id}/` | **cap:** `order.manage` → 204 |
| `POST /api/orders/{id}/confirm/` | Only route to `CONFIRMED`. Body `{note?}` → 200 `Order` |
| `POST /api/orders/{id}/cancel/` | Body `{refunded?: bool, reason?}` → `CANCELLED` or `REFUNDED`; fulfilment → `CANCELLED`. → 200 `Order` |
| `GET /api/orders/{id}/events/` | Append-only history, oldest first. → 200 `OrderEvent[]` |
| `GET /api/orders/export/` | CSV, newest first, accepts list filters. → 200 `text/csv` · 429 |

### 3.8 employees

**`GET /api/employees/`** → 200 `Paginated<Employee>`. Filters: `availability` (`ONLINE|AWAY|BREAK|OFFLINE`), `is_active`, `role`, `team` (id), `search` (first/last name, email), `page`, `page_size`. Reads: `employee.view`; writes: `employee.manage`.

| Method & path | Purpose |
|---|---|
| `POST /api/employees/` | Body `EmployeeWrite` → 201 `Employee` |
| `GET / PUT / PATCH /api/employees/{id}/` | → 200 `Employee` |
| `DELETE /api/employees/{id}/` | **Deactivates** → **200 `Employee`** (not 204) |
| `POST /api/employees/{id}/activate/` | Reactivate → 200 `Employee` |
| `GET /api/employees/online/` | ONLINE or AWAY, for transfer pickers. Filters `availability`, `is_active`, `role`. → 200 `Employee[]` |

### 3.9 teams

| Method & path | Purpose |
|---|---|
| `GET /api/teams/` | **cap:** `team.view`. Filters `is_active`, `language`, `page`, `page_size` → 200 `Paginated<Team>` |
| `POST /api/teams/` | **cap:** `team.manage`. Body `TeamWrite`. Foreign-org ids silently dropped. `responsibilities` = the team's **complete** channel responsibility. → 201 `Team` |
| `GET / PUT / PATCH /api/teams/{id}/` | → 200 `Team` |
| `DELETE /api/teams/{id}/` | **Deactivates** → **200 `Team`** |

### 3.10 routing (auto-assignment) — all need `routing.manage`

| Method & path | Purpose |
|---|---|
| `GET /api/routing/policy/` | Created with defaults on first read (never 404). → 200 `RoutingPolicy` |
| `PATCH /api/routing/policy/` | Body `RoutingPolicyWrite` (all optional). Affects new work only. → 200 `RoutingPolicy` |
| `GET /api/routing/responsibilities/` | Incl. retired rules. → 200 `RoutingResponsibility[]` |
| `POST /api/routing/responsibilities/` | Body `RoutingResponsibilityWrite`: exactly one of `team_id`/`employee_id` **and** exactly one of `provider`/`channel_connection_id`. → 201 |
| `PATCH /api/routing/responsibilities/{id}/` | Only `is_active` may change. → 200 |
| `DELETE /api/routing/responsibilities/{id}/` | **Retires** → **200 `RoutingResponsibility`** |
| `GET /api/routing/workload/` | Live, from audit trail. → 200 `WorkloadPreview` |

### 3.11 channels (connection management)

| Method & path | Purpose |
|---|---|
| `GET /api/channels/` | **cap:** `channel.view`. Filters `is_active`, `provider`, `status` (`PENDING|CONNECTED|DEGRADED|DISCONNECTED|ERROR`), `search`, `ordering`, `page`, `page_size`. Archived excluded. → 200 `Paginated<ChannelConnection>` |
| `POST /api/channels/` | **cap:** `channel.manage`. Body `ChannelConnectionWrite` (`configuration` rejects credentials). → 201 `ChannelConnection` |
| `GET / PUT / PATCH /api/channels/{id}/` | → 200 `ChannelConnection` |
| `DELETE /api/channels/{id}/` | **Must already be disconnected** (else 409). Conversations preserved (erased if none, otherwise archived). → 204 |
| `POST /api/channels/{id}/mute/` · `/unmute/` | Hide/show in inbox; ingestion continues. → 200 `ChannelConnection` |
| `POST /api/channels/{id}/test/` | Read-only provider readiness check. → 200 `ChannelConnectionTestResult` |
| `GET /api/channels/providers/` | → 200 `ProviderCatalogEntry[]` |

### 3.12 integrations (connecting Meta / WhatsApp / Instagram / TikTok) — need `channel.manage`

**OAuth starts** (return a URL; navigate the browser to it):

| Method & path | Body → Response |
|---|---|
| `POST /api/integrations/meta/connect/` | `{return_path?}` → `{authorization_url}` (Messenger/Instagram via Pages) |
| `POST /api/integrations/instagram/authorize/` | `InstagramAuthorizeRequest` → `{authorization_url}` (Business Login for Instagram) |
| `POST /api/integrations/tiktok/authorize/` | `{return_path?}` → `{authorization_url}` |
| `POST /api/integrations/whatsapp/embedded-signup/mobile/start/` | `{mode?: cloud_api|coexistence, return_path?}` → `{authorization_url}` (no-popup devices) |

**Manual / token connects**

| Method & path | Body → Response |
|---|---|
| `POST /api/integrations/instagram/connect/` | `{access_token}` → 201 `ConnectedChannel` |
| `POST /api/integrations/whatsapp/connect/` | `WhatsAppConnectRequest` (token verified with Graph first) → 201 `ConnectedChannel` · 409 |
| `GET /api/integrations/whatsapp/signup-config/` | → `WhatsAppSignupConfig` (params for Meta's Embedded Signup popup) |
| `POST /api/integrations/whatsapp/embedded-signup/attempt/` | `WhatsAppSignupAttemptRequest` — logs the attempt, writes nothing → 200 |
| `POST /api/integrations/whatsapp/embedded-signup/` | `WhatsAppEmbeddedSignupRequest` (popup `code` exchanged server-side) → 201 `WhatsAppEmbeddedSignupResponse` · 409 |
| `POST /api/integrations/whatsapp/{id}/register/` | `{pin}` (6-digit 2FA PIN, never stored) → 200 `ConnectedChannel` · 409, 429, 502, 503 |
| `POST /api/integrations/whatsapp/{id}/check-status/` | Re-read readiness from Meta → 200 `ConnectedChannel` |

**Disconnects** → 200 `ConnectionState` (credential destroyed, conversations kept):
`POST /api/integrations/meta/{id}/disconnect/` · `/instagram/{id}/disconnect/` · `/whatsapp/{id}/disconnect/` · `/tiktok/{id}/disconnect/`

**WhatsApp business profile** (read live from Meta)

| Method & path | Purpose |
|---|---|
| `GET /api/integrations/whatsapp/{id}/business-profile/` | → 200 `WhatsAppBusinessProfile` · 409, 503 |
| `PATCH /api/integrations/whatsapp/{id}/business-profile/` | Body `WhatsAppBusinessProfileUpdate` — only sent fields change; `""` clears. → 200 · 409, 502, 503 |
| `POST /api/integrations/whatsapp/{id}/business-profile/picture/` | *multipart* `file` (JPEG/PNG ≤5 MB) → 200 `{handle}`; then PATCH profile with `profile_picture_handle`. |

**WhatsApp templates**

| Method & path | Purpose |
|---|---|
| `GET /api/integrations/whatsapp/{id}/templates/` | **cap:** `channel.view`. Live from Meta. → 200 `{templates: WhatsAppTemplate[]}` |
| `POST /api/integrations/whatsapp/{id}/templates/` | Submit for review. Body `WhatsAppTemplateCreate` → 201 `WhatsAppTemplate` (status `PENDING`) |
| `POST /api/integrations/whatsapp/{id}/templates/send/` | Outbound send from this number (may differ from customer's last). Body `WhatsAppTemplateSend` — exactly one of `customer_id` / `phone`. → 201 `TemplateOutreachResult` · 429 |

**Called by Meta/TikTok, not by clients** (public, don't call from app code):
`GET /api/integrations/meta/callback/`, `GET /api/integrations/instagram/callback/`, `GET /api/integrations/tiktok/account/callback/` (OAuth redirects → 302) · `GET|POST /api/integrations/meta/webhook/` (`X-Hub-Signature-256`) · `POST /api/integrations/tiktok/webhook/` (`Tiktok-Signature`).

### 3.13 saved replies

| Method & path | Purpose |
|---|---|
| `GET /api/saved-replies/` | **cap:** `conversation.reply`. Caller's personal + team + org replies, active, most specific first. `?search` (title/shortcut/text), `?manageable=true` (ones caller can edit, incl. inactive). → 200 `Paginated<SavedReply>` |
| `POST /api/saved-replies/` | Body `SavedReplyWrite`. `scope`: `personal` (anyone) / `team` (`saved_reply.manage` or team leader) / `organization` (`saved_reply.manage`). → 201 `SavedReply` |
| `GET /api/saved-replies/{id}/` | → 200 `SavedReply` |
| `PATCH /api/saved-replies/{id}/` | Scope immutable; `is_active: true` restores. → 200 |
| `DELETE /api/saved-replies/{id}/` | **Deactivates** → **200 `SavedReply`**, shortcut released |
| `POST /api/saved-reply-assets/` | *multipart* `AssetUpload` (`file`, `saved_reply_id?`, `is_voice?`, `duration_ms?`). Replaces existing file. Omit `saved_reply_id` to create reply + file in one go. → 201 `SavedReply` |
| `DELETE /api/saved-reply-assets/{id}/` | Remove file (sent messages keep theirs). → 200 `SavedReply` |
| `GET /api/saved-reply-assets/{public_id}/content/` | Download/play (uuid, `Range` → 206). |

**Saved-reply categories**

| Method & path | Purpose |
|---|---|
| `GET /api/saved-reply-categories/` | **cap:** `conversation.reply` → 200 `Paginated<SavedReplyCategory>` |
| `POST /api/saved-reply-categories/` | **cap:** `saved_reply.manage`. Body `{name}` → 201 |
| `PATCH /api/saved-reply-categories/{id}/` | Rename `{name}` → 200 |
| `DELETE /api/saved-reply-categories/{id}/` | Replies become uncategorized. → 204 |
| `POST /api/saved-reply-categories/reorder/` | Body `{ids: [all category ids in order]}` → 200 `Paginated<SavedReplyCategory>` |

### 3.14 dashboard & analytics

| Method & path | Purpose |
|---|---|
| `GET /api/dashboard/` | `?preset=today|last_7_days|last_30_days|this_month|last_month` or `?from=YYYY-MM-DD&to=YYYY-MM-DD` (≤366 days, local dates). → 200 `DashboardSummary` (`team` is `null` without `analytics.view`) |
| `GET /api/dashboard/channels/` | **cap:** `analytics.view` → 200 `ChannelBreakdownRow[]` |
| `GET /api/dashboard/performance/` | Agents see themselves, team leaders their teams, ADMIN/SUPERVISOR/QA everyone. `?days=` (1–90, default 14) or `preset`/`from`/`to`, `?employee=`. → 200 `EmployeePerformanceResponse` |
| `GET /api/metrics/` | **cap:** `channel.manage`. Always 200 even when degraded. → `MetricsResponse` |
| `GET /api/health/` | Public probe. → 200 `HealthResponse` (`degraded` still 200) · 503 |

### 3.15 notifications (ADMIN, `notification.view`)

| Method & path | Purpose |
|---|---|
| `GET /api/notifications/` | Newest first. → 200 `Paginated<Notification>` |
| `GET /api/notifications/{id}/` | → 200 `Notification` |
| `POST /api/notifications/{id}/read/` | Idempotent → 200 `Notification` |
| `POST /api/notifications/read-all/` | → 200 (no schema) |
| `GET /api/notifications/unread-count/` | → 200 (no schema; inspect response) |

### 3.16 devices (push notifications — mobile app)

| Method & path | Purpose |
|---|---|
| `POST /api/devices/register/` | Call on every launch and token rotation. Idempotent on `device_identifier`; owner = session. Body `DeviceRegisterRequest` → 201 (new) / 200 (existing) `DeviceRegisterResponse` |
| `POST /api/devices/heartbeat/` | Body `{device_identifier, push_token?}` → 200 `{last_active_at}` · 404 if unknown (re-register) |
| `POST /api/devices/unregister/` | On sign-out. Body `{device_identifier}` → always 204 |

### 3.17 Facebook Page engagement (read-only)

| Method & path | Purpose |
|---|---|
| `GET /api/page-engagement/availability/` | Per Page: can read posts/comments, can moderate, missing permissions. → 200 `PageAvailability[]` |
| `GET /api/page-posts/` | → 200 `Paginated<PagePost>` (empty while permissions ungranted) |
| `GET /api/page-posts/{public_id}/` | uuid → 200 `PagePost` |
| `GET /api/page-comments/` | → 200 `Paginated<PageComment>` |
| `GET /api/page-comments/{public_id}/` | → 200 `PageComment` |
| `GET /api/page-comments/{public_id}/replies/` | Oldest first → 200 `Paginated<PageComment>` |

### 3.18 client-errors

`POST /api/client-errors/` — report a front-end crash. Body `ClientErrorReport` (all optional, truncated server-side). Always 204 (401 if no session, 429 if throttled).

---

## 4. Schemas

Legend: `?` = optional on write · `| null` = nullable · `ro` = read-only (ignored on write) · `wo` = write-only (never returned) · `≤N` = max length · dates are ISO-8601 strings, `decimal` is a string like `"120.50"`. Response-only schemas list every field as always present.

### 4.1 Auth & employees

```
Login                { email: string; password: string (wo) }
LoginResponse        { employee: CurrentEmployee; csrf_token: string }
CsrfTokenResponse    { csrf_token: string }
PasswordChange       { current_password: string (wo); new_password: string (wo) }
Availability         { availability: AvailabilityEnum }

Employee {
  id, public_id (uuid) ro
  email: string ≤254; first_name: string ≤80; last_name?: string ≤80
  full_name, initials, role_display: string ro
  role?: RoleEnum; availability?: AvailabilityEnum
  avatar_url?: url|""; phone?: ≤32; title?: ≤120; language?: "ar"|"en"|""
  is_active?: bool
  teams: TeamBrief[] ro
  last_seen_at: datetime|null ro
  max_open_chats?: int|null (0–32767; null = org default)
  effective_capacity: int ro          // override else org default
  routing_blocker: string ro; is_routing_ready: bool ro
  working_hours: WorkingHoursWindow[] ro
  work_schedule: WorkScheduleBrief|null ro
  routing_channel_scope?: "ALL"|"SELECTED"
  routing_providers: string[] ro; routing_connection_ids: int[] ro
  created_at, updated_at ro
}
CurrentEmployee = Employee + {
  permissions: string[]             // capability list for UI gating
  visibility_scope: string
  organization: OrganizationBrief|null
  channel_availability: map<string,string>
}
EmployeeWrite {                      // POST/PUT; PATCH = all optional
  email: string; first_name: string; last_name?; role?; availability?
  avatar_url?; phone?; title?; language?; is_active?
  password?: string (wo)
  team_ids?: int[] (wo)
  max_open_chats?: int|null (0–200)
  working_hours?: object[] (wo); work_schedule_id?: int|null (wo)
  routing_channel_scope?: "ALL"|"SELECTED"
  routing_providers?: ("TIKTOK"|"INSTAGRAM"|"FACEBOOK"|"WHATSAPP")[] (wo)
  routing_connection_ids?: int[] (wo)
}
EmployeeBrief        { id; full_name; initials; avatar_url; availability }
OrganizationBrief    { id; name; slug; timezone }
WorkScheduleBrief    { id; name; is_personal: bool; timezone }
WorkingHoursWindow   { weekday: int (0=Monday); start_time: "HH:MM"; end_time: "HH:MM"; crosses_midnight: bool }
```

### 4.2 Teams & routing

```
Team {
  id, public_id ro; name: ≤120; description?; language?: ≤10; color?: ≤7 (hex); is_active?
  members: TeamMember[] ro; leaders: TeamMember[] ro; member_count ro; created_at, updated_at ro
}
TeamWrite { name; description?; language?; color?; is_active?; member_ids?: int[]; leader_ids?: int[]; responsibilities?: TeamResponsibilityInput[] }
TeamResponsibilityInput { provider: RoutableProvider; scope: "all"|"selected"; strict?: bool=false; channel_connection_ids?: int[] }
TeamBrief  { id; name; color }
TeamMember { id; full_name; email; role; availability; last_seen_at: datetime|null; avatar_url; initials }

RoutingPolicy {
  is_enabled?: bool; workload_window?: "1h"|"24h"|"7d"|"30d"
  max_open_chats_per_agent?: int (1–200)
  first_response_sla_seconds?: int
  sticky_conversation_ownership?: bool; escalation_max_hops?: int (0–20)
  allow_connection_fallback?: bool; allow_escalation_outside_pool?: bool
  timezone: string ro; heartbeat_max_seconds: int ro
}
RoutingPolicyWrite (PATCH) — same writable fields, all optional; first_response_sla_seconds 60–86400; escalation_max_hops 1–20; timezone?: string
RoutingResponsibility {
  id; team: {id,name,is_active}|null; employee: {id,full_name,is_active}|null
  provider: string; channel_connection: {id,display_name,provider,is_active}|null
  strict: bool; is_active: bool; target_has_routing_access: bool|null; created_at; updated_at
}
RoutingResponsibilityWrite { team_id?: int|null; employee_id?: int|null; provider?: RoutableProvider|""; channel_connection_id?: int|null; strict?: bool=false }
WorkloadPreview { workload_window; window_seconds; window_start; window_end; timezone; employees: WorkloadRow[] }
WorkloadRow { id; full_name; role; is_active; availability; received: int; open_conversations: int; capacity: int; routable: bool; blocked_by: string[] }
```

### 4.3 Conversations

```
ConversationList {
  id, public_id ro
  customer: CustomerBrief; provider: string; channel_name: string; channel_id: int
  assigned_to: EmployeeBrief|null; assigned_team: TeamBrief|null
  status: ConversationStatus; priority: Priority
  category: Category|null; custom_state: ConversationCustomStateBrief|null
  unread_count: int; message_count: int
  last_message_preview: string ≤280; last_message_direction: string; last_message_delivery_status: string
  last_message_at: datetime|null; started_at: datetime
  intelligence: IntelligenceBrief|null
  is_follow_up: bool; is_pinned: bool; review: ReviewRequest|null
  follow_up_date: date|null; follow_up_marked_at: datetime|null; follow_up_marked_by_name: string
}
ConversationDetail = ConversationList but intelligence: ConversationIntelligence|null, plus {
  external_conversation_id: string; customer_identity_username: string
  subject: string ≤255; rolling_summary: string
  assigned_at, resolved_at, first_response_at, last_customer_message_at, last_agent_message_at: datetime|null
  claimed_by: EmployeeBrief|null
  created_at; updated_at
  media_capabilities: map<string,object>
  messaging_policy: MessagingPolicy|null
  attribution: map|null                    // first & latest referral seen
}
ConversationGroup {
  group_key: string; customer: CustomerBrief; conversation_count; unread_conversations; unread_count; is_unread: bool
  last_message_at; last_message_preview; last_message_direction; last_message_delivery_status
  providers: string[]; accounts: string[]; is_pinned; pinned_at: datetime|null
  review: ReviewRequest|null; review_conversation_id: int|null
  conversations: ConversationList[]
}
ConversationCounts  { all; mine; unassigned; new; open; waiting; resolved; unread; review_mine }   // ints
InboxChannel        { id; provider; display_name; is_active; is_muted }
MarkReadResponse    { unread_count: 0 }
MessagingPolicy     { state: "no_customer_message"|"initial"|"active"|"inactive"; allowed: bool; remaining_count: int|null; window_expires_at: datetime|null; reason: string }
ReviewRequest       { id; status; note; reviewer_id: int|null; reviewer_name; requested_by_id: int|null; requested_by_name; requested_at }
ConversationCustomStateBrief { id; label; color; base_status; is_active }

ConversationEvent { id; event_type: ConversationEventType; actor_name; target_employee_id: int|null; target_employee_name; from_value; to_value; metadata: object; created_at }
InternalNote      { id; public_id; body: string; author_name; author_initials; created_at; updated_at }
```

**Write bodies**
```
Assign          { assignee_id?: int|null; team_id?: int|null; note?: string ≤255 }   // omitted = unchanged, null = release
Status          { status?: ConversationStatus; custom_state_id?: int|null }           // send exactly one
Priority        { priority: Priority }
CategoryUpdate  { category_id: int|null }
FollowUp        { is_follow_up: bool; follow_up_date?: date|null }
NoteCreate      { body: string ≤8000 }
ReviewRequestInput { reviewer_id: int; note?: string ≤280 }
LeadScoreRequest   { score: int (0–100)|null }                                         // null = back to analyzer
ConfirmPurchaseRequest { confirmed: bool; note?: string ≤255 }                         // false = record "not yet"
Reply {
  text?: string ≤8000 (default "")            // optional when attachment_ids present
  message_type?: MessageType = "TEXT"
  reply_to_id?: int|null                       // quote a message
  attachment_ids?: uuid[]                      // AttachmentDraft ids
  client_message_id?: string ≤64               // your idempotency/optimistic-UI key
}
SendTemplate    { template_name: string ≤512; language: string ≤16; parameters?: string[] }
SavedReplyAttachment { saved_reply_id: int }
```

### 4.4 Messages & attachments

```
Message {
  id; public_id
  direction: "INBOUND"|"OUTBOUND"; sender_type: "CUSTOMER"|"AGENT"|"SYSTEM"
  sender_name; sender_initials
  message_type: MessageType; text: string
  attachments: object[]
  delivery_status: "PENDING"|"SENT"|"DELIVERED"|"READ"|"FAILED"|"RECEIVED"
  delivery_error: string; delivery_error_code: string
  content_notice: object|null; referral: object|null
  client_message_id: string
  sent_at; delivered_at: datetime|null; read_at: datetime|null
  reply_to: QuotedMessage|null
  sent_from_platform: bool            // typed in the native app, not here
  edited_at: datetime|null; is_edited: bool; is_revoked: bool; deletion_source: string
}
QuotedMessage  { id: int|null; text; truncated: bool; message_type; direction; sender_name; sent_at; is_deleted: bool; available: bool }
AttachmentDraft { id: uuid; type; mime_type; file_name; size_bytes: int; is_voice: bool; duration_ms: int|null; expires_at: datetime }
```

### 4.5 Intelligence & conversions

```
ConversationIntelligence {     // all read-only
  stage: SalesStage; confidence: number
  purchase_status: PurchaseStatus; purchase_evidence; purchase_intent: string
  intent_strength, urgency: "none"|"low"|"medium"|"high"
  sentiment: "positive"|"neutral"|"negative"|"mixed"
  interested_products, objections, buying_signals: object; quantity_signal: string
  summary: string; next_best_action: string
  lead_score: int; lead_score_signals: object; lead_score_auto: int; lead_score_override: int|null
  is_lead_score_overridden: bool; lead_score_overridden_by_name; lead_score_overridden_at: datetime|null
  needs_human_review: bool; review_reason: string
  is_purchase_claim_pending: bool; is_agent_confirmed: bool
  confirmed_by_name; purchase_confirmed_at: datetime|null; purchase_confirmation_note
  analysis_version; analyzer_key; analyzed_at: datetime|null
}
IntelligenceBrief     { stage; lead_score: int; purchase_status; needs_human_review: bool }
PurchaseConfirmation  { id; decision: "CONFIRMED"|"REJECTED"; previous_status: PurchaseStatus; evidence; note; employee_name; decided_at }
ConversionEvent       { id; event_name; source_stage; source_purchase_status; status: "SENT"|"FAILED"|"NOT_CONFIGURED"|"SKIPPED"|"UNMATCHABLE"; events_received: int; error_message; value: decimal|null; currency; created_at }
ReportConversionResponse { status: string /* "already_reported" or lower-cased ConversionEvent status */; detail; event_name; stage; intelligence: ConversationIntelligence }
```

### 4.6 Conversation states & categories

```
Category { id ro; slug: ≤60; label: ≤80; color?: ≤7; is_system: bool ro; is_active?: bool; display_order?: int }
ConversationCustomState { id ro; slug ro; label: ≤80; color?: ≤7; base_status?: ConversationStatus (create only); is_active ro; display_order?: int; conversation_count ro }
ConversationStateDistribution { system: {status, count, is_visible}[]; custom: {id,label,color,base_status,is_active,count}[]; total: int }
SystemStateVisibility { status; label; custom_label; default_label; is_visible: bool; is_terminal: bool }
SystemStateVisibilityUpdate (PATCH) { hidden?: string[]; labels?: {[status]: string} }
```

### 4.7 Customers & custom fields

```
CustomerBrief { id; public_id; display_name; avatar_url; lifecycle_stage; preferred_language; email; phone; country; city }
CustomerList {
  id, public_id ro; display_name: ≤160; email?: email|""; phone?: ≤32; avatar_url?
  preferred_language?: ≤10; country?: ≤64; city?: ≤96
  lifecycle_stage?: CustomerLifecycle; lifecycle_confirmed_by_employee?: bool; tags?: object
  identities: CustomerIdentity[] ro; conversation_count ro
  first_seen_at?; last_seen_at?
}
CustomerDetail = CustomerList + { notes?: string; facts: object[] ro; confirmed_purchase_count ro; created_at; updated_at }
CustomerWrite  { display_name: ≤160; email?; phone?; preferred_language?; country?; city?; lifecycle_stage?; tags?: object; notes? }
CustomerIdentity { id ro; provider: Provider; external_id: ≤191; username?; display_name?; avatar_url?; last_interaction_at? }

CustomerFact {
  id ro; key: ≤80; value: string; confidence?: number; source?: "ANALYZER"|"EMPLOYEE"
  status: "SUGGESTED"|"CONFIRMED"|"REJECTED" ro; needs_review ro
  created_by_name, reviewed_by_name ro; reviewed_at ro
  conversation?: int|null; is_active?; definition: int|null ro; validation_error: string|null ro; created_at; updated_at
}
CustomerFactWrite  { key: ≤80; value: string; conversation?: int|null }
CustomerFactReview { confirmed: bool; value?: string }

CustomerFieldDefinition { id; key; label; field_type: FieldType; field_type_display; options: {value,label}[]; required: bool; is_active: bool; display_order: int; help_text; placeholder; created_at; updated_at }
CustomerFieldDefinitionWrite { key?: ≤80; label: ≤120; field_type: FieldType; options?: object; required?; is_active?; display_order?: 0–10000; help_text?: ≤255; placeholder?: ≤120 }
CustomerFieldValue { definition: CustomerFieldDefinition; value: any|null; fact_id: int|null; updated_at: datetime|null; updated_by_name }
CustomerFieldValuesWrite (PATCH) { values?: {[key]: any|null}; conversation?: int|null }
CustomerFieldReorder { order: int[] }
```

### 4.8 Orders

```
Order {
  id, public_id ro
  customer: int; customer_name ro; conversation?: int|null
  status: OrderStatus ro; status_display ro; source: "EMPLOYEE"|"ANALYZER" ro; is_claim: bool ro
  recorded_by: int|null ro; recorded_by_name ro; confirmed_by: int|null ro; confirmed_by_name ro; confirmed_at ro
  total_amount, subtotal: decimal ro; discount?, shipping_cost?: decimal; currency?: ≤3
  external_reference?: ≤120; evidence?; note?: ≤255; internal_note?
  placed_at?; cancelled_at ro; cancellation_reason ro
  recipient_name?: ≤160; recipient_phone?: ≤32; alternative_phone?: ≤32
  address?: ≤500; governorate?: ≤80; city?: ≤80; landmark?: ≤200; location_url?; delivery_notes?
  expected_delivery_date?: date|null; shipping_method?: ≤80
  payment_method?: PaymentMethod|""; payment_status?: PaymentStatus|""
  fulfilment_status?: FulfilmentStatus; fulfilment_status_display ro
  assigned_to?: int|null; assigned_to_name ro; assigned_team?: int|null; assigned_team_name ro
  items: OrderItem[] ro; created_at; updated_at
}
OrderItem      { id ro; product_name: ≤200; quantity?: int ≥1; unit_price?: decimal; line_total: decimal ro; note?: ≤255; position?: int }
OrderWrite {
  customer: int; items: OrderItemWrite[]        // the only required fields
  conversation?: int|null; currency?; external_reference?; note?; internal_note?: ≤4000
  discount?; shipping_cost?; recipient_name?; recipient_phone?; alternative_phone?
  address?; governorate?; city?; landmark?; location_url?; delivery_notes?: ≤4000
  expected_delivery_date?; shipping_method?; payment_method?; payment_status?
  fulfilment_status?: NEW|PROCESSING|PACKING|SHIPPED|DELIVERED|ON_HOLD   // not CANCELLED; use /cancel/
  assigned_to?: int|null; assigned_team?: int|null
}
OrderItemWrite { product_name: ≤200; quantity?: int = 1; unit_price?: decimal = "0.00"; note?: ≤255 }
ConfirmOrder   { note?: ≤255 }
CancelOrder    { refunded?: bool = false; reason?: ≤255 }
OrderEvent     { id; event_type: OrderEventType; event_type_display; actor: int|null; actor_name; before: object; after: object; metadata: object; created_at }
```

### 4.9 Channels & integrations

```
ChannelConnection {
  id, public_id ro; provider: Provider; provider_display ro
  external_account_id: ≤191; display_name: ≤160; avatar_url?
  status?: ChannelConnectionStatus; status_detail ro
  is_active?; is_operational ro; has_credentials ro
  token_expires_at: datetime|null ro; token_days_remaining: int|null ro
  is_muted ro; muted_at ro; muted_by_name ro
  connection_mode: string ro            // WhatsApp: "cloud_api" | "coexistence"
  readiness_status: string ro; setup_completion: object ro
  tiktok_readiness: TikTokReadiness|null ro
  conversation_count ro; connected_at, last_sync_at, last_message_at: datetime|null ro; created_at; updated_at
}
ChannelConnectionWrite { provider: Provider; external_account_id: ≤191; display_name: ≤160; avatar_url?; is_active?; configuration?: object }
ChannelConnectionTestResult { ok: bool; detail; warning; readiness?: object }
ProviderCatalogEntry { provider; label; is_operational: bool }
TikTokReadiness { state: "READY"|"BLOCKED"|"UNKNOWN"; reason; provider_code: int|null; request_id; log_id; missing_scopes: string[]; checked_at: datetime|null }

ConnectedChannel { id: int; display_name; status; detail }
ConnectionState  { status; detail }
InstagramAuthorizeRequest { return_path?: string = "/settings"; mode?: "MIGRATE_TO_DIRECT"; connection_id?: int (required with MIGRATE_TO_DIRECT) }
InstagramConnectRequest   { access_token: string (wo) }
MetaConnectStartRequest / TikTokAuthorizeRequest { return_path?: string = "/settings" }
*AuthorizeResponse / MetaConnectStartResponse / WhatsAppMobileSignupStartResponse { authorization_url: string }

WhatsAppConnectRequest { phone_number_id: string; access_token: string (wo); waba_id?: string }
WhatsAppSignupConfig { enabled: bool; app_id; config_id; graph_api_version; coexistence_enabled: bool; coexistence_config_id }
WhatsAppSignupAttemptRequest { mode: "cloud_api"|"coexistence"; transport?: "popup"|"redirect"; selected_option?: "existing_number"|"new_number" }
WhatsAppEmbeddedSignupRequest { code: string (wo); waba_id?; phone_number_id?; business_id?; coexistence?: bool = false }
WhatsAppEmbeddedSignupResponse { waba_id; business_id; connection_mode; connected: ConnectedChannel[]; warnings: string[] }
WhatsAppMobileSignupStartRequest { mode?: "cloud_api"|"coexistence" = "cloud_api"; return_path?: string = "/settings" }
WhatsAppRegisterRequest { pin: string (wo, 6 digits) }

WhatsAppBusinessProfile { about; address; description; email; vertical; websites: string[]; profile_picture_url; editable: bool; account: {display_phone_number, phone_number_id, waba_id, verified_name} }
WhatsAppBusinessProfileUpdate (PATCH) {
  about?: ≤139; address?: ≤256; description?: ≤512; email?; vertical?: Vertical|""; websites?: url[]
  profile_picture_handle?: string        // from /business-profile/picture/
  if_unchanged?: { about?, address?, description?, email?, vertical?, websites? }   // undocumented in schema; check server code before using
}
WhatsAppProfilePictureResponse { handle: string }

WhatsAppTemplate { id; name; language; category: "MARKETING"|"UTILITY"|"AUTHENTICATION"; status /* APPROVED|PENDING|REJECTED|PAUSED|IN_APPEAL|DISABLED */; body: ≤1024; rejected_reason; variables: int; can_send: bool; unsupported: string[] }
WhatsAppTemplateCreate { name; category; language: ≤16; body?: ≤1024; add_security_recommendation?: bool = false; code_expiration_minutes?: int 1–90|null; button_text?: ≤25 }
WhatsAppTemplateSend { template_name: ≤512; language: ≤16; parameters?: string[]; customer_id?: int|null; phone?: ≤32 }   // exactly one of customer_id / phone
TemplateOutreachResult { message: Message; conversation_id: int; conversation_created: bool; customer_id: int; customer_name; wa_id: string }
```

### 4.10 Saved replies

```
SavedReply {
  id; public_id; title; shortcut; body; category: string; category_id: int|null; category_position: int|null; position: int
  assets: SavedReplyAsset[]; scope: "personal"|"team"|"organization"; team: {id,name}|null
  is_active: bool; can_edit: bool; created_at; updated_at
}
SavedReplyAsset { id; public_id; attachment_type: MessageType; mime_type; original_filename; size_bytes; is_voice; metadata: object; content_url: string }
SavedReplyWrite { title: ≤120; shortcut?: ≤40; body?: ≤4096; category?: ≤60; category_id?: int|null; scope?: SavedReplyScope (create only); team_id?: int|null (create only); is_active? }
AssetUpload (multipart) { file: binary; saved_reply_id?: int; is_voice?: bool = false; duration_ms?: int|null }
SavedReplyCategory { id; public_id; name; position; reply_count; created_at; updated_at }
SavedReplyCategoryWrite { name: ≤60 }
Reorder { ids: int[] }
```

### 4.11 Dashboard, metrics, health

```
DashboardSummary { conversations: ConversationCountsBlock; intelligence: IntelligenceBlock; period: Period; team: TeamBlock|null; recent_conversations: ConversationList[] /* 8 most recent open */; generated_at }
ConversationCountsBlock { open; new; unassigned; waiting; resolved; unread; mine_open }
IntelligenceBlock { qualified_leads; hot_leads; purchase_claims; agent_confirmed_purchases; pending_review; average_lead_score: number }
Period { preset; start_at /* inclusive UTC */; end_at /* exclusive UTC */; timezone; from: date; to: date /* inclusive local */ }
TeamBlock { online_agents: int; workload: {id, full_name, initials, avatar_url, availability, open_conversations, unread_conversations}[] }
ChannelBreakdownRow { provider; total; open; unread }

EmployeePerformanceResponse { window: {days, start, end}; results: EmployeePerformance[] }
EmployeePerformance {
  employee_id; full_name; initials; role; avatar_url; availability
  conversations_handled; conversations_resolved
  average_response_seconds: number|null; median_response_seconds: int|null; first_response_average_seconds: number|null; responses_counted
  lead_score_at_assignment, lead_score_now, lead_score_lift, lead_score_lift_percent: number|null; scored_conversations
  messages_sent; customers_served; platforms: {provider, messages, customers, conversations}[]
  hours: { scheduled_seconds, online_seconds, away_seconds, break_seconds: int; has_session_data: bool; adherence: number|null }
  orders_recorded; orders_confirmed; confirmed_order_value: string; currency
}

HealthResponse { status: "ok"|"degraded"|"unhealthy"; database: bool; realtime: RealtimeHealth }
RealtimeHealth { published; failed; last_failure_at: datetime|null; last_failure_detail; degraded: bool }
MetricsResponse {
  status: "ok"|"degraded"; problems: string[]        // realtime | tasks | broker | queue_depth | channels
  realtime: RealtimeHealth
  tasks: { succeeded; failed; inline_fallbacks; last_failure_at; last_failure_detail; degraded }
  queues: { enabled: bool; reachable?; error?; ingest?; analysis?; backlogged? }
  webhooks: { accepted; rejected; failed; error_rate: number }
  ingestion: { messages; messages_per_second: number|null; p50_ms: number|null; p95_ms: number|null; window: int }
  channels: { active; degraded; error; unhealthy: {name, provider}[] }
  audit: { routing_decisions; conversion_events }
}
```

### 4.12 Notifications, devices, pages, misc

```
Notification { id; kind: NotificationKind; severity: "INFO"|"WARNING"|"CRITICAL"; title_code; context: object; conversation: int|null; employee: int|null; employee_name; occurrence_count; is_read: bool; resolved_at: datetime|null; created_at; updated_at }

DeviceRegisterRequest  { device_identifier: string; platform: "ANDROID"|"IOS"|"WEB"; push_token?: string (wo, ≤4096); app_version?: string; device_model?: string }
DeviceRegisterResponse { id; device_identifier; platform; notifications_enabled: bool; created: bool }
DeviceHeartbeatRequest { device_identifier: string; push_token?: string (wo) }
DeviceHeartbeatResponse { last_active_at: datetime }
DeviceUnregisterRequest { device_identifier: string }

PageAvailability { connection_id; connection: uuid; display_name; provider; can_read_posts; can_read_comments; can_moderate_comments; missing_permissions: string[]; moderation_missing_permissions: string[]; requires_app_review: bool; feed_subscribed: bool }
PagePost    { id: uuid; external_post_id; message; permalink; published_at: datetime|null; comment_count; media: object; is_stub: bool }
PageComment { id: uuid; post: uuid; parent: uuid|null; external_comment_id; author_name; author_external_id; message; created_time; edited_at; is_hidden; is_deleted; deleted_at; attachment: object; source }

ClientErrorReport { section?: ≤60; message?: ≤500; path?: ≤200; stack?: ≤4000; component_stack?: ≤4000 }
ApiError { error: { code: string; message: string; details: object } }
```

### 4.13 Enums

```
ConversationStatus      NEW | OPEN | WAITING_CUSTOMER | WAITING_INTERNAL | RESOLVED | CLOSED
Priority                LOW | NORMAL | HIGH | URGENT
Provider                TIKTOK | INSTAGRAM | FACEBOOK | WHATSAPP | MOCK
RoutableProvider        TIKTOK | INSTAGRAM | FACEBOOK | WHATSAPP
ChannelConnectionStatus PENDING | CONNECTED | DEGRADED | DISCONNECTED | ERROR
Role                    ADMIN | SUPERVISOR | TEAM_LEADER | AGENT | QA
Availability            ONLINE | AWAY | BREAK | OFFLINE
Language                ar | en
MessageType             TEXT | IMAGE | VIDEO | AUDIO | FILE | STICKER | TEMPLATE | SYSTEM
SalesStage              NEW_LEAD | LEAD | QUALIFIED_LEAD | HOT_LEAD | LOST | UNCERTAIN
PurchaseStatus          NONE | INTENT_DETECTED | CUSTOMER_SAYS_ORDERED | CUSTOMER_SAYS_PAID | AGENT_CONFIRMED | CANCELLED | REFUND_MENTIONED
CustomerLifecycle       UNKNOWN | NEW_CUSTOMER | PROSPECT | EXISTING_CUSTOMER | REPEAT_BUYER
FieldType               TEXT | LONG_TEXT | NUMBER | DECIMAL | DATE | DATETIME | BOOLEAN | SELECT | MULTI_SELECT | PHONE | EMAIL
OrderStatus             SUGGESTED | RECORDED | CONFIRMED | CANCELLED | REFUNDED
FulfilmentStatus        NEW | PROCESSING | PACKING | SHIPPED | DELIVERED | ON_HOLD | CANCELLED
PaymentMethod           CASH_ON_DELIVERY | BANK_TRANSFER | CARD | WALLET | OTHER
PaymentStatus           UNPAID | PARTIALLY_PAID | PAID | REFUNDED
OrderEventType          RECORDED | SUGGESTED | DETAILS_CHANGED | ITEMS_CHANGED | STATUS_CHANGED | CONFIRMED | CANCELLED | FULFILMENT_CHANGED | PAYMENT_CHANGED | ASSIGNED
SavedReplyScope         personal | team | organization
NotificationKind        FALLBACK_ASSIGNMENT | EMPLOYEE_DEACTIVATED_REASSIGNMENT | NO_USABLE_EMPLOYEE | CHANNEL_ACTION_REQUIRED
WhatsAppVertical        ALCOHOL | APPAREL | AUTO | BEAUTY | EDU | ENTERTAIN | EVENT_PLAN | FINANCE | GOVT | GROCERY | HEALTH | HOTEL | NONPROFIT | ONLINE_GAMBLING | OTC_DRUGS | OTHER | PHYSICAL_GAMBLING | PROF_SERVICES | RESTAURANT | RETAIL | TRAVEL
ConversationEventType   CONVERSATION_CREATED | ASSIGNED | UNASSIGNED | TRANSFERRED | CLAIM_RELEASED | TEAM_ASSIGNED | STATUS_CHANGED |
                        CONVERSATION_RESOLVED | RESOLUTION_UNDONE | CONVERSATION_REOPENED | REVIEW_REQUESTED | REVIEW_COMPLETED |
                        REVIEW_CANCELLED | REVIEW_RETARGETED | PRIORITY_CHANGED | CATEGORY_CHANGED | NOTE_ADDED | FOLLOW_UP_MARKED |
                        FOLLOW_UP_DATE_CHANGED | FOLLOW_UP_REMOVED | MESSAGE_DELETED | PURCHASE_CONFIRMED | PURCHASE_REJECTED |
                        INTELLIGENCE_REFRESHED | LEAD_SCORE_OVERRIDDEN | LEAD_SCORE_RESET | CONVERSION_REPORTED | ORDER_RECORDED |
                        ORDER_CONFIRMED | ORDER_CANCELLED | ORDER_FULFILMENT_CHANGED | ORDER_ASSIGNED
```
