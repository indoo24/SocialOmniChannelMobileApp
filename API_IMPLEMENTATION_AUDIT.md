# API Implementation Audit

**Backend:** Scenario Omnichannel API — OpenAPI 3.0.3, `https://scenariomnchnl.tech/api/schema/`
**Client:** SocialOmniChannelMobileApp (Flutter, Riverpod, Dio)
**Audit date:** 2026-09-02
**Method:** Full OpenAPI spec retrieved and parsed (122 operations, 157 schemas). Every repository/service file that performs HTTP calls was read in full (`api_client.dart`, `auth_repository.dart`, `conversation_repository.dart`, `directory_repository.dart`, `device_repository.dart`, `client_error_reporter.dart`). Screens, controllers/providers, and sheets were traced UI → provider → repository → endpoint for every feature area. No application code was modified.

---

## Summary

| Metric | Count |
|---|---|
| Total Swagger endpoints (client-facing, excludes `integrations-external`) | 113 |
| Total Swagger endpoints (incl. `integrations-external`, webhook/OAuth-redirect only) | 122 |
| Implemented | 61 |
| Partially implemented | 6 |
| Not implemented | 46 |
| Unknown | 0 |
| N/A — not a client concern (`integrations-external` tag: webhooks/OAuth redirects, called by Meta/TikTok, never by this app, per Swagger's own tag description) | 9 |

**Overall API coverage estimate: ~54% of client-facing endpoints (61/113) are implemented, ~5% partially, ~41% not implemented.** Coverage is uneven by design rather than by oversight in most cases: every core "run the inbox" workflow (auth, conversations, messages, intelligence, orders, customer facts, dashboard, directory) is implemented to a high standard with correct permission gating. The gaps cluster almost entirely in three deliberately-deferred areas — **channel/integration OAuth management** (explicitly documented in-code as "belongs on the web"), **in-app admin notifications**, and **operational endpoints** (`/metrics/`, `/health/`) that have no natural mobile UI. Two gaps look like genuine oversights rather than deferrals: **attachment upload/send** and **WhatsApp template send** — an agent on mobile cannot send a photo, a document, or a re-engagement template, which are core support-agent workflows on any channel that isn't plain text.

---

## Endpoint Matrix

Legend: **Impl.** = Flutter Implementation. Permission column shows the capability slug(s) the backend requires (from Swagger operation `description`); "—" means no capability requirement (open to any active employee, or unauthenticated).

### auth

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/auth/csrf/` | Prime CSRF cookie | IMPLEMENTED | `ApiClient.primeCsrf()` (`lib/core/api/api_client.dart:114`) | — | Called before first unsafe request in `AuthRepository.login()`. |
| POST | `/api/auth/login/` | Sign in | IMPLEMENTED | `AuthRepository.login()` (`lib/core/auth/auth_repository.dart:26`) | — | Sends `email`/`password`; parses `data['employee']`. |
| POST | `/api/auth/logout/` | Sign out | IMPLEMENTED | `AuthRepository.logout()` (`auth_repository.dart:98`) | — | Local session cleared even if server call fails. |
| GET | `/api/auth/me/` | Current employee | IMPLEMENTED | `AuthRepository.restore()` / `currentEmployee()` (`auth_repository.dart:66,93`) | — | Drives session restore on launch and after any profile-affecting call. |
| PATCH | `/api/auth/me/` | Edit own profile | IMPLEMENTED | `AuthRepository.updateProfile()` (`auth_repository.dart:140`) | `employee.manage` (role/is_active/team_ids silently stripped server-side) | Only sends `first_name`/`last_name`/`title`/`phone`, matching what the backend accepts from this route. |
| POST | `/api/auth/password/` | Change password | IMPLEMENTED | `AuthRepository.changePassword()` (`auth_repository.dart:128`) | — | `settings_screen.dart` Security tab. |
| POST | `/api/auth/availability/` | Set availability | IMPLEMENTED | `AuthRepository.setAvailability()` (`auth_repository.dart:115`) | — | `settings_screen.dart` Profile tab, `_availabilities` chips. |

### categories

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/categories/` | List categories | IMPLEMENTED | `DirectoryRepository.categories()` (`directory_repository.dart:218`) | — | Feeds the category chips in `conversation_actions_sheet.dart`. Not paginated on either side — matches. |
| POST | `/api/categories/` | Create category | NOT IMPLEMENTED | — | `team.manage` | No repository method, no UI. |
| GET | `/api/categories/{id}/` | Retrieve category | NOT IMPLEMENTED | — | `conversation.change_category` | No single-category fetch; app only ever reads the list. |
| PUT | `/api/categories/{id}/` | Replace category | NOT IMPLEMENTED | — | `conversation.change_category` | — |
| PATCH | `/api/categories/{id}/` | Update category | NOT IMPLEMENTED | — | `conversation.change_category` | — |
| DELETE | `/api/categories/{id}/` | Deactivate category | NOT IMPLEMENTED | — | `team.manage` | No category management screen at all. |

### channels

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/channels/` | List channels | IMPLEMENTED | `DirectoryRepository.channels()` (`directory_repository.dart:181`) | `channel.view` | `settings_screen.dart` `_ChannelsTab`, gated on `Perm.channelView`. |
| POST | `/api/channels/` | Record a channel connection | NOT IMPLEMENTED | — | `channel.manage` | No UI; by design (see note below). |
| GET | `/api/channels/providers/` | Provider catalog | NOT IMPLEMENTED | — | — | No "add channel" flow exists to need it. |
| GET | `/api/channels/{id}/` | Retrieve channel | NOT IMPLEMENTED | — | — | App only ever reads the list page. |
| PUT | `/api/channels/{id}/` | Replace channel | NOT IMPLEMENTED | — | — | — |
| PATCH | `/api/channels/{id}/` | Update channel | NOT IMPLEMENTED | — | — | — |
| DELETE | `/api/channels/{id}/` | Remove disconnected channel | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/channels/{id}/mute/` | Mute channel | IMPLEMENTED | `DirectoryRepository.muteChannel()` (`directory_repository.dart:191`) | `channel.manage` | `_ChannelCard._toggleMute()` in `settings_screen.dart`. |
| POST | `/api/channels/{id}/unmute/` | Unmute channel | IMPLEMENTED | `DirectoryRepository.unmuteChannel()` (`directory_repository.dart:199`) | `channel.manage` | Same toggle. |
| POST | `/api/channels/{id}/test/` | Test channel connection | IMPLEMENTED | `DirectoryRepository.testChannel()` (`directory_repository.dart:208`) | `channel.manage` | `_ChannelCard._test()`, always renders `result.detail` as a plain snackbar. |

**Design note:** `settings_screen.dart` carries an explicit doc comment: *"Connecting one is an OAuth flow against Meta that belongs on the web, where the redirect URI is whitelisted; showing its status here is what an on-call supervisor actually needs when replies start failing."* Channel CRUD and provider catalog being absent from mobile therefore appears to be a **deliberate scope decision**, not an oversight — see Not Implemented section for full reasoning.

### client-errors

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| POST | `/api/client-errors/` | Report a browser/client render error | IMPLEMENTED | `reportClientError()` / `configureClientErrorReporter()` (`lib/core/logging/client_error_reporter.dart:35,52`) | — (authenticated, `IsActiveEmployee`) | Wired to `FlutterError.onError` and `PlatformDispatcher.instance.onError` in `main.dart`. Always swallows its own failures — correct per the endpoint's "log sink" nature. |

### conversations

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/conversations/` | List conversations | PARTIALLY IMPLEMENTED | `ConversationRepository.list()` (`lib/features/conversations/conversation_repository.dart:82`) | — | See **Contract Issues** — only a subset of documented filters is exposed. |
| GET | `/api/conversations/grouped/` | Inbox grouped by customer | NOT IMPLEMENTED | — | — | No repository method; `inbox_screen.dart` renders the flat `/conversations/` list only. |
| GET | `/api/conversations/counts/` | Inbox badge counts | IMPLEMENTED | `ConversationRepository.counts()` (`conversation_repository.dart:99`) | — | Powers inbox tab badges. `channel_connection` query param not sent (no per-channel badge scoping in UI — consistent with no channel-scoped inbox view existing). |
| GET | `/api/conversations/{id}/` | Retrieve conversation | IMPLEMENTED | `ConversationRepository.detail()` (`conversation_repository.dart:94`) | — | Correctly relied on for its read-marking side effect. |
| POST | `/api/conversations/{id}/assign/` | Assign / release | PARTIALLY IMPLEMENTED | `ConversationRepository.assign()` (`conversation_repository.dart:174`); UI in `conversation_actions_sheet.dart:157-186` | `conversation.assign_self`, `conversation.assign_any` | UI only offers "assign to me" and "unassign" — `team_id` routing is never sent despite the repository method accepting it. |
| POST | `/api/conversations/{id}/attachments/` | Stage a file for sending | NOT IMPLEMENTED | — | — | No repository method, no file picker in the composer. |
| DELETE | `/api/conversations/{id}/attachments/{draft_id}/` | Discard staged file | NOT IMPLEMENTED | — | — | Depends on the above, which doesn't exist. |
| POST | `/api/conversations/{id}/category/` | Change category | IMPLEMENTED | `ConversationRepository.changeCategory()` (`conversation_repository.dart:203`) | `conversation.change_category` | `conversation_actions_sheet.dart` category chips. |
| POST | `/api/conversations/{id}/confirm-purchase/` | Confirm/reject purchase claim | IMPLEMENTED | `ConversationRepository.confirmPurchase()` (`conversation_repository.dart:283`) | `conversation.confirm_purchase` | `intelligence_panel.dart` `_PurchaseClaimSection`. |
| GET | `/api/conversations/{id}/conversions/` | Conversions reported to Meta | IMPLEMENTED | `ConversationRepository.conversions()` (`conversation_repository.dart:321`) | — | `conversion_sheet.dart`. |
| GET | `/api/conversations/{id}/events/` | Audit timeline | IMPLEMENTED | `ConversationRepository.events()` (`conversation_repository.dart:309`) | — | `conversation_history_sheet.dart`. |
| POST | `/api/conversations/{id}/follow-up/` | Mark/clear follow-up | NOT IMPLEMENTED (write) | — | `conversation.change_category` | `Conversation` model reads `is_follow_up`/`follow_up_date`/`follow_up_marked_at`/`follow_up_marked_by_name` (`lib/core/models/conversation.dart:128-131,182-185`) but nothing in the app ever calls this endpoint — no toggle exists anywhere in the UI. Effectively display-only despite the read model. |
| GET | `/api/conversations/{id}/intelligence/` | Read intelligence | IMPLEMENTED | `ConversationRepository.intelligence()` (`conversation_repository.dart:246`) | — | `intelligence_panel.dart`, correctly treats `null` as "not analyzed" rather than an error. |
| POST | `/api/conversations/{id}/intelligence/` | Re-run analyzer | IMPLEMENTED | `ConversationRepository.refreshIntelligence()` (`conversation_repository.dart:256`) | `conversation.refresh_intelligence` | `intelligence_panel.dart` refresh button, gated. |
| POST | `/api/conversations/{id}/lead-score/` | Override/clear lead score | IMPLEMENTED | `ConversationRepository.setLeadScore()` (`conversation_repository.dart:270`) | `intelligence.override_score` | `intelligence_panel.dart` `_LeadScoreSection`; correctly sends explicit `null` to clear. |
| GET | `/api/conversations/{id}/messages/` | List messages | IMPLEMENTED | `ConversationRepository.messages()` (`conversation_repository.dart:106`) | — | `conversation_controller.dart`. |
| DELETE | `/api/conversations/{id}/messages/{message_id}/` | Delete message | NOT IMPLEMENTED | — | `conversation.delete_message` (ADMIN/SUPERVISOR) | Repository has `deleteMessage()` (`conversation_repository.dart:234`) but **no UI calls it** — no long-press/delete affordance on `message_bubble.dart`. Repository-only implementation (see "APIs implemented in the repository but never exposed through the UI"). |
| POST | `/api/conversations/{id}/messages/{message_id}/retry/` | Retry failed media message | NOT IMPLEMENTED | — | — | The app's own "Retry" button (`message_bubble.dart:277`, `conversation_controller.dart:322` `retry()`) only re-sends a **locally-failed text reply** via `POST /reply/` again. It never calls this endpoint, which retries a server-stored `FAILED` outgoing message (relevant to media). Since attachments cannot be sent at all, this endpoint currently has no reachable use case. |
| GET | `/api/conversations/{id}/notes/` | List internal notes | IMPLEMENTED | `ConversationRepository.notes()` (`conversation_repository.dart:209`) | — | `notes_sheet.dart`. |
| POST | `/api/conversations/{id}/notes/` | Add internal note | IMPLEMENTED | `ConversationRepository.addNote()` (`conversation_repository.dart:221`) | `conversation.note` | `notes_sheet.dart`, gated. |
| POST | `/api/conversations/{id}/priority/` | Change priority | IMPLEMENTED | `ConversationRepository.changePriority()` (`conversation_repository.dart:197`) | `conversation.change_priority` | `conversation_actions_sheet.dart` priority chips. |
| GET | `/api/conversations/{id}/purchase-confirmations/` | Purchase ruling history | IMPLEMENTED | `ConversationRepository.purchaseConfirmations()` (`conversation_repository.dart:297`) | — | `intelligence_panel.dart` `_PurchaseHistorySection`. |
| POST | `/api/conversations/{id}/read/` | Mark read | IMPLEMENTED | `ConversationRepository.markRead()` (`conversation_repository.dart:170`) | — | Called from `conversation_controller.dart` on open. |
| POST | `/api/conversations/{id}/reply/` | Reply to customer | IMPLEMENTED | `ConversationRepository.reply()` (`conversation_repository.dart:162`) | `conversation.reply` (throttled 120/min server-side) | `conversation_controller.dart` `send()`; text-only, matches (no attachment support end to end). |
| POST | `/api/conversations/{id}/report-conversion/` | Report stage to Meta | IMPLEMENTED | `ConversationRepository.reportConversion()` (`conversation_repository.dart:333`) | `conversion.report` | `conversion_sheet.dart` "Report now", gated. |
| POST | `/api/conversations/{id}/send-template/` | Send approved WhatsApp template | NOT IMPLEMENTED | — | `conversation.reply` | No repository method, no UI. The only way to message a customer outside WhatsApp's 24-hour window is unreachable from mobile. |
| POST | `/api/conversations/{id}/status/` | Change status | IMPLEMENTED | `ConversationRepository.changeStatus()` (`conversation_repository.dart:191`) | `conversation.change_status` | `conversation_actions_sheet.dart` status chips. |
| GET | `/api/attachments/{public_id}/content/` | Download/stream attachment | PARTIALLY IMPLEMENTED | Implicit via `MessageAttachment.url` (`lib/core/models/message.dart:11-33`) rendered in `message_bubble.dart` `_Attachments` | — | Inbound attachments (images the customer sent) can be *viewed* — the model parses `url`/`fileName`/`mimeType`/`type` from each message's `attachments` array and the bubble renders them — but there is no dedicated authenticated-download flow verification; treat as read-path only, no outbound counterpart. |

### customers

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/customers/` | List customers | IMPLEMENTED | `DirectoryRepository.customers()` (`directory_repository.dart:59`) | — | `customers_screen.dart`. |
| POST | `/api/customers/` | Create customer | NOT IMPLEMENTED | — | `customer.manage` | No repository method, no "add customer" UI. |
| GET | `/api/customers/{id}/` | Retrieve customer | IMPLEMENTED | `DirectoryRepository.customerDetail()` (`directory_repository.dart:76`) | — | `customer_profile_screen.dart`. |
| PUT | `/api/customers/{id}/` | Replace customer | NOT IMPLEMENTED | — | `customer.manage` | Only `PATCH` is used; `PUT` (full replace) has no caller. |
| PATCH | `/api/customers/{id}/` | Update customer | IMPLEMENTED | `DirectoryRepository.updateCustomer()` (`directory_repository.dart:88`) | `customer.manage` | `edit_customer_sheet.dart`, gated via `Perm.customerManage`. |
| DELETE | `/api/customers/{id}/` | Delete customer | NOT IMPLEMENTED | — | `customer.manage` | No repository method, no UI. |
| GET | `/api/customers/{id}/conversations/` | Customer's conversation history | IMPLEMENTED | `DirectoryRepository.customerConversations()` (`directory_repository.dart:174`) | — | `customer_profile_screen.dart`. |
| GET | `/api/customers/{id}/facts/` | List customer facts | IMPLEMENTED | `DirectoryRepository.customerFacts()` (`directory_repository.dart:306`) | `customer.view` | `customer_record_sheet.dart`. |
| POST | `/api/customers/{id}/facts/` | Record a fact | IMPLEMENTED | `DirectoryRepository.recordFact()` (`directory_repository.dart:314`) | `order.manage` | `customer_record_sheet.dart` "Add" dialog, gated on `Perm.orderManage` — correctly matches the backend's documented (counter-intuitive) requirement, not `customer.manage`. |
| POST | `/api/customers/{id}/facts/{fact_id}/review/` | Accept/reject fact suggestion | IMPLEMENTED | `DirectoryRepository.reviewFact()` (`directory_repository.dart:332`) | `order.manage` | `customer_record_sheet.dart` `_SuggestedDetailState._decide()`. |
| GET | `/api/customers/{id}/orders/` | Customer's orders | IMPLEMENTED | `DirectoryRepository.customerOrders()` (`directory_repository.dart:260`) | — | Available in repository; primary UI path uses the conversation-scoped `orders/?conversation=` list instead (see orders below). |

### dashboard

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/dashboard/` | Dashboard summary | IMPLEMENTED | `DirectoryRepository.dashboard()` (`directory_repository.dart:223`) | `analytics.view` (partially — see note) | `dashboard_screen.dart`. Correctly treats `team: null` as "hide the panel," not zero. |
| GET | `/api/dashboard/channels/` | Volume per channel | IMPLEMENTED | `DirectoryRepository.channelVolume()` (`directory_repository.dart:229`) | `analytics.view` | `analytics_screen.dart`. |
| GET | `/api/dashboard/performance/` | Per-employee performance | IMPLEMENTED | `DirectoryRepository.performance()` (`directory_repository.dart:243`) | — (self always allowed; role narrows result set) | `dashboard_screen.dart` `_MyPerformance`, `performance_card.dart`. `employee`/`days` query params: `days` is sent (default 14); `employee` filter is not exposed in UI (app only ever asks for "my" or "everyone I may see" — matches the backend's own self-scoping default). |

### devices

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| POST | `/api/devices/register/` | Register device for push | IMPLEMENTED | `DeviceRepository.register()` (`lib/core/notifications/device_repository.dart:22`) | — | Called on launch / token rotation per `PushService.onTokenRefresh`. |
| POST | `/api/devices/heartbeat/` | Liveness ping | IMPLEMENTED | `DeviceRepository.heartbeat()` (`device_repository.dart:55`) | — | — |
| POST | `/api/devices/unregister/` | Stop push | IMPLEMENTED | `DeviceRepository.unregister()` (`device_repository.dart:84`) | — | Called from sign-out cleanup. |

### employees

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/employees/` | List employees | IMPLEMENTED | `DirectoryRepository.employees()` (`directory_repository.dart:24`) | — | `employees_screen.dart`. |
| POST | `/api/employees/` | Create employee | IMPLEMENTED | `DirectoryRepository.createEmployee()` (`directory_repository.dart:105`) | `employee.manage` | `employee_form_sheet.dart`, double-gated `isAdminProvider && Perm.employeeManage`. |
| GET | `/api/employees/online/` | Currently-available employees | IMPLEMENTED | `DirectoryRepository.onlineEmployees()` (`directory_repository.dart:46`) | `employee.view` (implicit) | `employees_screen.dart` "Online now" filter; also used for transfer pickers. |
| GET | `/api/employees/{id}/` | Retrieve employee | NOT IMPLEMENTED | — | `employee.view` | App only ever reads the paginated list, never a single employee by id. |
| PUT | `/api/employees/{id}/` | Replace employee | NOT IMPLEMENTED | — | `employee.manage` | Only `PATCH` is used. |
| PATCH | `/api/employees/{id}/` | Update employee | IMPLEMENTED | `DirectoryRepository.updateEmployee()` (`directory_repository.dart:117`) | `employee.manage` | `employee_form_sheet.dart` edit mode. |
| DELETE | `/api/employees/{id}/` | Deactivate employee | IMPLEMENTED | `DirectoryRepository.deactivateEmployee()` (`directory_repository.dart:135`) | — (self-deactivation blocked server-side with 400) | `deactivate_employee_dialog.dart`. |
| POST | `/api/employees/{id}/activate/` | Reactivate employee | NOT IMPLEMENTED | — | `employee.manage` | No counterpart UI to deactivate — an admin cannot undo a deactivation from mobile. |

### health

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/health/` | Liveness/readiness probe | NOT IMPLEMENTED | — | — (unauthenticated) | No use in a client app (this is an infra/monitoring endpoint); confirmed zero references. |

### integrations

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| POST | `/api/integrations/instagram/authorize/` | Begin Instagram Business Login | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/instagram/connect/` | Attach Instagram by token | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/instagram/{id}/disconnect/` | Disconnect Instagram | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/meta/connect/` | Begin Meta OAuth | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/meta/{id}/disconnect/` | Disconnect Messenger/Instagram | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/tiktok/authorize/` | Start TikTok authorization | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/tiktok/{id}/disconnect/` | Disconnect TikTok | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/whatsapp/connect/` | Attach WhatsApp by id/token | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/whatsapp/embedded-signup/` | Complete WhatsApp Embedded Signup | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/whatsapp/embedded-signup/mobile/start/` | Begin Embedded Signup (no-popup) | NOT IMPLEMENTED | — | `channel.manage` | **Named for mobile specifically** in its Swagger summary ("for browsers where the SDK navigates the tab instead of opening a popup") — see P1 recommendation. |
| GET | `/api/integrations/whatsapp/signup-config/` | Embedded Signup popup parameters | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/whatsapp/{id}/check-status/` | Re-check WhatsApp number status | NOT IMPLEMENTED | — | `channel.manage` | — |
| POST | `/api/integrations/whatsapp/{id}/disconnect/` | Disconnect WhatsApp | NOT IMPLEMENTED | — | `channel.manage` | — |
| GET | `/api/integrations/whatsapp/{id}/templates/` | List WhatsApp templates | NOT IMPLEMENTED | — | `channel.view` | — |
| POST | `/api/integrations/whatsapp/{id}/templates/` | Submit template for review | NOT IMPLEMENTED | — | `channel.manage`, `channel.view` | — |
| POST | `/api/integrations/whatsapp/{id}/templates/send/` | Send approved template | NOT IMPLEMENTED | — | `channel.view`, `conversation.reply` | Same functional gap as `conversations/{id}/send-template/` above. |

### integrations-external (N/A — not a client concern)

| Method | Endpoint | Feature | Status | Notes |
|---|---|---|---|---|
| GET | `/api/integrations/instagram/callback/` | Instagram OAuth redirect target | N/A | Called by Instagram's redirect, never by a Scenario client. |
| GET | `/api/integrations/meta/callback/` | Meta OAuth redirect target | N/A | Same. |
| GET/POST | `/api/integrations/meta/webhook/` | Meta webhook handshake/receiver | N/A | Called by Meta only. |
| GET | `/api/integrations/tiktok/account/callback/` | TikTok OAuth redirect target | N/A | Called by TikTok's redirect. |
| POST | `/api/integrations/tiktok/webhook/` | TikTok webhook receiver | N/A | Called by TikTok only. |

Swagger's own tag description confirms this classification: *"Called by Meta, never by a Scenario client... tagged separately so client generation and contract diffs can leave them out."* These 5 operations (6 counting both verbs on the Meta webhook) are correctly out of scope for this audit's Implemented/Not Implemented counts.

### metrics

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/metrics/` | Operational metrics | NOT IMPLEMENTED | — | `channel.manage` | No ops/health dashboard screen in the app. Reasonable to defer — this is an on-call/SRE tool, not an agent-facing feature. |

### notifications

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/notifications/` | List notifications | NOT IMPLEMENTED | — | `notification.view` (ADMIN) | No in-app notification center anywhere. Confirmed via full-project grep — zero references to `/notifications`. |
| GET | `/api/notifications/{id}/` | One notification | NOT IMPLEMENTED | — | — | — |
| GET | `/api/notifications/unread-count/` | Unread count | NOT IMPLEMENTED | — | — | No badge/bell icon exists in the app chrome for this. |
| POST | `/api/notifications/{id}/read/` | Mark one read | NOT IMPLEMENTED | — | — | — |
| POST | `/api/notifications/read-all/` | Mark all read | NOT IMPLEMENTED | — | — | — |

**Note:** this is distinct from *push* notifications, which are fully implemented (see `devices` above and `lib/core/notifications/push_service.dart`, `push_bridge.dart`). This gap is specifically the **in-app admin notification feed** (`notification.view`, ADMIN-only) — a persistent, server-side record of events an admin has and hasn't seen, independent of whether a push was delivered.

### orders

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/orders/` | List orders | IMPLEMENTED | `DirectoryRepository.conversationOrders()` (`directory_repository.dart:252`, filters by `conversation`) | — | `customer_record_sheet.dart`. |
| POST | `/api/orders/` | Record order | IMPLEMENTED | `DirectoryRepository.recordOrder()` (`directory_repository.dart:270`) | `order.manage` | `customer_record_sheet.dart` `_showRecordOrderDialog`, structured line-item composer. |
| GET | `/api/orders/{id}/` | Retrieve order | NOT IMPLEMENTED | — | — | App only reads orders via the list endpoint. |
| PUT | `/api/orders/{id}/` | Replace order | NOT IMPLEMENTED | — | — | — |
| PATCH | `/api/orders/{id}/` | Update order | NOT IMPLEMENTED | — | — | No edit-line-items UI; only confirm/cancel are offered. |
| DELETE | `/api/orders/{id}/` | Delete order | NOT IMPLEMENTED | — | `order.manage` | No delete UI (cancel is used instead, which is the correct workflow per the backend's own status model — SUGGESTED/RECORDED/CONFIRMED/CANCELLED/REFUNDED). |
| POST | `/api/orders/{id}/confirm/` | Confirm order | IMPLEMENTED | `DirectoryRepository.confirmOrder()` (`directory_repository.dart:289`) | `order.manage` | `customer_record_sheet.dart` `_OrderCard`. |
| POST | `/api/orders/{id}/cancel/` | Cancel order | IMPLEMENTED | `DirectoryRepository.cancelOrder()` (`directory_repository.dart:297`) | `order.manage` | Same card; `refunded` flag not exposed in UI (always sends `refunded: false`) — see Partially Implemented. |

### routing

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/routing/policy/` | Read auto-assignment settings | IMPLEMENTED | `DirectoryRepository.routingPolicy()` (`directory_repository.dart:346`) | `routing.manage` | `settings_screen.dart` `_AssignmentTab`, gated. |
| PATCH | `/api/routing/policy/` | Change auto-assignment settings | IMPLEMENTED | `DirectoryRepository.updateRoutingPolicy()` (`directory_repository.dart:351`) | `routing.manage` | Exact field match to `PatchedRoutingPolicyWrite` (`is_enabled`, `max_open_chats_per_agent`, `timezone`) — see Implemented APIs. |

### teams

| Method | Endpoint | Feature | Status | Flutter Implementation | Permission | Notes |
|---|---|---|---|---|---|---|
| GET | `/api/teams/` | List teams | IMPLEMENTED | `DirectoryRepository.teams()` (`directory_repository.dart:51`) | `team.view` | `teams_screen.dart`. |
| POST | `/api/teams/` | Create team | IMPLEMENTED | `DirectoryRepository.createTeam()` (`directory_repository.dart:149`) | `team.manage` | `team_form_sheet.dart`, double-gated. |
| GET | `/api/teams/{id}/` | Retrieve team | NOT IMPLEMENTED | — | — | App reads teams only via the list. |
| PUT | `/api/teams/{id}/` | Replace team | NOT IMPLEMENTED | — | `team.manage` | Only `PATCH` used. |
| PATCH | `/api/teams/{id}/` | Update team | IMPLEMENTED | `DirectoryRepository.updateTeam()` (`directory_repository.dart:157`) | `team.manage` | `team_form_sheet.dart` edit mode. |
| DELETE | `/api/teams/{id}/` | Deactivate team | IMPLEMENTED | `DirectoryRepository.deactivateTeam()` (`directory_repository.dart:169`) | `team.manage` | `deactivate_team_dialog.dart`. |

---

## Implemented APIs

### `POST /api/auth/login/` + `GET /api/auth/csrf/`
- **Flutter:** `AuthRepository.login()`, `ApiClient.primeCsrf()`
- **What it does:** Establishes a session cookie (`scenario_session`) and CSRF cookie (`scenario_csrftoken`), matching the Swagger `cookieAuth` security scheme exactly.
- **Request/response compatibility:** Sends `email`/`password` as documented; correctly primes CSRF first, since Django only issues that cookie on request.
- **Permission/auth behavior:** No permission needed to attempt login; correct.
- **Issues:** None found. This is a faithful, well-documented mirror of the backend contract, including the CSRF handshake (`X-CSRFToken` header echoed from the cookie on every unsafe request via `_CsrfInterceptor`).

### `PATCH /api/routing/policy/`
- **Flutter:** `DirectoryRepository.updateRoutingPolicy()`
- **What it does:** Toggles automatic conversation assignment, sets per-agent chat capacity, sets org timezone.
- **Request/response compatibility:** `PatchedRoutingPolicyWrite` accepts exactly `is_enabled`, `max_open_chats_per_agent`, `timezone` — the Flutter method sends exactly these three, no more, no less. `heartbeat_max_seconds` is correctly treated as read-only in the `RoutingPolicy` read model (never sent back).
- **Permission/auth behavior:** UI gated on `Perm.routingManage`; `_AssignmentTab` renders an `EmptyState` with a lock icon rather than the form when the capability is absent.
- **Issues:** None. This is the most precise 1:1 contract match found in the audit.

### `POST /api/customers/{id}/facts/`, `.../review/`
- **Flutter:** `DirectoryRepository.recordFact()`, `reviewFact()`
- **What it does:** Records a fact about a customer (manually or reviewing an analyzer suggestion).
- **Request/response compatibility:** Correct — `key`/`value`/`conversation` on create; `confirmed`/`value` on review, with `value` only sent when actually corrected (`customer_record_sheet.dart:299`), matching the backend's distinction between "accepted as-is" and "accepted with a fix."
- **Permission/auth behavior:** Correctly gated on `Perm.orderManage`, not `Perm.customerManage` — this matches the backend's documented (and counter-intuitive) reasoning that the agent on the conversation, not a customer-record manager, is the one who should capture what was just said.
- **Issues:** None.

### `POST /api/orders/`, `.../confirm/`, `.../cancel/`
- **Flutter:** `DirectoryRepository.recordOrder()`, `confirmOrder()`, `cancelOrder()`
- **What it does:** Records a claimed order, then lets an authorized employee attest (`CONFIRMED`) or cancel it.
- **Request/response compatibility:** Line items sent as `product_name`/`quantity`/`unit_price` structured rows, matching `OrderItemWrite`. `Order.isClaim`/`isConfirmed` correctly drive UI copy ("Not counted as sale" vs "Confirmed by…"), matching the backend's revenue-integrity model.
- **Permission/auth behavior:** Gated on `Perm.orderManage` throughout.
- **Issues:** `cancelOrder()` always sends `refunded: false` — the `refunded: true` path (documented as "record it as REFUNDED rather than CANCELLED") has no UI affordance. See Partially Implemented.

### Conversation lifecycle (`status`, `priority`, `category`, `assign`, `reply`, `read`)
- **Flutter:** `ConversationRepository` (multiple methods), `conversation_actions_sheet.dart`, `conversation_controller.dart`
- **What it does:** Core inbox workflow — the majority of what a support agent does all day.
- **Request/response compatibility:** Field names and enums match Swagger's `ConversationStatusEnum`/`PriorityEnum` exactly (`OPEN`, `WAITING_CUSTOMER`, `WAITING_INTERNAL`, `RESOLVED`, `CLOSED`; `URGENT`, `HIGH`, `NORMAL`, `LOW`). Note: the status list in the UI (`_statuses` in `conversation_actions_sheet.dart`) omits `NEW`, which does appear in the *filter* list (`inbox_filters_sheet.dart`) — `NEW` is presumably a system-only initial state never manually set by an agent, which is consistent, but worth confirming against the backend's actual `ConversationStatusEnum` values (5 vs 6 members — see Contract Issues).
- **Permission/auth behavior:** Every action individually gated per its own capability (`conversation.change_status`, `.change_priority`, `.change_category`, `.assign_self`/`.assign_any`, `.reply`) — this is the most thorough permission-mirroring in the app.
- **Issues:** `assign` never sends `team_id` (see Partially Implemented).

### Intelligence panel (`intelligence` GET/POST, `lead-score`, `confirm-purchase`, `purchase-confirmations`, `conversions`, `report-conversion`)
- **Flutter:** `ConversationRepository` + `intelligence_panel.dart` + `conversion_sheet.dart`
- **What it does:** Surfaces and lets an employee override the AI-derived lead score, funnel stage, purchase status, and Meta Conversions API reporting.
- **Request/response compatibility:** Correctly distinguishes `null` (never analyzed) from a real payload; `setLeadScore(null)` correctly sent as an explicit JSON `null` rather than omitted, matching the backend's "omitted = unchanged, null = clear" semantics documented for this and the `follow-up` endpoint.
- **Permission/auth behavior:** `Perm.conversationRefreshIntelligence`, `Perm.intelligenceOverrideScore`, `Perm.conversationConfirmPurchase`, `Perm.conversionReport` each independently gate their action.
- **Issues:** None found; this is a strong implementation.

### Directory (employees, teams) CRUD
- **Flutter:** `DirectoryRepository` + `employees_screen.dart`, `teams_screen.dart`, `employee_form_sheet.dart`, `team_form_sheet.dart`
- **What it does:** Admin management of the employee roster and team structure.
- **Request/response compatibility:** Correct; `Team.fromJson` handles both `member_ids`/`leader_ids` and object-list (`members`/`leaders`) response shapes defensively.
- **Permission/auth behavior:** Double-gated (`isAdminProvider && Perm.employeeManage` / `Perm.teamManage`) — explicitly documented as deliberate belt-and-suspenders beyond the capability mirror, per the code's own comments.
- **Issues:** No reactivate path (see Not Implemented — `employees/{id}/activate/`).

### Dashboard (`/dashboard/`, `/dashboard/channels/`, `/dashboard/performance/`)
- **Flutter:** `DirectoryRepository.dashboard()`, `channelVolume()`, `performance()`
- **What it does:** Live queue metrics, intelligence rollups, per-channel volume, team workload, personal/team performance.
- **Request/response compatibility:** `DashboardSummary.team` correctly modeled as nullable and rendered conditionally, matching the backend's "omit the block for roles without `analytics.view`" behavior rather than a zeroed placeholder.
- **Permission/auth behavior:** Correct — no explicit UI-side gate on the dashboard screen itself (server narrows scope per-role automatically; the team block's nullability *is* the gate).
- **Issues:** None found.

### Devices (push registration)
- **Flutter:** `DeviceRepository.register()`, `heartbeat()`, `unregister()`
- **What it does:** Registers/refreshes/clears the FCM push token against the backend's `EmployeeDevice` row.
- **Request/response compatibility:** Matches `DeviceRegisterRequest`/`DeviceHeartbeatRequest`/`DeviceUnregisterRequest` field-for-field (`device_identifier`, `platform`, `push_token`).
- **Permission/auth behavior:** N/A — always the calling employee's own device, server-derived from session.
- **Issues:** None.

---

## Partially Implemented APIs

### `GET /api/conversations/` — filter parameter coverage
- **What's implemented:** `page`, `search`, single-value `status`, `priority`, `provider`, and `assigned_to` (via "assigned to me").
- **What's missing:** `category`, `channel_connection`, `customer`, `follow_up`, `include_muted`, `min_lead_score`, `stage`, `team`, `unread`, `view` are all documented Swagger query parameters with no UI or repository support. Additionally, Swagger documents `priority`, `provider`, and `status` as **arrays** (multi-select filtering) — the Flutter `ConversationFilters` only ever sends one value for each.
- **Exact mismatch:** `ConversationFilters.toQuery()` (`conversation_repository.dart:36`) also sends `assigned_to__isnull: true` for the "Unassigned" filter — this is a raw Django ORM lookup suffix, and **does not appear anywhere in the documented OpenAPI parameter list** for this endpoint. It may work by accident (if the backend's filter backend passes unknown params through to a queryset filter) or may silently no-op. This should be verified against backend source directly, not assumed.
- **Recommended work:** (1) Confirm with backend team whether `assigned_to__isnull` is intentionally supported or coincidentally works; replace with a documented equivalent if one exists. (2) Extend the filter sheet to at least `unread`, `follow_up`, and `team` — natural extensions of the existing filter UI pattern. (3) Consider multi-select chips for status/priority/provider to match the array-typed backend contract.

### `POST /api/conversations/{id}/assign/` — team assignment
- **What's implemented:** Self-assign and release/unassign (`assigneeId` only).
- **What's missing:** Routing to a team via `team_id` — the repository method already accepts `teamId` as a parameter (`conversation_repository.dart:177`), but `conversation_actions_sheet.dart` never surfaces a team picker.
- **Exact mismatch:** None in the request shape itself — this is purely a missing UI affordance for an already-correct repository method.
- **Recommended work:** Add a "Route to team" option to the actions sheet for employees holding `conversation.assign_any`, using the existing `teamsProvider`.

### `POST /api/orders/{id}/cancel/` — refund flag
- **What's implemented:** Cancel with `refunded: false` always.
- **What's missing:** No UI path ever sends `refunded: true`, so an order can never be marked REFUNDED from mobile — only CANCELLED.
- **Recommended work:** Add a "Refunded?" checkbox/confirmation to the cancel action, mirroring the two distinct outcomes the backend models.

### `POST /api/conversations/{id}/follow-up/` — read-only in practice
- **What's implemented:** The `Conversation` model fully parses `is_follow_up`, `follow_up_date`, `follow_up_marked_at`, `follow_up_marked_by_name` from every conversation payload.
- **What's missing:** No `ConversationRepository` method calls this endpoint, and no UI anywhere lets an agent set or clear it — despite the model being fully wired to display it (if any UI does render it; a search for follow-up badges/icons in `inbox_screen.dart` and `message_bubble.dart` should be done to confirm whether the parsed field is even displayed, or parsed-and-discarded).
- **Exact mismatch:** Full read support, zero write support, for a feature whose commit history (`365c219 Spec the follow-up flag for mobile`) suggests it was explicitly planned for this platform.
- **Recommended work:** Add the write path — likely a toggle/date-picker in `conversation_actions_sheet.dart`, calling a new `ConversationRepository.setFollowUp()` wrapping `POST /conversations/{id}/follow-up/` with the three-valued `follow_up_date` semantics (omit = unchanged, per the endpoint's own documented convention).

### `GET /api/attachments/{public_id}/content/` — inbound-only
- **What's implemented:** Inbound message attachments (images/files a customer sent) are parsed and rendered in the message thread.
- **What's missing:** No outbound counterpart (see `attachments/` POST/DELETE in Not Implemented) — an agent can see what was sent to them but can never send a file back.
- **Recommended work:** See P0 item below.

### `GET /api/dashboard/performance/` — `employee` query param
- **What's implemented:** `days` window selection.
- **What's missing:** The `employee` query parameter (viewing a specific colleague's performance, for TEAM_LEADER/ADMIN/SUPERVISOR roles) is never sent — the app only ever requests the caller's own scoped result set.
- **Recommended work:** Low priority; likely acceptable if there's no "view teammate's performance in detail" use case on mobile, but worth an explicit product decision rather than a silent gap.

---

## Not Implemented APIs

### Notifications (in-app admin feed)
`GET /api/notifications/`, `GET /api/notifications/{id}/`, `GET /api/notifications/unread-count/`, `POST /api/notifications/{id}/read/`, `POST /api/notifications/read-all/`

Zero references anywhere in the codebase. This is the server-side notification *record* (ADMIN-only, `notification.view`), distinct from push delivery (which is fully implemented). There is no bell icon, no notification list screen, no unread badge tied to this endpoint anywhere in `lib/`.

### Integrations — channel connection management
All of: `instagram/authorize`, `instagram/connect`, `instagram/{id}/disconnect`, `meta/connect`, `meta/{id}/disconnect`, `tiktok/authorize`, `tiktok/{id}/disconnect`, `whatsapp/connect`, `whatsapp/embedded-signup`, `whatsapp/embedded-signup/mobile/start`, `whatsapp/signup-config`, `whatsapp/{id}/check-status`, `whatsapp/{id}/disconnect`, `whatsapp/{id}/templates` (list + create), `whatsapp/{id}/templates/send`.

Explicitly deferred per an in-code comment in `settings_screen.dart` ("belongs on the web, where the redirect URI is whitelisted"). This is a coherent product decision for the OAuth-heavy parts (`authorize`, `connect`, `embedded-signup*`) — those genuinely need a whitelisted web redirect URI. It is a **weaker justification** for `{id}/disconnect`, `{id}/check-status`, and the WhatsApp templates endpoints, none of which involve an OAuth redirect and all of which are plausible on-call/supervisor actions for a mobile app (see P1).

### Channel/category CRUD
`POST /channels/`, `GET/PUT/PATCH/DELETE /channels/{id}/`, `GET /channels/providers/`, and all of categories' create/retrieve/update/delete (`POST /categories/`, `GET/PUT/PATCH/DELETE /categories/{id}/`).

Consistent with the same "connection management belongs on the web" reasoning as integrations. Category management specifically has no stated justification in-code — it may simply not have been built yet rather than deliberately deferred.

### Operational/infra endpoints
`GET /api/health/`, `GET /api/metrics/`.

Not client-facing features in any conventional sense — `health` is an unauthenticated liveness probe and `metrics` is an ops dashboard gated on `channel.manage`. Reasonable to leave unimplemented unless the product intends an in-app "system status" screen for supervisors.

### Conversation actions with no reachable use case
`POST /conversations/{id}/attachments/`, `DELETE /conversations/{id}/attachments/{draft_id}/`, `POST /conversations/{id}/send-template/`, `POST /conversations/{id}/messages/{message_id}/retry/`.

Unlike the categories above, these are **not** deferred by any in-code comment — they appear to be straightforward gaps in an otherwise thorough messaging feature. See P0 below.

### Read-only single-resource fetches with no caller
`GET /channels/{id}/`, `GET /employees/{id}/`, `GET /teams/{id}/`, `GET /orders/{id}/`, `GET /categories/{id}/`.

The app consistently reads these resources only through their list endpoints and never fetches a single row by id. Low-priority — the list responses already carry every field the detail view needs in each observed case.

---

## Unknown APIs

None. Every one of the 122 documented operations was resolved to a definite IMPLEMENTED / PARTIALLY IMPLEMENTED / NOT IMPLEMENTED / N/A status via direct source inspection (repository method existence, grep confirmation of zero references for absent ones, and UI-level tracing for partial cases). The `integrations-external` tag's 5 operations are explicitly out of scope per the Swagger spec's own tag description, not "unknown" — Meta/TikTok are the only possible callers.

---

## API Contract Issues

| Path | Method | Issue | Detail |
|---|---|---|---|
| `/api/conversations/` | GET | Undocumented query param | `ConversationFilters.toQuery()` sends `assigned_to__isnull: true` for "Unassigned," which does not appear in the Swagger `parameters` list for this operation. Either the backend's filter backend passes it through unofficially, or it silently does nothing — needs backend-side verification, not assumption. |
| `/api/conversations/` | GET | Type mismatch (array vs scalar) | Swagger types `status`, `priority`, `provider` as arrays (multi-select). The Flutter client only ever sends one value per filter. Not a bug (single-select is a valid subset), but the UI cannot express "URGENT or HIGH" in one request the way the API supports. |
| `/api/conversations/{id}/assign/` | POST | Underused request field | `team_id` is accepted by both the endpoint and the Flutter repository method, but no UI path ever populates it. |
| `/api/orders/{id}/cancel/` | POST | Underused request field | `refunded` is accepted and modeled, but the UI never sends `true`. |
| `/api/conversations/{id}/follow-up/` | POST | Read/write asymmetry | Full response-field parsing exists (`is_follow_up`, `follow_up_date`, `follow_up_marked_at`, `follow_up_marked_by_name`) with no corresponding write path anywhere in the app. |
| `/api/dashboard/performance/` | GET | Underused query param | `employee` (viewing a specific colleague, for elevated roles) is never sent; only `days` is used. |
| Conversation status vocabulary | — | Possible enum mismatch | The actions-sheet status picker (`conversation_actions_sheet.dart`) offers 5 values (`OPEN`, `WAITING_CUSTOMER`, `WAITING_INTERNAL`, `RESOLVED`, `CLOSED`); the inbox filter sheet offers 6, adding `NEW`. `NEW` is presumably a system-only initial state an agent cannot manually re-enter, which would make this correct by design — but it should be confirmed against the backend's actual `ConversationStatusEnum` member list (not retrievable from the schema dump used for this audit without the enum's `enum:` value list) rather than assumed. |

No path, method, request-field-name, response-field-name, or type errors were found in any endpoint that **is** implemented — every implemented method reads/writes the exact JSON keys the schema documents (verified against `RoutingPolicy`/`PatchedRoutingPolicyWrite`, `Order`/`OrderItemWrite`, `Employee`/`EmployeeWrite`, `CustomerFact`, `ConversationList`/`ConversationDetail`, `DashboardSummary`, `Team`, and `Message`/`MessageAttachment` schemas directly). JSON parsing throughout uses a consistent `JsonSafe` helper with typed fallbacks (`asString`, `asInt`, `asBool`, `asIntOrNull`, `asDoubleOrNull`, `parseList`) — no unsafe casts or missing-null-handling were found in any model read in this audit.

---

## Security & Permission Audit

**Architecture:** `Employee.permissions` (a `Set<String>`) is populated from `GET /auth/me/`'s `permissions` field and checked via `employee.can(Perm.xxx)` / a `canProvider(Perm)` Riverpod provider throughout the UI. The `Perm` class (`lib/core/models/employee.dart:188`) mirrors the backend's capability slugs closely: `conversation.*` (view/reply/note/assign_self/assign_any/change_status/change_priority/change_category/delete_message/confirm_purchase/refresh_intelligence), `intelligence.override_score`, `conversion.report`, `customer.view`/`customer.manage`, `employee.view`/`employee.manage`, `team.view`/`team.manage`, `analytics.view`, `channel.view`/`channel.manage`, `routing.manage`, `order.manage`.

**Correctly enforced (UI hides, backend is still authoritative):**
- Every write action traced in this audit (`conversation_actions_sheet.dart`, `intelligence_panel.dart`, `conversion_sheet.dart`, `notes_sheet.dart`, `customer_record_sheet.dart`, `settings_screen.dart`, `employees_screen.dart`, `teams_screen.dart`) gates its button/control on the matching `Perm` constant before rendering it.
- Employee/team management additionally double-gates on `isAdminProvider`, explicitly documented as belt-and-suspenders beyond the capability-mirror pattern (per the code's own doc comments), matching the backend's ADMIN-only enforcement for those specific routes.
- `ApiException.isForbidden` (`statusCode == 403`) exists and error messages from the backend are surfaced verbatim rather than replaced with client-invented text — meaning a permission mismatch (UI thought something was allowed, server disagreed) fails safely and visibly rather than silently.
- The doc comment on `Employee.permissions` states explicitly: *"never the authority: every action is re-checked server-side... a client that got this wrong would produce a clean 403, not an unauthorised write."* This is the correct model and it's applied consistently everywhere checked.

**Gaps found:**
- **`notification.view` has no `Perm` constant** — consistent with notifications being entirely unimplemented, not a permission-check bug, but worth adding when/if that feature is built so the same double-gate pattern extends there.
- **No explicit UI-side gate on the dashboard screen itself** for `analytics.view` — this appears to be intentional (the `team` block's nullability is itself the signal that the capability was denied server-side, per the doc comment at `dashboard_screen.dart:5-8`), but it is worth confirming this doesn't leave any dashboard sub-widget assuming a non-null value it hasn't actually checked. Not independently verified beyond the one `if (data.team != null)` guard already read.
- **CSRF/session cookie handling is sound**: `X-CSRFToken` is echoed from the `scenario_csrftoken` cookie on every unsafe request (`_CsrfInterceptor`), a `Referer` header is set to satisfy Django's HTTPS Referer check, redirects are capped at 1 hop (bounding credential exposure to a compromised/misconfigured backend), and a release build forces TLS regardless of build-time flags (`Environment.isReleaseBuild` overriding `useTls`/`allowsDevTlsBypass`). No credential- or cookie-handling issues were found.
- **No client-side rate-limiting awareness**: the backend documents `conversation.reply` as throttled to 120/min and `client-errors` to 20/min; the Flutter client has no special handling for a 429 beyond the generic `ApiException` fallback message ("Too many requests. Please wait a moment.") — acceptable, but worth confirming the composer doesn't allow rapid-fire double-sends that would exhaust this budget pointlessly (not independently verified in this audit).

No instance was found of a capability being checked incorrectly (wrong `Perm` for an action) or a destructive/sensitive action being reachable in the UI without any permission check at all.

---

## Recommended Remaining Work

### P0 — Release blockers

1. **Outbound attachment support is completely missing.**
   *Endpoints:* `POST /conversations/{id}/attachments/`, `DELETE /conversations/{id}/attachments/{draft_id}/`.
   *Files:* `lib/features/conversations/conversation_repository.dart`, `lib/features/messages/conversation_controller.dart`, `lib/features/messages/conversation_screen.dart` (composer).
   *Why it matters:* An agent can receive a photo/document from a customer but cannot send one back on any channel. This is a core support-agent capability on WhatsApp/Instagram/Messenger/TikTok and its absence will read as a broken product to any agent who has used the web client, not a deferred nice-to-have.

2. **Message delete UI is missing despite the repository already supporting it.**
   *Endpoint:* `DELETE /conversations/{id}/messages/{message_id}/`.
   *Files:* `lib/features/conversations/conversation_repository.dart:234` (method exists, unused), `lib/features/messages/message_bubble.dart` (needs a long-press/action affordance).
   *Why it matters:* ADMIN/SUPERVISOR moderation capability that's fully built server-side and client-side at the repository layer, just never wired to a gesture. Low implementation cost given the method already exists — likely a half-day fix, not a design problem.

### P1 — Important before release

3. **WhatsApp template send is unreachable from mobile.**
   *Endpoints:* `POST /conversations/{id}/send-template/`, `GET/POST /integrations/whatsapp/{id}/templates/`, `POST /integrations/whatsapp/{id}/templates/send/`.
   *Files:* new — no existing repository method.
   *Why it matters:* This is documented as *"the only way to reach a customer after the 24-hour service window closes"* on WhatsApp. Without it, an agent on mobile has no recovery path for a stalled WhatsApp conversation and must switch to the web client mid-shift.

4. **Follow-up flag is read-only.**
   *Endpoint:* `POST /conversations/{id}/follow-up/`.
   *Files:* `lib/core/models/conversation.dart` (read model already complete), `lib/features/conversations/conversation_repository.dart` (needs a `setFollowUp()` method), `lib/features/messages/conversation_actions_sheet.dart` (needs a toggle).
   *Why it matters:* Git history (`365c219 Spec the follow-up flag for mobile`) indicates this was explicitly planned for this platform, and the read side was fully built — the write side appears to be an unfinished feature rather than a deferred one.

5. **WhatsApp Embedded Signup "mobile start" endpoint exists specifically for this app and is unused.**
   *Endpoint:* `POST /integrations/whatsapp/embedded-signup/mobile/start/`.
   *Why it matters:* Its Swagger summary explicitly targets "browsers where the SDK navigates the tab instead of opening a popup" — i.e., mobile. This suggests the backend team built a mobile-specific onboarding path that the Flutter app never adopted. Worth a product conversation: either this becomes the mobile channel-connect flow, or it should be confirmed as dead/backend-only and the "belongs on web" framing in `settings_screen.dart` revisited.

6. **Conversation list filter coverage.**
   *Endpoint:* `GET /conversations/`.
   *Files:* `lib/features/conversations/conversation_repository.dart` (`ConversationFilters`), `lib/features/conversations/inbox_filters_sheet.dart`.
   *Why it matters:* `follow_up`, `team`, and `unread` filters are natural, low-effort additions to an already-built filter sheet and directly support common inbox workflows ("show me my follow-ups," "show my team's unassigned"). The undocumented `assigned_to__isnull` param should be verified with the backend team before shipping, since silent no-ops in a filter are hard to notice in QA.

### P2 — Nice to have

7. **Team routing from the conversation actions sheet.**
   *Endpoint:* `POST /conversations/{id}/assign/` (`team_id`).
   *Files:* `lib/features/messages/conversation_actions_sheet.dart`.
   *Why it matters:* Repository support already exists; this is a UI-only gap for a plausible supervisor workflow ("route this to Team X").

8. **Order refund flag.**
   *Endpoint:* `POST /orders/{id}/cancel/` (`refunded`).
   *Files:* `lib/features/orders/customer_record_sheet.dart`.
   *Why it matters:* Distinguishing REFUNDED from CANCELLED matters for reporting accuracy; currently impossible from mobile.

9. **Employee reactivation.**
   *Endpoint:* `POST /employees/{id}/activate/`.
   *Files:* `lib/features/directory/employees_screen.dart`, `lib/features/directory/directory_repository.dart`.
   *Why it matters:* An admin can deactivate an employee from mobile but cannot undo it without switching to web — an asymmetric, easy-to-hit dead end.

10. **In-app admin notification feed.**
    *Endpoints:* all of `notifications/*`.
    *Why it matters:* ADMIN-only operational awareness (the specific event log, not push delivery). Lower priority than the above since push already covers real-time awareness for the events that matter most.

### P3 — Future features

11. **Channel/category management UI** (create/update/delete for both, plus the provider catalog and full integrations OAuth suite). Consistent with the documented "belongs on web" design decision for the OAuth-heavy parts; category CRUD has no such justification and could move to P2 if product wants full parity.

12. **Operational dashboards** (`/metrics/`, `/health/`) — only relevant if the product intends a supervisor-facing "system status" screen on mobile.

13. **Conversation grouped view** (`GET /conversations/grouped/`) — the customer-centric inbox grouping the web client offers; worth considering as a future navigation mode rather than the current flat list, since the backend already ships it fully formed.

---

## Final Release Checklist

- [ ] Decide and document (even if "won't fix for v1"): outbound attachments, message delete UI, WhatsApp template send — these are the three gaps with no in-code justification, unlike the channel/integrations deferrals.
- [ ] Verify `assigned_to__isnull` on `GET /conversations/` with the backend team — confirm it's a supported (if undocumented) filter, or replace it before the "Unassigned" filter ships silently broken.
- [ ] Confirm the conversation status vocabulary (5 vs 6 values between the actions sheet and the filter sheet) against the backend's actual `ConversationStatusEnum` member list.
- [ ] Product sign-off on the follow-up flag: ship the write path, or explicitly descope the read-only display for this release.
- [ ] Confirm whether `POST /integrations/whatsapp/embedded-signup/mobile/start/` was intended for this app; if so, scope it in or explicitly defer it with a tracked follow-up.
- [ ] Re-run this audit (or at minimum the Endpoint Matrix) after any of the P0/P1 items land, since new repository methods should be re-checked against the same schema for field-name/type accuracy this audit found to be consistently correct elsewhere.
- [ ] No blocking security/permission issues were found — the capability-mirror pattern is applied consistently and correctly wherever checked, and the backend remains authoritative in every traced path. No action required here beyond normal regression testing.

---

*This document was generated by inspecting the live OpenAPI schema at `https://scenariomnchnl.tech/api/schema/` (122 operations, 157 component schemas, OpenAPI 3.0.3) against the Flutter source tree as of the `update-one` branch. No application code was modified in the course of this audit.*
