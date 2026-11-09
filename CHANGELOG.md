# Changelog

## 1.0.0

Two packages from one repository, released together: the headless client, and a ready-made chat
screen built on it. The same features, option names, theme tokens and words as the 1.0 web, iOS and
Android SDKs — [`docs/chat-ui/SPEC.md`](docs/chat-ui/SPEC.md) is the shared contract.

### `cnct_flutter_ui` — new

- **A ready-made chat screen**: `CnctChat` to embed anywhere and `CnctChatPage` as a full-screen
  route, on a client or a public key, with the spec's options — `theme`, `language`, `strings`,
  `identity`, `onClose`, `onEvent`. Install it from git with `path: cnct_flutter_ui`; it brings the
  headless package at the same commit and re-exports it.
- **Theming** with `CnctChatTheme`: the spec's tokens, light and dark, decided as the app's, then the
  inbox's console settings, then the defaults. The chat never reads or changes the app's `ThemeData`.
- **English and Arabic** from the shared string table, the whole interface mirrored right to left,
  each message in its own direction, phone numbers and links kept left to right, Latin digits.
- **Attachments both ways**: photo library, camera and files through the system pickers; refused
  with a sentence before upload when over the limits; HEIC/HEIF converted to JPEG and photos scaled
  to 2560 px; progress per file; pictures inline with a zoomable viewer, other files to the share
  sheet.
- **Signed-in users** through `identity`, applied before anything is read.
- Accessibility: labels in the chat's language, 48-point targets, the largest text sizes.
- `lib/fixture.dart`: the fixture conversation every CNCT SDK renders, on a fake transport, for
  tests, screenshots and the example app's no-key mode.

### `cnct_flutter_sdk`

- **The inbox** carries the console's `widget` settings, the `team` and `availability`.
- **Attachments**: `upload()` — one multipart part named `file`, progress per file, cancellable,
  from bytes or a stream — checked first by `CnctAttachmentRules`; `send(attachments:)` sends their
  ids; downloads are cached by id.
- **The rest of the visitor API**: `identify()`, `updateProfile()`, `conversations()`,
  `conversation(id)`, `markRead()` (once per reply), `rate()`, and `choose()` for a flow's choices
  (`send(replyId:)` underneath).
- **The full message**: `sender`, `flow`, `suggestions`, `replyTo`; conversations gain `id`,
  `assignee`, `seenAt`, `ratable`, `rating` and `closedAt`; the visitor `anonymous` and
  `identified`; the state `awaiting`, `suggestions` and `lastReply`.
- **Socket frames** `chat.message.updated` (replaced in place) and `chat.read` (`seenAt`).
- **The session sends the device's time zone**, from a resolver given to the client or to
  `Cnct.chat(timeZone:)`.
- New error codes: `too_many_files`, `unsupported_type`, `attachments_off`, `cancelled`,
  `identity_not_configured`, `identity_rejected`. `too_large` now also means a file over 50 MB.
- A reconnect's reload keeps messages still in flight or failed, where it used to drop them.
- `chat.conversation.updated` reads the change the server sends — `{status, withPerson, assignee}` —
  as well as a whole conversation.

### Changes to check when upgrading

- `downloadAttachment()` returns `Future<Uint8List>`, which is still a `List<int>`.
- A send answered 409 ends the conversation and removes its bubble, as the hosted chat does, instead
  of leaving a retry that cannot succeed.
- `send()` refuses more than 4,000 characters or ten files locally, with `too_large` and
  `too_many_files`, rather than on the wire.
- The example app is now the chat UI with switches for language, appearance and theme, and runs
  the fixture without a key; the hand-built chat screen it replaces is gone.

## 0.2.0

- **The host defaults to production, `https://app.doo.ooo`.** `CnctConfig.baseUrl` is optional and
  `Cnct()` needs no arguments. It was required in 0.1.0 because the only deployment was a development
  box. Passing a host works exactly as before, and an empty one is still refused — it is a variable
  somebody meant to set.
- **`CnctHosts.production`**. `CnctHosts.development` is deprecated: the box it named no longer
  answers, and it now points at production so code that used it still compiles and still works.
- **Sandbox keys.** A `kaer_sk_test_…` key reads the account as it really is and writes nothing real —
  see the README's _Sandbox and production_. `CnctApiKey` has `mode` (`CnctKeyMode`) and `isSandbox`,
  `CnctAgentClient` has `mode`, and `CnctBookingConfirmation` and `CnctRaisedTicket` carry `sandbox`
  (defaulting to false, so code that builds them is unaffected). Production keys are
  `kaer_sk_live_…`; keys minted before are plain `kaer_sk_…` and are production. All three still start
  `kaer_sk_`, so 0.1.0 accepts the new keys unchanged.
- Keys are minted by the account's owner or an admin in the CNCT console, under **Settings →
  Developers**.
- **Following up on a ticket.** `agent.tickets.get(phone, ticketNumber)` reads one of a customer's
  tickets as they may see it — status, whether it waits on them, their request, its fields and a
  plain history (`CnctTicketDetail`, `CnctTicketMilestone`), with no names and no staff notes.
  `agent.tickets.addTo(customerPhone:, ticketNumber:, note:)` passes their follow-up on to the open
  ticket instead of raising a second one, and starts a ticket that was waiting on them moving again
  (`CnctTicketFollowUp.resumed`). Both need a CNCT host from 2026-09-29 on.
- `agent.tickets.forCustomer(phone, q:, ticketNumber:, includeResolved:)` passes the options the
  platform always accepted.
- **The agent client calls `/api/tools`.** CNCT still answers the old `/api/booking-tools`.
- **Breaking: the operator token and contacts are removed** — `CnctOperatorToken`,
  `CnctContactsClient`, `CnctOperatorAuth`, `Cnct.contacts`, `Cnct.auth`, `CnctModule.contacts` and the
  contact models. They made a staff member's own eight-hour login into an integration credential. For a
  customer's bookings or tickets, an API key already does this by phone number; for the rest of the
  contact directory there is no key-based surface yet.

## 0.1.0

First release. Ports the CNCT web chat SDK to Dart, and adds the two credentialed surfaces a web
page has no business holding.

- **Chat** on an inbox public key: `boot`, `start`, `resume`, `send`, `retry`, `typing`, `end`, with
  the socket, the reconnect-and-refetch, the idempotent send and the HTTP fallback the JavaScript
  client has. Ticket and booking cards are typed; an unrecognised card degrades to its own body.
- **Bookings and tickets** on a `kaer_sk_` API key: availability, create, reschedule, cancel, ticket
  types and raises, plus `call()` as an escape hatch onto any tool the platform adds later.
- **Contacts** on an operator session: list with cursor paging, get, create, update, merge, tags, and
  a login that handles MFA and a person with seats in more than one account.
- `CnctConfig.baseUrl` is required and swappable at runtime with `copyWith` / `Cnct.withBaseUrl`. The
  WebSocket origin is derived from it, so there is no second URL to keep in step.
- No Flutter dependency: the package runs in Flutter, on a Dart server, and in a CLI.
