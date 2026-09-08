# CNCT chat, as a real screen

A working chat interface built on `cnct_flutter_sdk`, and deliberately an ordinary one — the bubbles,
the composer, the retry button and the cards are all this app's. Nothing here comes from the SDK,
which is the arrangement: it ships state and events, and the interface is yours.

```bash
flutter pub get
flutter run \
  --dart-define=CNCT_BASE_URL=https://your-cnct-host \
  --dart-define=CNCT_PUBLIC_KEY=your-inbox-public-key
```

Both are build flags rather than constants in the source. The host especially: it is the one value
that changes between a laptop, a staging box and production.

Three files, and each is worth reading for a different reason:

| File                | What it shows                                                                     |
| ------------------- | --------------------------------------------------------------------------------- |
| `lib/main.dart`     | Where the host lives, and what an unconfigured build should say                    |
| `lib/chat_screen.dart` | Rendering `CnctChatState`, cards with a `default` branch, a failed bubble that offers a retry |
| `lib/token_store.dart` | Persisting the visitor's session in three callbacks, so a returning customer comes back to their own thread |

Copy any of it. It is meant to be deleted once your own design system has the screen.
