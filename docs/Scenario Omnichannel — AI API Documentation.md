# Scenario Omnichannel — AI API Documentation

Nov 2, 2026 · @scenario

توثيق قسم الـ AI في Scenario Omnichannel API: إعدادات الـ AI لكل قناة، المراقبة، الـ Playground، وتكامله جوه المحادثات.

## نظرة عامة

كل endpoints الـ AI تحت `/api/ai/` (والتكامل مع المحادثات تحت `/api/conversations/{id}/`)، وكلها بتشتغل بنفس نظام الـ session بتاع باقي الـ API.

| البند | التفاصيل |
| --- | --- |
| Base URL | `https://scenariomnchnl.tech` |
| Authentication | session cookie اسمها `scenario_session` (httpOnly). بتتحط بعد `POST /api/auth/login/` وتتبعت مع كل request. مفيش bearer tokens. |
| CSRF | أي `POST` أو `PUT` أو `PATCH` أو `DELETE` لازم يحمل header اسمه `X-CSRFToken`. القيمة من cookie اسمها `scenario_csrftoken`، أو من `GET /api/auth/csrf/`، أو من response الـ login. |
| Authorization | كل endpoint محصور على مؤسسة المستخدم، ومعظمهم محتاج capability معينة (زي `conversation.reply`). `GET /api/auth/me/` بيرجّع قائمة الـ capabilities كاملة. |
| Cross-tenant | أي resource بتاع مؤسسة تانية بيرد **404 مش 403**، عشان الـ 403 كان هيأكد إن الـ row موجود. |
| Content type | `application/json` |

### شكل الأخطاء

كل فشل بيرجع نفس الشكل:

```json
{"error": {"code": "validation_error", "message": "...", "details": {}}}
```

`details` فيه `{field: [message, ...]}` لما يكون الخطأ validation، وفاضي `{}` في غير كده. أمثلة على `code`: `validation_error` و `not_found` و `throttled`.

| Status | المعنى في endpoints الـ AI |
| --- | --- |
| 400 | Validation failed (مثلاً `SUGGEST` لقناة لسه ما اتفتحتش للـ pilot) |
| 401 | مفيش session صالحة |
| 403 | المستخدم مسجّل دخول بس ناقصه الـ capability المطلوبة |
| 404 | الـ resource مش موجود جوه مؤسسة المستخدم، أو المؤسسة برا الـ AI pilot |
| 429 | تجاوز حد الـ requests (الـ playground: 30 في الدقيقة) |

## فهرس الـ Endpoints

فيه 13 endpoint: 11 تحت tag اسمه `ai`، واتنين جوه الـ `conversations`. كلهم بيستخدموا `cookieAuth`.

| Method | Path | الغرض | Request | Response |
| --- | --- | --- | --- | --- |
| GET | `/api/ai/agent-settings/` | وضع الـ AI لكل connection | — | `AIAgentSetting[]` |
| PUT | `/api/ai/agent-settings/` | تغيير وضع الـ AI لـ connection واحد | `AIAgentSettingUpdate` | `AIAgentSetting[]` |
| GET | `/api/ai/readiness/` | جاهزية كل connection لكل وضع | — | `Readiness[]` |
| GET | `/api/ai/conflicts/` | تناقضات الـ knowledge base | — | `KnowledgeConflict[]` |
| GET | `/api/ai/policy/` | سياسة الـ AI للمؤسسة | — | `AIOrganizationPolicy` |
| PUT | `/api/ai/policy/` | تعديل سياسة الـ AI | `AIOrganizationPolicyUpdate` | `AIOrganizationPolicy` |
| GET | `/api/ai/metrics/` | مقاييس نشاط الـ AI | query: `connection_id`, `hours` | `AIMetrics` |
| GET | `/api/ai/usage/` | استهلاك الـ AI (requests و tokens) | query: `days` | `AIUsageSummary` |
| GET | `/api/ai/history/` | سجل تغييرات الإعدادات (audit) | query: `limit` | `AIConfigurationChange[]` |
| POST | `/api/ai/playground/ask/` | سؤال للـ knowledge base بدون ما يتعمل conversation | `PlaygroundRequest` | `PlaygroundResponse` |
| POST | `/api/conversations/{id}/ai-suggestion/` | مسودة رد للموظف يراجعها | `SuggestionRequest` | `SuggestionResponse` |
| POST | `/api/ai/suggestions/{public_id}/outcome/` | تسجيل إن المسودة اتستخدمت أو اتلغت | `SuggestionOutcome` | `SuggestionOutcome` |
| POST | `/api/conversations/{id}/ai-resume/` | رجّع الـ AI يرد على المحادثة تاني | — | `ConversationDetail` |

