# cnct_flutter_ui

The ready-made chat screen for CNCT live chat, in Flutter: brandable, in English and Arabic, right to
left, with photos and files both ways. Built on [`cnct_flutter_sdk`](../), the headless client in the
same repository, and installed alongside it from git.

```dart
CnctChat.publicKey('your-inbox-public-key', onClose: () => Navigator.pop(context))
```

Installing, theming, Arabic, attachments and signed-in users are all in the
[repository's README](../README.md). The options and theme tokens are the same as the chat UI of
every other CNCT SDK; [`docs/chat-ui/SPEC.md`](../docs/chat-ui/SPEC.md) is the contract.

## Working on it

```bash
flutter pub get
flutter analyze
flutter test                      # includes the screenshots, written to build/screenshots/
dart run tool/generate_strings.dart   # after changing docs/chat-ui/strings.json
```

`lib/fixture.dart` is the scripted conversation the tests, the screenshots and the example app's
no-key mode all render, through a fake transport and a fake socket.
