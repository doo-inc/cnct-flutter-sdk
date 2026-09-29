# Examples

Two of them, and they need different things.

**`bin/` is plain Dart** and runs anywhere the SDK does — no Flutter, no emulator, no device:

```bash
cd example
dart pub get
CNCT_PUBLIC_KEY=… dart run bin/chat.dart
CNCT_API_KEY=kaer_sk_test_… dart run bin/bookings.dart
CNCT_API_KEY=kaer_sk_test_… dart run bin/tickets.dart
```

They go to CNCT production, `https://app.doo.ooo`, unless `CNCT_BASE_URL` says otherwise. Run the
bookings and tickets ones with a **sandbox** key (`kaer_sk_test_…`, from Settings → Developers in the
CNCT console) and nothing they book or raise is real.

**`flutter_app/` is a real app** — a chat screen, wired to `shared_preferences` so a returning
visitor comes back to their own thread:

```bash
cd example/flutter_app
flutter pub get
flutter run --dart-define=CNCT_PUBLIC_KEY=…
```

Nothing here hard-codes a host or a credential. Both read them from the environment, which is the
same habit worth keeping in a real app.