### أوضاع الـ AI لكل connection

| الوضع | المعنى |
| --- | --- |
| `OFF` | مفيش مساعدة من الـ AI. ده الافتراضي لأي connection ملهاش إعداد محفوظ. |
| `SUGGEST` | الـ AI يكتب مسودة والموظف يراجعها ويبعتها. |
| `AUTO` | الـ AI يرد على العميل لوحده من غير إنسان. |

الـ rollout state بتاع المؤسسة (`INTERNAL` ثم `PILOT` ثم `LIMITED` ثم `GENERAL`) **مش بيفتح أي قناة**. كل connection لازم يتحط على `SUGGEST` أو `AUTO` لوحده ولازم يعدّي الـ readiness.

## إعدادات الـ AI

### GET /api/ai/agent-settings/

بيرجّع كل connections المؤسسة (حتى اللي ملهاش إعداد محفوظ) مع وضع الـ AI بتاعها. أي connection من غير إعداد بتتقرا `OFF`.

- Response `200`: مصفوفة `AIAgentSetting[]`
- Errors: `401`, `404`

```json
[
  {
    "connection_id": 12,
    "connection_name": "WhatsApp Main",
    "provider": "whatsapp",
    "status": "ACTIVE",
    "mode": "OFF",
    "assist_supported": true
  }
]
```

> القيم في الأمثلة توضيحية، الأنواع بس هي المأخوذة من الـ spec.

### PUT /api/ai/agent-settings/

بيغيّر وضع الـ AI لـ connection واحد. السيرفر بيرفض الأوضاع اللي الـ readiness مش سامح بيها حتى لو الواجهة عرضتها.

| Field | Type | مطلوب | الوصف |
| --- | --- | --- | --- |
| `connection_id` | integer | نعم | الـ connection المقصود |
| `mode` | enum | نعم | `OFF` أو `SUGGEST` أو `AUTO` |

- Response `200`: `AIAgentSetting[]` (القائمة بعد التعديل)
- Errors: `400` (مثلاً `SUGGEST` لقناة ما اتفتحتش للـ pilot في الإصدار ده: بيرد 400 مش تجاهل صامت)، `401`, `404`

### GET /api/ai/readiness/

جاهزية كل connection لكل وضع. الشروط الصلبة بتمنع التفعيل (مفيش knowledge base، مفيش حاجة اتعملها index، مفيش provider، connection ميت، قناة ما اتفتحتش). الشروط الخفيفة بتظهر كتحذير بس.

تعارض الـ knowledge base بيمنع `AUTO` وبيطلع تحذير بس في `SUGGEST`.

- Response `200`: `Readiness[]`
- Errors: `401`, `404`

| Field | Type | الوصف |
| --- | --- | --- |
| `connection_id` | integer |  |
| `provider` | string |  |
| `state` | enum | `NOT_READY` أو `READY_FOR_SUGGEST` أو `READY_FOR_AUTO` |
| `suggest_allowed` | boolean | هل `SUGGEST` مسموح |
| `auto_allowed` | boolean | هل `AUTO` مسموح |
| `blocking` | string\[\] | أكواد بتمنع التفعيل (machine-readable مش جمل) |
| `warnings` | string\[\] | أكواد تحذير ما بتمنعش |
| `detail` | object | تفاصيل حرة الشكل |

### GET /api/ai/conflicts/

تناقضات في الـ knowledge base: نفس السؤال بأرقام مختلفة والاتنين active. الفحص محدود (بيقف بعد عدد ثابت من المصادر وكام نتيجة بس).

- Response `200`: `KnowledgeConflict[]`، كل عنصر فيه `sources` (string\[\]) و `reason` (string)
- Errors: `401`, `404`

### GET /api/ai/policy/

