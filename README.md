# CNCT for Flutter

The official CNCT SDK for Flutter and Dart. Live chat, the contact directory, the calendar and
tickets — against a CNCT workspace, using the credentials CNCT issues you.

**It is headless, and that is the whole point.** There is no widget in this package, not one, and no
web view. A business building their own app has a design system already; shipping them a chat bubble
to restyle answers a question they did not ask. So this ships state and events, and the interface is
yours. [`example/flutter_app`](example/flutter_app) is a complete chat screen built on it, in about
three hundred lines you own and can delete.

It has no Flutter dependency either, so the same package runs in an app, on a Dart server and in a
one-file script.

```yaml
dependencies:
  cnct_flutter_sdk:
    git:
      url: https://github.com/doo-inc/cnct-flutter-sdk.git
      ref: main
```

Pin a tag rather than `main` the moment one exists. What a client ships is what their users run, and
an SDK that moves under a released app is a bug report nobody can reproduce.

---

## Point it at your host

One value decides where everything goes — HTTP and the WebSocket alike, because the socket origin is
derived from it rather than configured separately. There is nothing else to keep in step.

```dart
final cnct = Cnct.host('https://your-cnct-host');
```

It is **required**, with no default. There is one CNCT deployment today and it is a development box;
defaulting to it would mean shipping to production by forgetting to set something. It is named as a
constant so that swapping it later is one line:

```dart
final cnct = Cnct.host(CnctHosts.development);   // today
final cnct = Cnct.host('https://api.cnct.example'); // when there is a production hostname
```

Swapping at runtime — an environment picker in a debug menu, a remote config value, a
`--dart-define` — is `withBaseUrl`, and everything else in the config comes with it:

```dart
final staging = cnct.withBaseUrl('https://staging.example.com');
```

A base URL may carry a path, so fronting CNCT on your own domain works without a fork:
`https://theirdomain.com/support` puts every request under `/support`.

Clients already built keep the host they were built with. They hold open sockets and in-flight
requests, and silently re-pointing those mid-conversation would be worse than making a new one.

---

## Three credentials, three doors

Which parts of this SDK you can use is decided entirely by what CNCT gave you. They are not
interchangeable, and the difference is not convenience — it is what happens when one leaks.

| Credential                          | Opens                    | Where it belongs                                        |
| ----------------------------------- | ------------------------ | ------------------------------------------------------- |
| `CnctChatPublicKey('…')`            | Live chat, as a visitor  | **Inside your app.** It identifies an inbox, not a person, and it is already public — it is in the URL of the hosted chat page. |
| `CnctApiKey('kaer_sk_…')`           | Bookings and tickets     | **On a server you control.** It is account-wide: it can book for, and cancel for, anybody. |
| `CnctOperatorToken('…')`            | The contact directory    | A staff app, from a person's own login. Eight hours, carrying that person's role. |

The SDK will tell you what it holds, which is useful for an app that hides the tabs it cannot serve
rather than discovering the answer with a 401 in front of a customer:

```dart
Cnct.modulesFor(credentials); // {CnctModule.chat} | {bookings, tickets} | {contacts}
```

---

## Chat

```dart
final chat = cnct.chat(CnctChatPublicKey('the-inbox-public-key'));

chat.states.listen(render);        // every change, as an immutable snapshot
chat.events.listen(onEvent);       // the things a UI does rather than shows

final inbox = await chat.boot();   // greeting, whether it is open, whether it wants a number
if (inbox.isActive) {
  await chat.start(displayName: 'Layla');
  await chat.send('Do you open on Fridays?');
}
```

`boot()` is readable without a session — it is the front door, and it is what tells you whether to
draw a composer at all. `start()` mints a visitor, or reuses the one behind a stored token, and opens
the socket. From there, `chat.state` is everything a UI renders.

### The state

| Field           | What it is                                                                     |
| --------------- | ------------------------------------------------------------------------------ |
| `status`        | `idle` → `connecting` / `live` / `offline`, and `ended` once closed             |
| `inbox`         | What `boot()` returned                                                         |
| `conversation`  | `status`, `startedAt`, and `withPerson` — somebody is on the thread, never who  |
| `messages`      | Oldest first, with `pending` and `failed` on the visitor's own                  |
| `theyAreTyping` | True while the other side is typing; clears itself                             |
| `error`         | The last failure, or null                                                       |

