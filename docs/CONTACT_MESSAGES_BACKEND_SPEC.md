# Contact messages — backend contract (proposed)

Lets an agent share a phone contact (name + one phone number) in a conversation, and lets the app show contacts that customers send. This document is the backend half. The mobile app will not ship the feature until this contract is live.

**Status (2026-11-18):** shipped on the backend; built on mobile (`lib/features/messages/contact_share.dart`).

What the live schema shipped, where it differs from the proposal below:

- `CONTACT`, `Reply.contacts`, `Message.contacts`, `ContactCard {name, phones}` and `ContactPhone {phone, type, wa_id (read-only)}` match.
- `contact_delivery` is a free-form, nullable **object**, not the `"native" | "text_fallback"` string of §2.4, and its keys are not documented. The app stores it unread and shows no "sent as text" note until its shape is documented.
- There is **no per-conversation capability field** (§2.5). The app offers Contact wherever it offers attachments; a channel that refuses comes back through the normal failed-send path with the server's reason and a retry.
- Still open: what Messenger, Instagram and TikTok do with a contact (§2.5), and whether `text` carries the summary of §2.4.

*Earlier status (2026-11-17): not supported by the backend; backend first, then mobile.*

---

## 1. What exists today

Checked against the live OpenAPI schema (`/api/schema/`) and the deployed web client on 2026-11-17.

| Area | Today | Why it is not enough |
|---|---|---|
| `MessageTypeEnum` | `TEXT`, `IMAGE`, `VIDEO`, `AUDIO`, `FILE`, `STICKER`, `TEMPLATE`, `SYSTEM` | No `CONTACT` type. |
| `POST /conversations/{id}/reply/` (`Reply`) | `text`, `message_type`, `reply_to_id`, `attachment_ids`, `client_message_id`, `suggestion_id` | No field that carries a name and a phone number. |
| `POST /conversations/{id}/attachments/` | Re-derives the file type from its bytes; accepted types and size depend on the conversation's platform. The accepted list is not published. | A `.vcf` would be judged as a document. WhatsApp's document types do not include vCard, so it is likely rejected. If it were accepted, the customer would receive a file, not a contact. |
| `Message.content_notice` | `{kind: share_post \| template \| unsupported, provider_type, …}` | A contact a customer sends is most likely recorded as `kind: "unsupported"`, so the agent sees "unsupported content" instead of the number. **Please confirm** what the WhatsApp webhook does with `type: "contacts"` today. |
| Web client | No contact sharing, no contact rendering. | — |

The mobile app will not fake any of this. That rules out a client-only message type, a `.vcf` sent as a generic file, and parsing contacts out of text.

## 2. Proposed contract

### 2.1 Message type

Add **`CONTACT`** to `MessageTypeEnum`.

### 2.2 The contact object

Shaped after the WhatsApp Cloud API `contacts` object, so the WhatsApp path needs no translation. Only the fields below are in scope for v1.

```jsonc
ContactCard {
  "name": {
    "formatted_name": "Sara Ahmed",   // required, 1–256 chars, any script (Arabic names kept as-is)
    "first_name": "Sara",             // optional
    "last_name": "Ahmed"              // optional
  },
  "phones": [                          // required, 1–5 entries
    {
      "phone": "+20 100 123 4567",     // required, 1–32 chars, kept as given (keep "+", digits, spaces)
      "type": "CELL",                  // optional: CELL | MAIN | IPHONE | HOME | WORK, or "" if unknown
      "wa_id": "201001234567"          // read-only, inbound WhatsApp only
    }
  ]
}
```

- Emails, addresses, organisation, birthday and URLs are **out of scope** for v1. The app collects only the name and the one number the agent picked.
- `phone` is stored as given. Normalise to E.164 **only when building a provider request**, and never rewrite the stored value. International numbers must survive unchanged.

### 2.3 Sending — `POST /conversations/{id}/reply/`

New optional field on `Reply`:

| Field | Type | Rule |
|---|---|---|
| `contacts` | `ContactCard[]` | Required when `message_type` is `CONTACT`; 1 item in v1. Rejected with 400 for any other `message_type`. |

When `message_type` is `CONTACT`:

- `attachment_ids` must be empty (400 `contact_with_attachments`).
- `text` must be empty (400 `contact_with_text`). WhatsApp cannot attach a caption to a contacts message.
- `reply_to_id` and `client_message_id` work as they do today.

Request example:

```json
{
  "message_type": "CONTACT",
  "contacts": [
    {
      "name": { "formatted_name": "سارة أحمد" },
      "phones": [{ "phone": "+20 100 123 4567", "type": "CELL" }]
    }
  ],
  "client_message_id": "8f0c…"
}
```

### 2.4 The stored and serialised message

`Message` (history, realtime, reply response) gains:

| Field | Type | Notes |
|---|---|---|
| `contacts` | `ContactCard[]` | Empty array for every other message type. |
| `contact_delivery` | `"native"` \| `"text_fallback"` \| `""` | How the customer actually received it (see §2.5). `""` for inbound messages and non-contact messages. |

`text` on a `CONTACT` message is a **server-built summary**, e.g. `"👤 Sara Ahmed\n+20 100 123 4567"`. It is used by:

- older apps and the current web client, which render `text` for any type they do not know (the current mobile bubble already does this), so an old client shows a readable contact instead of an empty bubble;
- push notification previews;
- inbox `last_message_preview`;
- conversation search;
- `QuotedMessage.text` when someone replies to a contact.

Response example:

```json
{
  "id": 9812,
  "message_type": "CONTACT",
  "direction": "OUTBOUND",
  "text": "👤 سارة أحمد\n+20 100 123 4567",
  "attachments": [],
  "contacts": [
    {
      "name": { "formatted_name": "سارة أحمد", "first_name": "", "last_name": "" },
      "phones": [{ "phone": "+20 100 123 4567", "type": "CELL", "wa_id": "" }]
    }
  ],
  "contact_delivery": "native",
  "delivery_status": "SENT"
}
```

### 2.5 Channel behaviour

| Provider | Outbound (agent → customer) | Inbound (customer → agent) |
|---|---|---|
| **WhatsApp** | Native Cloud API message: `{"type": "contacts", "contacts": [{name, phones}]}`. `contact_delivery: "native"`. Messaging-window and template rules apply as for any free-form message. | Webhook `type: "contacts"` → store as `CONTACT` with the `contacts` array (including `wa_id`), **instead of** an `unsupported` content notice. |
| **Facebook Messenger** | No native contact message. **Decision needed:** send the `text` summary as an ordinary text message with `contact_delivery: "text_fallback"` (recommended), or reject with 400 `contact_not_supported`. | Not applicable (Messenger has no contact message). |
| **Instagram** | Same decision as Messenger. | Not applicable. |
| **TikTok** | Same decision as Messenger. | Not applicable. |
| **MOCK** | Store only, `contact_delivery: "native"`. | — |

Whichever is chosen, the app needs to know **before** the agent picks a contact whether a conversation supports it. Please expose it on the conversation detail. Two options:

- a boolean `capabilities.contact_messages` (`true` on WhatsApp; `true` everywhere if text fallback is chosen);
- or a list `contact_delivery_mode: "native" | "text_fallback" | "unsupported"` per conversation.

The app will hide the menu option, or label it "sent as text", from that field. It will not hard-code providers.

### 2.6 Realtime

No new events. `message.created` and `message.updated` carry the same `Message` serialiser, including `contacts` and `contact_delivery`. Delivery and read updates are unchanged.

### 2.7 Privacy

- Store only what the agent sent: one name and the chosen numbers. The app never uploads an address book.
- Do not write phone numbers to application logs. Keep the provider request body in `provider_metadata` as today; it never reaches a browser.
- Contact cards follow the conversation's existing visibility and retention. No separate store.

## 3. What the mobile app will do once this ships

Decided with the product owner. Not built yet.

- **Composer:** a "Contact" / "جهة اتصال" option in the existing attachment menu, shown only when the conversation's capability field (§2.5) allows it.
- **Android picker:** a small native method channel that opens the system phone-number picker (`ACTION_PICK` with `Phone.CONTENT_TYPE`). The user picks the exact number there; the app gets a one-time grant to that row only. **No `READ_CONTACTS` permission, no permission prompt.**
- **iOS picker:** `CNContactPickerViewController` with phone numbers displayed. It runs out of process and needs **no contacts permission**. If a contact has several numbers, the user picks one in the native screen.
- **No phone number:** a contact without a number shows a message, and nothing is staged or sent.
- **Preview:** initials avatar, name, number, number type; remove and change actions. Nothing is saved locally beyond the existing composer draft behaviour.
- **Send:** `POST /reply/` with `message_type: "CONTACT"` and `contacts` exactly as in §2.3. Optimistic bubble, retry and failure handling go through the existing send path.
- **Display:** a contact card for `CONTACT` messages, sent or received, from history, realtime and after restart. It shows avatar, name and number, with Call (`tel:`) and Copy-number actions. `contact_delivery: "text_fallback"` shows a small "sent as text" note.
- **Logging:** phone numbers and names are never logged by the app.

## 4. Open questions for the backend

1. What does the WhatsApp webhook do with an inbound `contacts` message today? Is it `content_notice.kind = "unsupported"`, or dropped?
2. Messenger, Instagram and TikTok: send a text fallback, or refuse? (§2.5)
3. Which capability field shape (§2.5)?
4. Should `phones[].type` keep WhatsApp's vocabulary (`CELL`, `MAIN`, `IPHONE`, `HOME`, `WORK`) or pass through the device label (e.g. "Mobile", "جوال")? The app can send either. WhatsApp only understands its own values.
