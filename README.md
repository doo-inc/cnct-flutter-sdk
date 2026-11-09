# CNCT for Flutter

The official CNCT SDK for Flutter and Dart: live chat, the calendar and tickets on a CNCT workspace,
using the credentials CNCT issues you. It comes as two packages from this one repository.

| Package             | What it is                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------- |
| `cnct_flutter_ui`   | **A ready-made chat screen.** Brandable, in English and Arabic, right to left, with photos and files both ways. |
| `cnct_flutter_sdk`  | **The headless client** the screen is built on. State and events, and no Flutter: it runs in an app, on a Dart server and in a one-file script. |

Take the screen and brand it, or take the client and build your own. The screen is made only from
the client's public API, so anything it does, your own screen can do too.

---

## Chat UI in 10 lines

```yaml
dependencies:
  cnct_flutter_ui:
    git:
      url: https://github.com/doo-inc/cnct-flutter-sdk.git
      path: cnct_flutter_ui
      ref: v1.0.0
```

```dart
import 'package:cnct_flutter_ui/cnct_flutter_ui.dart';

// As a page of its own:
Navigator.of(context).push(CnctChatPage.route(publicKey: 'your-inbox-public-key'));

// Or anywhere in a layout — a tab, a sheet:
CnctChat.publicKey('your-inbox-public-key', onClose: () => Navigator.pop(context))
```

That is a working chat. It reads its colours, logo, language and options from the inbox's settings
in the CNCT console, keeps the visitor's session so a returning customer comes back to their own
conversation, and sends the device's time zone. The headless package comes along with it, at the
same version, and `cnct_flutter_ui` re-exports it, so one import covers both.