`offline` is not an error state. The transcript is still true, sends still go over HTTP, and a
reconnect is already backing off towards its next attempt.

### Cards

Every message carries a `type`. It is `text` for ordinary words, and a card for the few things a
customer is meant to read as something other than a sentence.

```dart
switch (message.type) {
  case CnctMessageType.ticketUpdate:
    renderTicket(message.ticket!);   // ticketNumber, title, status, raisedAt
  case CnctMessageType.bookingUpdate:
    renderBooking(message.booking!); // title, startsAt, endsAt, status, locationName, partySize
  default:
    renderText(message.body);
}
```

**`body` always reads correctly on its own** — "We have opened ticket #1042 for this: Refund not
received" — so an app built before a card type existed shows something true rather than an empty
bubble. That `default` branch is the whole of what an older app needs, which is what makes adding a
card type a non-breaking change. An unrecognised card arrives as `CnctMessageType.other`, with its
name in `rawType` and its fields in `data`, for an app that wants to opt in early.

Booking times are converted to the device's zone on the way in: a customer reads their own clock,
not the business's.

### Three things it does for you

**A reconnect reloads.** The platform's fan-out replays nothing after a drop — deliberately — so this
client refetches the whole transcript every time it reconnects rather than splicing a gap it cannot
measure. Rendering `state.messages` is always rendering the truth.

**A send is idempotent.** Every message carries a `clientKey`, unique per conversation on the server,
so a frame replayed across a reconnect returns the row it already wrote instead of writing a second
one. That is what makes `send()` safe to reject on a timeout: a failed bubble stays on screen, marked
`failed`, and `retry(clientKey)` cannot double-post.

**It degrades rather than breaks.** The server announces what it accepts on the handshake. Sends go
over the socket where that is offered and fall back to `POST /api/chat/public/messages` where it is
not — which covers both an older server and the ordinary case of the socket being between
connections. Nothing in your code changes either way.

### Keeping the visitor

A session token is a thirty-day secret scoped to one conversation. Held, somebody who chatted last
week comes back to their own thread; lost, they arrive as a stranger. The default store is memory —
this package deliberately depends on no storage plugin, because forcing `shared_preferences` on a
Dart backend or `flutter_secure_storage` on a kiosk build is a decision that belongs to the app.

Wiring one is three callbacks:

```dart
final preferences = await SharedPreferences.getInstance();
final store = CnctTokenStore.delegate(
  read: (key) async => preferences.getString(key),
  write: (key, value) async => preferences.setString(key, value),
  clear: (key) async => preferences.remove(key),
);

final chat = cnct.chat(CnctChatPublicKey(publicKey), tokenStore: store);
await chat.resume(); // false simply means they have not been here before
```

### Identity

A visitor is anonymous until they volunteer a phone number. If your app has already signed this
person in, **pass the number you hold**: it is the difference between a thread that joins their
history and one that starts a second record for them.

```dart
await chat.start(displayName: user.name, phone: user.phone);
```

There is no signed identity handshake yet — no `setUser` with an HMAC — so this is the honest weak
spot of the channel, and `start(phone: …)` is the way around it today.

---

## Bookings and tickets

Server-side, on the API key.

```dart
final agent = cnct.agent(CnctApiKey(Platform.environment['CNCT_API_KEY']!));

final day = await agent.bookings.checkAvailability(date: '2026-09-15', partySize: 4);
if (day.isEmpty) {
  print(day.note); // "No table seats six that day." — an answer, with the reason
} else {
  final booking = await agent.bookings.create(
    startsAt: day.free.first.startsAt,   // exactly as given
    customerPhone: '+97312345678',
    name: 'Layla',
    nameIsTheCaller: true,
  );
}
```

Three things are worth knowing before you build against it.

**Pass `startsAt` back verbatim.** It is the token a slot is matched on. Rebuilding it from a parsed
`DateTime` is how a booking lands on a time that was never offered — `startsAtUtc` is for sorting and
display, never for sending.

**The phone number is the authorization boundary.** There is no ambient identity out here, so the
number is what decides whose booking may be read and changed, and the platform resolves it itself.