سياسة الـ AI بتاعة المؤسسة: مفاتيح التشغيل والميزانيات وحالة الـ rollout. لو المؤسسة عمرها ما اتضبطت بيرجّع الـ defaults من غير ما يعمل row، وأول `PUT` هو اللي بيعمله.

- Response `200`: `AIOrganizationPolicy`
- Errors: `401`, `404`

### PUT /api/ai/policy/

كل الـ fields اختيارية، فتقدر تغيّر مفتاح واحد من غير ما تبعت الباقي. كل تغيير بيتسجّل في الـ audit بالـ actor والقيمة القديمة والجديدة.

| Field | Type | الحدود | الوصف |
| --- | --- | --- | --- |
| `is_ai_enabled` | boolean |  | تشغيل الـ AI للمؤسسة |
| `is_auto_send_enabled` | boolean |  | السماح بالرد التلقائي |
| `daily_request_limit` | integer | 0 إلى 1,000,000 | سقف الـ requests اليومي (0 يعطّل الميزة) |
| `daily_token_limit` | integer | 0 إلى 1,000,000,000 | سقف الـ tokens اليومي (0 يعطّل الميزة) |
| `rollout_state` | enum |  | `INTERNAL` أو `PILOT` أو `LIMITED` أو `GENERAL` |

- Response `200`: `AIOrganizationPolicy` (نفس الـ fields بالأعلى، كلها موجودة)
- Errors: `400`, `401`, `404`

```json
{ "is_ai_enabled": true, "daily_request_limit": 5000 }
```

## المراقبة والـ Audit

التلات endpoints دول للقراءة بس، (الـ metrics والـ usage بيعرضوا أرقام مجمّعة بس، من غير محتوى رسايل). كلهم بيرجّعوا `401` و `404` في الحالات العامة.

### GET /api/ai/metrics/

نشاط الـ AI للمؤسسة في فترة زمنية: بيتجمّع من المخازن الموجودة أصلاً مش من عدّادات منفصلة، عشان الأرقام ما تتعارضش وقت حادثة.

| Query | Type | الوصف |
| --- | --- | --- |
| `connection_id` | integer | تضييق النتائج على connection واحد |
| `hours` | integer | حجم الفترة بالساعات. الافتراضي 24 والحد الأقصى 720 |

الـ response من نوع `AIMetrics`، وكل الـ fields فيه موجودة دايماً. مجمّعة كالتالي:

| المجموعة | Fields |
| --- | --- |
| تعريف | `organization_id`, `window_hours` |
| الحجم والنتيجة | `opportunities`, `sent`, `handed_off`, `refused`, `duplicates_suppressed`, `coalesced_messages` |
| النسب | `handoff_rate`, `send_rate`, `verbatim_rate` (أرقام double) |
| أسباب الرفض أو التسليم للموظف | `not_in_kb`, `conflicts`, `restricted_topics`, `grounding_too_low`, `ungrounded_numbers`, `customer_requested_human`, `outside_service_window`, `attachment_required`, `max_auto_turns`, `budget_exhausted`, `provider_unavailable`, `send_failed` |
| الـ Suggestions | `suggestions`, `suggestions_used`, `suggestions_discarded`, `suggestions_regenerated`, `sent_unchanged`, `sent_edited` |
| التكلفة والأداء | `tokens`, `requests`, `average_duration_ms`, `average_retrieval_ms`, `slowest_duration_ms` |
| أحداث تشغيلية | `human_takeovers`, `delivery_failures`, `conversations_paused` |
| توزيع الـ connections | `connections_off`, `connections_suggest`, `connections_auto` |
| تفصيل | `by_operation` (object حر الشكل) |

### GET /api/ai/usage/

الاستهلاك المجمّع: عدد الـ requests والـ tokens والموديل، وعدد المرات اللي الـ knowledge base ماكانش فيها إجابة. مش فاتورة ومش بيعرض محتوى.

| Query | Type | الوصف |
| --- | --- | --- |
| `days` | integer | حجم الفترة بالأيام. الافتراضي 30 والحد الأقصى 365 |

الـ response من نوع `AIUsageSummary`:

