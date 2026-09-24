# Changelog

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