**`nameIsTheCaller` is small and load-bearing.** A booking's name and a customer's name are different
facts about different people: somebody booking a haircut for their daughter gives their daughter's
name, and filing that against the number renames the contact permanently. Leave it false unless the
name given is the number's own owner.

Tickets follow the platform's own sequence — list the types, read what one needs, raise it:

```dart
final types = await agent.tickets.types();
final type = await agent.tickets.type(types.items.first.ticketTypeId);
// `askFor` is already only the questions worth asking: what the platform knows is subtracted.
final ticket = await agent.tickets.create(
  ticketTypeId: type.ticketTypeId,
  title: 'Leaking tap',
  reasonUnresolved: 'Needs a plumber',
  customerPhone: '+97312345678',
  fields: {for (final field in type.askFor) field.key: answers[field.key]},
  idempotencyKey: attemptId, // retry with the same value, get the same ticket
);
```

**An empty list is often an instruction rather than an absence.** `bookings.people()` coming back
empty with a note means the business assigns whoever is free and you must not offer a choice of
person. Read `note`.

**A tool that declines answers `200` with a sentence.** The typed methods raise those as
`CnctException` with `CnctErrorCode.toolRefused`; `agent.call(name, args)` hands the raw map back
instead, and reaches any tool the platform adds after this SDK was published.

---

## Contacts

On an operator's login.

```dart
final result = await cnct.auth.login(email: '…', password: '…');
final session = result.session ?? await cnct.auth.verifyMfa(
  mfaToken: result.challenge!.mfaToken,
  code: codeFromTheirScreen,
);

final contacts = cnct.contacts(session.credentials);

var page = await contacts.list(query: 'layla', limit: 50);
print('${page.contacts.length} of ${page.total}');
while (page.hasMore) {
  page = await contacts.list(query: 'layla', cursor: page.nextCursor);
}
```

An MFA challenge is a returned value rather than an exception, because for an account with a second
factor it is the ordinary path. A person with seats in more than one account throws
`CnctChooseOrganization`, carrying the list to put in front of them.

Paging is by cursor, never offset: every inbound message touches the contact it belongs to, so the
order is being rewritten while somebody scrolls it. `nextCursor == null` is the end, and a short page
never issues one, so a list cannot spin on a final request that returns nothing. `listAll()` follows
the cursors for you — with the obvious caveat that an account with twenty-five thousand contacts will
happily give you all of them.

**A contact needs an identity**: a phone number, an email address, or your own `identifier`. A name
is not one of them — two people called Ahmed are two people. A collision throws
`CnctContactConflict` naming who it collided with, so you can offer to open that record rather than
sending somebody to the search box for a person they were just told is there.

Correcting somebody's number is `merge`, not an edit — and never do it speculatively: a shared
household number is not proof that two histories belong to one person.

---

## Errors

Everything throws `CnctException`. The `code` is stable and is the server's own where the failure
came from the server, so an answer that works for the JavaScript SDK works here.

```dart
try {
  await chat.send(text);
} on CnctException catch (error) {
  if (error.isUnauthenticated) return signInAgain();
  if (error.isRetryable) return scheduleRetry();
  show(error.message);
}
```

`offline` and `timeout` are worth retrying; a 4xx that is not `rate_limited` is not. `details` carries
the server's whole error body — the record you collided with, the accounts to choose from, the fields
that failed validation.

---

## Limits, and one platform note

Thirty messages a minute per visitor, five session starts a minute per IP, four thousand characters a
message. The socket counts the same thirty the HTTP path does, so moving between them buys nothing.

**On Flutter web, only chat works out of the box.** `/api/chat/public/*` is open to every origin; the
rest of the platform is pinned to the host's configured `CORS_ORIGIN`, so a web build reaching
contacts or bookings needs that origin allowed on the server. Mobile and desktop builds are not
subject to this, and neither is a Dart backend — which is where the API key belongs anyway.

---

## Working on the SDK

```bash
dart pub get && dart analyze && dart test        # the package
cd example && dart analyze                       # the plain-Dart examples
cd example/flutter_app && flutter analyze && flutter test
```

The tests run against fakes — a mock HTTP client and a fake socket — so the whole suite is offline
and takes under a second.

## Versioning

Semantic. Anything that changes the shape of a client's calls is a major, and the platform's own
`/sdk/v1/` promise is the one this mirrors: what a client ships is what their users run, and we
cannot deploy to it.