| Field | Type | الوصف |
| --- | --- | --- |
| `requests` | integer | إجمالي الـ requests |
| `total_tokens` | integer |  |
| `input_tokens` | integer |  |
| `output_tokens` | integer |  |
| `answered` | integer | عدد الإجابات المدعومة |
| `not_in_kb` | integer | عدد المرات اللي مفيش فيها إجابة في الـ knowledge base |
| `errors` | integer |  |
| `by_model` | object | عدد الـ requests لكل موديل `{model: count}` |
| `since` | date-time أو null | بداية الفترة |

### GET /api/ai/history/

سجل تغييرات إعدادات الـ AI (append-only وللقراءة بس): مين غيّر إيه ومتى والقيمة كانت إيه قبل. بيجاوب على أسئلة زي «القناة دي بقت automatic إمتى» أو «مين قفل الـ kill switch».

| Query | Type | الوصف |
| --- | --- | --- |
| `limit` | integer | عدد الصفوف. الافتراضي 100 والحد الأقصى 500 |

الـ response `AIConfigurationChange[]`:

| Field | Type | الوصف |
| --- | --- | --- |
| `setting` | string | اسم الإعداد اللي اتغيّر |
| `previous_value` | string |  |
| `new_value` | string |  |
| `channel_connection_id` | integer أو null |  |
| `conversation_id` | integer أو null |  |
| `actor` | string | مين عمل التغيير |
| `source` | string | مصدر التغيير |
| `note` | string |  |
| `at` | date-time | وقت التغيير |

## Playground: اختبار الـ Knowledge Base

### POST /api/ai/playground/ask/

بيجاوب سؤال من knowledge base واحدة، بإجابة مبنية على مصادرها ومعاها citations. **ما بيعملش conversation ولا message ولا أي تغيير ownership.** الحد 30 request في الدقيقة (`429` بعد كده).

**Request body** (`PlaygroundRequest`):

| Field | Type | مطلوب | الوصف |
| --- | --- | --- | --- |
| `knowledge_base_id` | uuid | نعم | الـ public id بتاع الـ knowledge base |
| `question` | string (حتى 1000 حرف) | نعم | السؤال بالعربي أو الإنجليزي، والإجابة بترجع بنفس اللغة |

```json
{ "knowledge_base_id": "<uuid>", "question": "ايه مواعيد العمل؟" }
```

**Response `200`** (`PlaygroundResponse`): اقرا `status` الأول.

| `status` | المعنى |
| --- | --- |
| `ANSWERED` | الإجابة مدعومة بالـ knowledge base، وفيها citation واحدة على الأقل (ده بيتفرض من السيرفر مش بيتطلب من الموديل) |
| `NOT_IN_KB` | الـ knowledge base ما بتدعمش إجابة. ده نتيجة صحيحة مش خطأ، و`answer` فاضي |
| `ERROR` | الـ provider ما اتوصلش له أو رجّع حاجة مش صالحة. `error_code` بيقول السبب |

| Field | Type | الوصف |
| --- | --- | --- |
| `status` | string | زي الجدول اللي فوق |
| `answer` | string | نص الإجابة |
| `citations` | `Citation[]` | مصادر الإجابة |
| `retrieved` | `RetrievedChunk[]` | الـ chunks المرشّحة مع درجات التشابه، لتقييم الـ retrieval نفسه (فيها نص الـ chunk) |
| `model`, `provider`, `policy_version` | string |  |
| `duration_ms`, `retrieval_ms` | integer |  |
| `input_tokens`, `output_tokens`, `cached_tokens`, `total_tokens` | integer |  |
| `error_code`, `error_detail`, `conflict_reason` | string |  |

**Errors:** `400` validation، `401`، `403` (ناقص capability)، `404`، `429` (30 في الدقيقة).

## الـ AI جوه المحادثة

### POST /api/conversations/{id}/ai-suggestion/

بيطلب من الـ AI مسودة رد على المحادثة مبنية على الـ knowledge base بتاعة المؤسسة. **ما بيبعتش حاجة:** مفيش message بتتعمل، ومفيش حاجة توصل للعميل، ومفيش تغيير في ownership أو unread أو first-response أو status أو routing. المسودة بترجع للمتصفح، والموظف هو اللي يحطها في الـ composer ويدوس Send.

