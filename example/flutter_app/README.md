# CNCT chat, in a Flutter app

The chat UI from `cnct_flutter_ui` in a real app, with switches across the top for language
(Auto, English, Arabic), appearance (follow the device, light, dark) and a custom theme.

```bash
flutter pub get
flutter run                                              # the fixture: no key, no network
flutter run --dart-define=CNCT_PUBLIC_KEY=your-inbox-public-key
```

**Without a key it runs the fixture conversation**: CNCT's scripted chat, behind a fake transport
and a fake socket, the same one the SDK's tests and screenshots render. It answers what you send, so
the composer, attachments, ending and rating can all be tried with no account. Switch to Arabic to
see the whole interface mirror; the fixture's own messages switch with it.

With a key it is a live chat on that inbox. The host is optional: without
`--dart-define=CNCT_BASE_URL=…` the app talks to CNCT production, `https://app.doo.ooo`.

All of it is `lib/main.dart`, and most of that is the switches: the chat itself is one widget.