Pin a tag rather than `main` — [the tags are here](https://github.com/doo-inc/cnct-flutter-sdk/tags).
What a client ships is what their users run, and an SDK that moves under a released app is a bug
report nobody can reproduce.

**Platform setup.** On iOS, the camera needs a sentence in your app's `ios/Runner/Info.plist`;
without it the camera crashes the app the first time it is opened:

```xml
<key>NSCameraUsageDescription</key>
<string>To take a photo and send it in the chat.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>To send photos from your library in the chat.</string>
```

Android needs nothing: the photo picker and the camera ask for no storage permission. On macOS,
file picking needs the `com.apple.security.files.user-selected.read-only` entitlement and the chat
needs `com.apple.security.network.client`. The chat's icons are Material's, so the app keeps
`uses-material-design: true` in its `pubspec.yaml`, as `flutter create` writes it.

### The options

`CnctChat`, `CnctChat.publicKey` and `CnctChatPage` take the same options as the chat UI of every
CNCT SDK, under the same names:

| Option     | What it does                                                                 | Default |
| ---------- | ---------------------------------------------------------------------------- | ------- |
| `client`   | The headless chat client — or the public key, with `CnctChat.publicKey`       | required |
| `theme`    | How it looks: see [Theming](#theming)                                         | the inbox's settings, then built-in |
| `language` | `CnctChatLanguage.en`, `.ar` or `.auto`                                       | the inbox's setting, then the device |
| `strings`  | Your own words for any key, per language: `{'en': {'writeMessage': 'Ask us anything…'}}` | none |
| `identity` | One of your signed-in users: see [Signed-in users](#signed-in-users)          | anonymous |
| `onClose`  | The header's close button; hidden when null (`CnctChatPage` pops by default)  | none |
| `onEvent`  | Analytics: `opened`, `started`, `sent`, `attachmentSent`, `ended`, `rated`    | none |

Give the chat a client of your own — `CnctChat(client: chat)` — to point it at another host, keep
the session somewhere else, or share the client with a badge that counts unread replies. The app
owns that client and disposes of it; pass `timeZone: cnctDeviceTimeZone` when you make it.

`onEvent` carries what happened and which conversation, never what anybody wrote: a customer's
words are theirs and the business's, not an analytics vendor's.

### What the screen does

It is the conversation view of CNCT's own hosted chat, ported: the business's greeting; a name form
first or typing first, as the inbox is set; the team's replies signed with a face and a first name,
the assistant's tagged "AI"; quotes; a flow's choices as buttons and the assistant's suggested
replies as chips; links that open; the typing dots, "Seen", a failed message with a retry, and a
"reconnecting" line when the network drops; "End chat" where the business allows it; and, once a
conversation is over, how it went in five faces and a way to start a new one.

It works at the largest text sizes, labels every control and message for VoiceOver and TalkBack in
the chat's language, keeps every control at least 48 points, rides above the keyboard and keeps
clear of notches.

---

## Theming

**What the app passes, then the inbox's widget settings in the CNCT console, then the built-in
defaults.** A business can brand the chat from the console without a release, or pin any part of
it in code.

```dart
CnctChat.publicKey(
  'your-inbox-public-key',
  theme: CnctChatTheme(
    primary: const Color(0xFFD7262E),
    cornerRadius: 8,
    font: 'Inter',                       // a family your app registers
    fontFallback: const ['Noto Kufi Arabic'],
    logo: const AssetImage('assets/logo.png'),
    title: 'Support',
    dark: const CnctChatColors(background: Color(0xFF000000)),
  ),
)
```

| Token            | Meaning                                         | Default |
| ---------------- | ----------------------------------------------- | ------- |
| `primary`        | Brand colour: the send button, links, accents   | the inbox's brand colour, else `#b52d93` |
| `onPrimary`      | Text and icons on `primary`                     | black or white, whichever reads on it |
| `background`     | The screen                                      | `#ffffff` light, `#0f1115` dark |
| `surface`        | Header, composer, cards                         | `#f6f7f9` light, `#171a21` dark |
| `text`           | Main text                                       | `#111418` light, `#eef0f3` dark |
| `textMuted`      | Timestamps, hints                               | `#5b6573` light, `#9aa3af` dark |
| `border`         | Dividers, outlines                              | `#e3e6ea` light, `#2a2f38` dark |
| `visitorBubble` / `onVisitorBubble` | The customer's own messages  | `primary` / `onPrimary` |
| `agentBubble` / `onAgentBubble`     | The team's and the assistant's | `surface` / `text` |
| `cornerRadius`   | Bubbles and cards                               | `18` |
| `font`           | The typeface, as a font family                  | the system's |
| `fontFallback`   | Families for characters `font` lacks — Arabic for a Latin brand font (Flutter only) | the system's fallback |
| `logo`           | The header image (`ImageProvider`)              | the inbox's logo, else the business's first letter on `primary` |
| `title`          | The header title                                | the business's name |
| `appearance`     | `CnctChatAppearance.light`, `.dark` or `.system` | the inbox's setting (`auto` is `system`) |
| `showPoweredBy`  | The "Powered by CNCT" line                       | the inbox's setting |

Colours set directly on `CnctChatTheme` apply in both appearances; `light:` and `dark:` take a
`CnctChatColors` for one appearance only and win over the shared ones. `onPrimary` follows the same
rule as the CNCT server and the hosted chat: near-black on a colour whose luminance is over 0.55,
white otherwise. Where the brand colour would not read at 4.5:1 — a pink link on a dark card, say —
the chat uses the text colour instead.

**The chat never reads your app's `ThemeData`, and never changes it.** It draws only from these
tokens, so it looks the same in a Material app, a Cupertino one or neither, and your app looks the
same around it.

---

## Arabic and right to left

Every word of the interface is in English and Arabic — the same table, word for word, as the web,
iOS and Android SDKs ([`docs/chat-ui/strings.json`](docs/chat-ui/strings.json)). The language is the
app's `language` if it gives one, then the business's setting, then the device: the first of its
preferred languages that is Arabic or English, else English. `CnctChatLanguage.auto` asks for the
device even where the business pinned a language.

```dart
CnctChat.publicKey(key, language: CnctChatLanguage.ar, strings: {
  'ar': {'writeMessage': 'اكتب سؤالك هنا…'},
  'en': {'writeMessage': 'Ask us anything…'},
});
```

What changes with Arabic:

- **The whole interface mirrors**: the header, the composer, the send arrow, the progress rings. The
  customer's own messages stay on the trailing side — the left, in Arabic.
- **Each piece of text takes its own direction** from its first strong letter, whatever the
  interface's language: an Arabic message in an English chat reads right to left, and the reverse.
  The same goes for names, the greeting, choices, file names and quotes.
- **Phone numbers, emails and links stay left to right** inside Arabic text, so "+973 3311 2233" is
  never drawn with its groups reversed.
- **Digits are Latin**, as Gulf apps write them, and times and dates are in the chat's language.
- **The business's own words are shown as written** — the greeting, the flow's text. Choosing a
  language never translates them.

---

## Attachments

Customers send photos and files from the photo library (several at once), the camera on phones, and
the file system — the system's own pickers, with no storage permission. Each file goes up the moment
it is picked, with a progress ring on its chip; the message waits until every file has arrived.

| Limit                | Value |
| -------------------- | ----- |
| Files on one message | 10 |
| Size of one file     | 50 MB |
| Pictures             | JPEG, PNG, WebP, GIF |
| Audio                | AAC, MP3, OGG, MP4 audio, AMR |
| Video                | MP4, 3GP, QuickTime |
| Documents            | PDF, Word (`.doc`, `.docx`), Excel (`.xlsx`), plain text, CSV |

The eleventh file, a file over 50 MB, or a type not on the list is refused with a sentence before a
byte is sent. **HEIC and HEIF become JPEG** — iPhones take photos in them, and CNCT does not accept
them — and photos larger than 2560 pixels on the long side are scaled down, at JPEG quality 85,
before upload; nothing is ever scaled up, and other files go exactly as they are.

What the team sends back appears in the thread: pictures inline, in their own shape, opening full
screen with pinch to zoom; everything else as a card with its name and size that downloads with the
visitor's token and opens in the share sheet, from which the customer can open it in any app or save
it.

The headless client has the same thing in two calls, and the checks as `CnctAttachmentRules`:

```dart
final upload = chat.upload(
  CnctUploadFile.bytes(bytes, filename: 'receipt.jpg', mimeType: 'image/jpeg'),
  onProgress: (progress) => print('${(progress * 100).round()}%'),
);
await chat.send('Here is the receipt', attachments: [await upload.result]);
```

`CnctUploadFile.stream(stream, length: …)` sends a large file without holding it in memory, and
`upload.cancel()` takes it back.

---

## Signed-in users

If your app has its own login, tell the chat who this is, so their conversations follow them from
phone to phone and the team sees the customer they already know rather than "Visitor 7KQ2".

**The hash is made on your server, never in the app.** It is `HMAC-SHA256(userId, the inbox's
identity secret)` in lowercase hex. The secret is in the CNCT console with the inbox's settings, and
it must never go in an app or a web page: anybody holding it can sign in as any of your customers and
read their conversations. Your server signs the user it has already authenticated:

```js
// Node, on your server. CNCT_IDENTITY_SECRET is the inbox's identity secret.
import { createHmac } from 'node:crypto';

app.get('/me/cnct-identity', requireSignedIn, (req, res) => {
  const userId = String(req.user.id);
  const userHash = createHmac('sha256', process.env.CNCT_IDENTITY_SECRET)
    .update(userId)
    .digest('hex');
  res.json({ userId, userHash, name: req.user.firstName, email: req.user.email });
});
```

The app fetches that from your server and hands it over:

```dart
final me = await yourApi.cnctIdentity(); // from the route above
CnctChat.publicKey(
  'your-inbox-public-key',
  identity: CnctChatIdentity(userId: me.userId, userHash: me.userHash, name: me.name),
)
```

The identity is applied before anything else is read, so the conversation shown is theirs, and an
anonymous chat they started before signing in moves across with them. A failure — the inbox has no
identity secret yet, or the hash does not verify — is logged for you and the customer still gets a
working anonymous chat. On the headless client it is `chat.identify(...)`, which throws
`identity_not_configured` or `identity_rejected`.

When the user signs out, clear the visitor's stored session so the next person on a shared device
does not see their conversations: `cnctPreferencesTokenStore().clear('cnct_chat_<publicKey>')` for
the default store, or the same call on a `tokenStore` of your own.

---

## The headless client

Everything below is `cnct_flutter_sdk`: no widget and no Flutter dependency, so it runs in an app,
on a Dart server and in a one-file script. Use it to build your own chat screen, or alongside
`cnct_flutter_ui` for what a screen does not do — a badge that counts unread replies, say.

```yaml
dependencies:
  cnct_flutter_sdk:
    git:
      url: https://github.com/doo-inc/cnct-flutter-sdk.git
      ref: v1.0.0
```

## The host

CNCT runs at **`https://app.doo.ooo`**, and that is where this SDK points unless you say otherwise.
One value decides where everything goes — HTTP and the WebSocket alike, because the socket origin is
derived from it rather than configured separately. There is nothing else to keep in step.

```dart
final cnct = Cnct(); // https://app.doo.ooo — the same as CnctHosts.production
```

Name another host for anything else — CNCT behind your own domain, or a CNCT on your laptop:

```dart
final cnct = Cnct.host('http://localhost:3001');
```

**Testing is not a different host.** What decides whether a booking is real is the key — a
[sandbox key](#sandbox-and-production) talks to the same `app.doo.ooo` and writes nothing real — so
there is no staging URL to remember to swap before you ship.

Before 0.2.0 the host was required and had no default, because the only CNCT deployment was a
development box and a default would have meant shipping to it by accident. `CnctHosts.development`
still compiles, deprecated, and now points at production.

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

## Two credentials, two doors

Which parts of this SDK you can use is decided entirely by what CNCT gave you. They are not
interchangeable, and the difference is not convenience — it is what happens when one leaks.

| Credential                          | Opens                    | Where it belongs                                        |
| ----------------------------------- | ------------------------ | ------------------------------------------------------- |
| `CnctChatPublicKey('…')`            | Live chat, as a visitor  | **Inside your app.** It identifies an inbox, not a person, and it is already public — it is in the URL of the hosted chat page. |
| `CnctApiKey('kaer_sk_…')`           | Bookings and tickets     | **On a server you control.** It is account-wide: it can book for, and cancel for, anybody. Mint one in the CNCT console under **Settings → Developers**. |

The SDK will tell you what it holds, which is useful for an app that hides the tabs it cannot serve
rather than discovering the answer with a 401 in front of a customer:

```dart
Cnct.modulesFor(credentials); // {CnctModule.chat} | {bookings, tickets}
```

Tickets also need the account to hold ticketing. `agent.catalogue()` lists exactly the tools a
particular account offers, so read that rather than assuming.

0.1.0 had a third, `CnctOperatorToken`, for the contact directory on a staff member's own login. It
is gone in 0.2.0: a person's login is not an integration credential. See the
[changelog](CHANGELOG.md).

---

## Sandbox and production

An API key comes in two kinds, and the key says which. The account's owner or an admin mints either
in the CNCT console, under **Settings → Developers**.

|                      | Sandbox — `kaer_sk_test_…`                             | Production — `kaer_sk_live_…`         |
| -------------------- | ------------------------------------------------------ | ------------------------------------- |
| Reads                | The real account: services, people, hours, what's free | The same                              |
| Book, move, cancel   | Kept in the account's sandbox, and findable again      | The real calendar                     |
| Raise a ticket       | Kept in the sandbox, numbered from 1                   | The real queue                        |
| Customers            | Never contacted, never looked up, never created        | Texted and filed as the account's own |
| Seen by the business | Never — not the calendar, the queue or the reports     | Everywhere                            |

Everything else is identical, and deliberately: a sandbox key runs **the same tools, the same
validation and the same refusals** as production — a time that is not free, a ticket field that does
not exist, a change inside the cancellation window are refused in production's own words. So an
integration that works in sandbox is an integration that works, and going live is swapping the key.

```dart
final key = CnctApiKey(Platform.environment['CNCT_API_KEY']!);
key.mode;      // CnctKeyMode.sandbox | CnctKeyMode.production
key.isSandbox; // true for kaer_sk_test_…

final agent = Cnct().agent(key);
final booking = await agent.bookings.create(startsAt: startsAt, customerPhone: '+97312345678');
booking.sandbox; // true — kept so you can find, move and cancel it, but nobody will ever see it
```

`agent.mode` says the same thing before anything is sent. Keys minted before there were two kinds
are plain `kaer_sk_…`, and are production.

Two things worth knowing:

- **A sandbox booking does not take its slot.** Availability is the real calendar's, so the same free
  time can be booked twice in sandbox. It is the one place sandbox is less faithful than production,
  and it is on purpose: taking the slot would block a real customer.
- **One sandbox per account**, shared by all its sandbox keys. Settings → Developers says what it
  holds and empties it.

Live chat has no sandbox mode — its credential is an inbox's public key, not an API key. To build a
chat screen without landing in the team's real queue, ask for a second web inbox and use its key.

---

## Chat

```dart
final chat = cnct.chat(CnctChatPublicKey('the-inbox-public-key'));

chat.states.listen(render);        // every change, as an immutable snapshot
chat.events.listen(onEvent);       // the things a UI does rather than shows

final inbox = await chat.boot();   // greeting, branding, the team, whether it is open
if (inbox.isActive) {
  await chat.start(displayName: 'Layla');
  await chat.send('Do you open on Fridays?');
}
```

`boot()` is readable without a session — it is the front door, and it is what tells you whether to
draw a composer at all. It also carries the inbox's `widget` settings from the console (brand
colour, appearance, logo, language, and whether attachments, ending and rating are on), a few of
the `team` by first name, and `availability`. `start()` mints a visitor, or reuses the one behind a
stored token, and opens the socket. From there, `chat.state` is everything a UI renders.

### The state

| Field           | What it is                                                                     |
| --------------- | ------------------------------------------------------------------------------ |
| `status`        | `idle` → `connecting` / `live` / `offline`, and `ended` once closed             |
| `inbox`         | What `boot()` returned                                                         |
| `conversation`  | `id`, `status`, `withPerson`, `assignee`, `seenAt`, `ratable`, `rating`, `closedAt` |
| `visitor`       | `displayName`, `anonymous` until they give a name, `identified` once signed in   |
| `messages`      | Oldest first, with `pending` and `failed` on the visitor's own                  |
| `theyAreTyping` | True while the other side is typing; clears itself                             |
| `awaiting`      | The assistant's flow when it is waiting for a choice or a kind of answer        |
| `suggestions`   | The assistant's suggested replies, while nobody has spoken since                |
| `error`         | The last failure, or null                                                       |

`offline` is not an error state. The transcript is still true, sends still go over HTTP, and a
reconnect is already backing off towards its next attempt.

### A message

| Field         | What it is |
| ------------- | ---------- |
| `speaker`     | `caller` (the visitor), `ai`, `operator` or `system` |
| `body`        | **Always reads correctly on its own**, whatever else the message carries |
| `sender`      | Who wrote it: a first name and a face key for a person, a name for the assistant |
| `type`, `data`| `text`, a card (`ticketUpdate`, `bookingUpdate`), or `other` with its fields in `data` |
| `flow`        | The assistant's structured message: `text`, `choices`, `layout`, `media`, `expects` |
| `suggestions` | Up to three short replies the assistant offers |
| `replyTo`     | The earlier message it quotes |
| `attachments` | `id`, `kind`, `mimeType`, `filename`, `bytes` |

```dart
switch (message.type) {
  case CnctMessageType.ticketUpdate:
    renderTicket(message.ticket!);   // ticketNumber, title, status, raisedAt
  case CnctMessageType.bookingUpdate:
    renderBooking(message.booking!); // title, startsAt, endsAt, status, locationName, partySize
  default:
    renderText(message.words);       // a flow's own text where it has one, else the body
}
```

An app built before a card type existed shows something true rather than an empty bubble: the
`default` branch is the whole of what an older app needs, which is what makes adding a card type a
non-breaking change. Booking times are converted to the device's zone on the way in.

A flow's choices are answered with `chat.choose(choice)`, which sends the choice's title as the
visitor's words and its id as `replyId`, so the flow follows the button rather than reading the
title as typing. `flow.expects` — `name`, `number`, `email`, `phone`, `date` — says which keyboard to
show.

### The rest of the visitor API

| Call | What it does |
| ---- | ------------ |
| `upload(file)`, `send(text, attachments:)` | Files: see [Attachments](#attachments) |
| `downloadAttachment(id)` | A file's bytes, with the visitor's token, cached by id — past conversations included |
| `identify(identity)` | Sign the visitor in: see [Signed-in users](#signed-in-users) |
| `updateProfile(displayName:, phone:)` | Give an anonymous visitor a name |
| `conversations()`, `conversation(id)` | Their conversations, newest first, and one with its messages |
| `markRead()` | Tell the team their newest reply is on screen — sent once per reply, however often you call it |
| `rate(score, comment:)` | Rate a closed conversation, 1 to 5 |
| `end()` | The visitor ends it |

The socket's `chat.read` frame sets `conversation.seenAt` — show "Seen" under the visitor's
messages up to it — and `chat.message.updated` replaces an edited message where it stands.

### Three things it does for you

**A reconnect reloads.** The platform's fan-out replays nothing after a drop — deliberately — so this
client refetches the whole transcript every time it reconnects rather than splicing a gap it cannot
measure. Rendering `state.messages` is always rendering the truth, and a message still in flight or
waiting for a retry survives the reload.

**A send is idempotent.** Every message carries a `clientKey`, unique per conversation on the server,
so a frame replayed across a reconnect returns the row it already wrote instead of writing a second
one. That is what makes `send()` safe to reject on a timeout: a failed bubble stays on screen, marked
`failed`, and `retry(clientKey)` — words, files and choice alike — cannot double-post.

**It degrades rather than breaks.** The server announces what it accepts on the handshake. Sends go
over the socket where that is offered and fall back to `POST /api/chat/public/messages` where it is
not — which covers both an older server and the ordinary case of the socket being between
connections. Nothing in your code changes either way.

### Keeping the visitor

A session token is a thirty-day secret scoped to one conversation. Held, somebody who chatted last
week comes back to their own thread; lost, they arrive as a stranger. `cnct_flutter_ui` keeps it in
`shared_preferences`. The headless client's default store is memory — it deliberately depends on no
storage plugin, because forcing `shared_preferences` on a Dart backend or `flutter_secure_storage` on
a kiosk build is a decision that belongs to the app.

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

**The time zone.** The session carries the device's IANA zone, which plain Dart cannot name —
`DateTime.timeZoneName` is an abbreviation. Pass a resolver: `cnct.chat(key, timeZone:
cnctDeviceTimeZone)` in a Flutter app with `cnct_flutter_ui`, or the zone your server runs in.

---

## Bookings and tickets

Server-side, on the API key — a sandbox one (`kaer_sk_test_…`) while you build.

```dart
final agent = Cnct().agent(CnctApiKey(Platform.environment['CNCT_API_KEY']!));

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

### Following a ticket up

Most of what happens to a ticket after it is raised is the customer asking about it, or telling you
something new. All three of these are scoped to the customer's own number:

```dart
// "Any news on my refund?"
final open = await agent.tickets.forCustomer(phone, q: 'refund');
final ticket = await agent.tickets.get(phone, open.items.first.ticketNumber);
ticket.status; // 'WAITING'
ticket.waitingOnCustomer; // true — the business is waiting on an answer from them
for (final line in ticket.history) print('${line.on}  ${line.what}');

// "The order number is 881"
final added = await agent.tickets.addTo(
  customerPhone: phone,
  ticketNumber: ticket.ticketNumber,
  note: 'The order number is 881',
);
added.resumed; // true — it was waiting on them, and is being worked on again
```

**`get` is safe to show the customer it belongs to** — no person's name on any line, no team, and
none of the notes staff write for each other. Somebody else's ticket number is refused exactly as a
number that does not exist is.

**`addTo` instead of a second ticket.** A follow-up belongs on the ticket it is about. If that ticket
was waiting on the customer it goes back to being worked on; a resolved, closed or cancelled one
refuses with `toolRefused`, and the refusal says to raise a new one. The same words twice within ten
minutes are kept once, so a retry is safe. Both need a CNCT host from 2026-09-29 or later —
`app.doo.ooo` is one.

`forCustomer` also takes `ticketNumber:` and `includeResolved: true`.

### The same tools, for an AI agent

This SDK is the REST side, at `/api/tools`. The same key opens the same tools over MCP, at
**`https://app.doo.ooo/api/mcp`** with the key as a bearer token — point any MCP client there and it
discovers them on its own. MCP also carries one tool REST does not: `request_operator`, for handing a
live phone call to a person.

### Worth knowing

**An empty list is often an instruction rather than an absence.** `bookings.people()` coming back
empty with a note means the business assigns whoever is free and you must not offer a choice of
person. Read `note`.

**A tool that declines answers `200` with a sentence.** The typed methods raise those as
`CnctException` with `CnctErrorCode.toolRefused`; `agent.call(name, args)` hands the raw map back
instead, and reaches any tool the platform adds after this SDK was published.

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

Files and signing in add their own: `too_many_files`, `too_large` and `unsupported_type` before an
upload; `attachments_off` when the inbox or the deployment takes no files; `cancelled` for an upload
taken back; `identity_not_configured` and `identity_rejected` from `identify()`.

---

---

## Limits, and one platform note

Thirty messages a minute per visitor, five session starts a minute per IP, four thousand characters a
message, ten files a message and 50 MB a file. The socket counts the same thirty the HTTP path does, so moving between them buys nothing.

**On Flutter web, only chat works out of the box.** `/api/chat/public/*` is open to every origin; the
rest of the platform is pinned to the host's configured `CORS_ORIGIN`, so a web build reaching
bookings or tickets needs that origin allowed on the server. Mobile and desktop builds are not
subject to this, and neither is a Dart backend — which is where the API key belongs anyway.

---

## Working on the SDK

```bash
dart pub get && dart analyze && dart test        # the headless package
cd example && dart analyze                       # the plain-Dart examples
cd cnct_flutter_ui && flutter analyze && flutter test   # the chat UI, screenshots included
cd example/flutter_app && flutter analyze && flutter test
```

The tests run against fakes — a mock HTTP client and a fake socket — so the whole suite is offline.
The chat UI's tests render the fixture conversation (`cnct_flutter_ui/lib/fixture.dart`), the same
one every CNCT SDK renders, and `test/screenshots_test.dart` writes it to
`cnct_flutter_ui/build/screenshots` in English and Arabic, light, dark and a custom theme. CI uploads
those as the `screenshots` artifact on every run.

The chat's words live in `docs/chat-ui/strings.json`, shared with the other SDKs. After changing it,
`dart run tool/generate_strings.dart` in `cnct_flutter_ui` rewrites the Dart table; a test fails
if the two disagree.

## Versioning

Semantic, and both packages move together: `cnct_flutter_ui` 1.0.0 is built on, and tested with,
`cnct_flutter_sdk` 1.0.0 from the same tag. Anything that changes the shape of a client's calls is
a major, and the platform's own `/sdk/v1/` promise is the one this mirrors: what a client ships is
what their users run, and we cannot deploy to it.