**الشروط:** الموظف معاه `conversation.reply`، والمؤسسة جوه الـ AI pilot، والـ connection بتاع المحادثة على وضع `SUGGEST`. أي شرط ناقص = `404` (عشان الـ composer ما يعرضش ميزة المستخدم مش قادر يستخدمها).

| Path param | Type | الوصف |
| --- | --- | --- |
| `id` | integer | رقم المحادثة |

**Request body** (`SuggestionRequest`): كل الـ fields اختيارية.

| Field | Type | Default | الوصف |
| --- | --- | --- | --- |
| `regenerate` | boolean | `false` | لو `true` بيلغي المسودة المعلّقة بتاعة الموظف ده على المحادثة دي ويطلب واحدة جديدة، وبيتحسب في عدد الـ regenerations |

```json
{ "regenerate": false }
```

**Response `200`** (`SuggestionResponse`): اقرا `status` الأول، ولا تحط `draft` فاضي في الـ composer أبداً.

| `status` | المعنى | `draft` |
| --- | --- | --- |
| `ANSWERED` | في مسودة. `citations` ممكن تكون فاضية لو الرد محادثة بحتة من غير أي ادعاء واقعي، وأي ادعاء واقعي بيتوثّق | فيها المسودة |
| `NOT_IN_KB` | الـ knowledge base ما تدعمش رد. `error_code` بيحدد السبب: `attachment_review_required` أو `no_customer_message` أو `no_knowledge_base` | فاضي |
| `CONFLICTING_KNOWLEDGE` | مصدرين أو أكتر متناقضين. `citations` بيسمّي المصادر اللي مختلفة عشان حد يصلحها | فاضي |
| `ERROR` | الـ provider فشل | فاضي |

| Field | Type | الوصف |
| --- | --- | --- |
| `suggestion_id` | uuid | بيتستخدم في endpoint الـ outcome تحت |
| `status` | string |  |
| `draft` | string |  |
| `citations` | `SuggestionCitation[]` | `source_id`, `source_title`, `source_type`, `chunk_id`, `rank`, `score` |
| `retrieved` | `RetrievedChunk[]` |  |
| `through_message_id` | integer أو null | آخر message اتكتبت المسودة بناءً عليها. لو في message أحدث بعدها يبقى المسودة قديمة (stale) |
| `attempt` | integer | رقم المحاولة |
| `context_messages` | integer | عدد الرسائل اللي دخلت في السياق |
| `model`, `provider`, `policy_version` | string |  |
| `duration_ms`, `retrieval_ms` | integer |  |
| `input_tokens`, `output_tokens`, `cached_tokens`, `total_tokens` | integer |  |
| `error_code`, `error_detail`, `conflict_reason` | string |  |

**Errors:** `400`, `401`, `403`, `404`, `429` (الـ endpoint عليه throttling).

### POST /api/ai/suggestions/{public\_id}/outcome/

بيسجّل الموظف عمل إيه بالمسودة. `USED` معناها المسودة اتحطت في الـ composer، ومش بترسل حاجة ولا بتعمل message. ده telemetry بس: فشله ما بيأثرش على أي حاجة الموظف يقدر يعملها.

| Param | Type | الوصف |
| --- | --- | --- |
| `public_id` (path) | uuid | هو `suggestion_id` من رد الـ ai-suggestion |
| `outcome` (body) | enum | `USED` أو `DISCARDED` |

```json
{ "outcome": "USED" }
```

**Response `200`:** نفس شكل `SuggestionOutcome`. **Errors:** `401`, `403`, `404`.

### POST /api/conversations/{id}/ai-resume/

بيرجّع الـ AI يرد على المحادثة تاني بعد ما كان واقف. الإيقاف بيحصل لما يتم handoff أو لما زميل ياخد المحادثة، وبيفضل ثابت حتى لو العميل بعت رسايل جديدة. الـ endpoint ده بيخلّي الأدمن اللي صلّح الـ knowledge base يجرّبها على المحادثة اللي كشفت الثغرة.

- الـ capability المطلوبة: `ai_knowledge.manage`
- من غير request body
- `404` لو المؤسسة برا الـ AI pilot
- Response `200`: `ConversationDetail` (فيه `ai_state` المحدّث)
- Errors: `401`, `403`, `404`

