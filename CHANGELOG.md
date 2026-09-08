# Changelog

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