### حقول الـ AI في بيانات المحادثة

في `ConversationDetail` (read-only):

| Field | Type | الوصف |
| --- | --- | --- |
| `ai_assist_mode` | string | وضع الـ AI للمحادثة (string للقراءة بس، والقيم هي نفس أوضاع الـ agent-settings) (`OFF` / `SUGGEST` / `AUTO`) |
| `ai_state` | `AIConversationState` | الحالة الحالية للـ AI على المحادثة دي |

`AIConversationState`:

| Field | Type | الوصف |
| --- | --- | --- |
| `has_replied` | boolean | هل الـ AI رد على المحادثة |
| `last_replied_at` | date-time أو null |  |
| `is_paused` | boolean | هل الـ AI موقوف على المحادثة |
| `paused_at` | date-time أو null |  |
| `paused_reason` | string | كود `HandoffReason` مش جملة، والواجهة هي اللي بتترجمه |

### مواضع تانية بيظهر فيها الـ AI

| المكان | القيمة |
| --- | --- |
| `نوع المرسل` للرسائل (`SenderTypeEnum`) | `AI` |
| أحداث المحادثة (`ConversationEventTypeEnum`) | `AI_REPLIED` و `AI_HANDED_OFF` و `AI_RESUMED` |
| الموظف الحالي (`CurrentEmployee`) | `ai_knowledge_enabled` |

## مرجع الـ Schemas المشتركة

### Citation

مصدر جملة معينة في الإجابة (بتظهر في `PlaygroundResponse.citations`، ونفس الـ fields في `SuggestionCitation`).

| Field | Type |
| --- | --- |
| `source_id` | uuid |
| `source_title` | string |
| `source_type` | string |
| `chunk_id` | uuid |
| `rank` | integer |
| `score` | double |

### RetrievedChunk

مرشّح من الـ retrieval لأغراض التشخيص. فيه نص الـ chunk عن قصد، وده مش موجود في الـ citations.

| Field | Type |
| --- | --- |
| `rank` | integer |
| `score` | double |
| `chunk_id` | uuid |
| `chunk_index` | integer |
| `text` | string |
| `source_id` | uuid |
| `source_title` | string |
| `source_type` | string |

### Enums

| Enum | القيم |
| --- | --- |
| `AIAgentSettingUpdateModeEnum` | `OFF`, `SUGGEST`, `AUTO` |
| `ReadinessStateEnum` | `NOT_READY`, `READY_FOR_SUGGEST`, `READY_FOR_AUTO` |
| `RolloutStateEnum` | `INTERNAL`, `PILOT`, `LIMITED`, `GENERAL` |
| `OutcomeEnum` | `USED`, `DISCARDED` |
| status في `PlaygroundResponse` | `ANSWERED`, `NOT_IN_KB`, `ERROR` |
| status في `SuggestionResponse` | `ANSWERED`, `NOT_IN_KB`, `CONFLICTING_KNOWLEDGE`, `ERROR` |

### ApiError

```json
{ "error": { "code": "string", "message": "string", "details": {} } }
```

| Field | Type | الوصف |
| --- | --- | --- |
| `error.code` | string | سبب machine-readable (مثلاً `validation_error`, `not_found`, `throttled`) |
| `error.message` | string | ملخص مقروء وآمن للعرض |
| `error.details` | object | أخطاء الحقول `{field: [message]}` أو `{}` |

### ملاحظات للمطوّر

- الـ `blocking` و`warnings` و`paused_reason` و`error_code` كلها أكواد، والواجهة هي المسؤولة عن ترجمتها.
- الواجهة ما تعتمدش على نفسها في الأمان: السيرفر بيرفض الأوضاع اللي الـ readiness ما بتسمحش بيها حتى لو اتبعتت.
- الـ spec الأصلي: `GET https://scenariomnchnl.tech/api/schema/` (الـ Swagger UI على `/api/docs/`).

## Sources

- [Scenario Omnichannel API — Swagger UI](https://scenariomnchnl.tech/api/docs/) (OpenAPI 3.0.3، الإصدار 1.0.0، اتقرا بتاريخ 2026-11-02)
