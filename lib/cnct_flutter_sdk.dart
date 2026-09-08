/// The official CNCT SDK for Flutter and Dart.
///
/// Three credentials, three doors, and nothing in here renders anything:
///
/// | Credential            | Opens                        | Where it belongs                    |
/// | --------------------- | ---------------------------- | ----------------------------------- |
/// | [CnctChatPublicKey]   | Live chat, as a visitor      | Inside your app. It is already public. |
/// | [CnctApiKey]          | Bookings and tickets         | On a server you control. Account-wide. |
/// | [CnctOperatorToken]   | The contact directory        | A staff app, from a person's login. |
///
/// Start with [Cnct], or construct a client directly. Everything points at the host in
/// [CnctConfig.baseUrl], and swapping that is the only change needed to move between environments.
///
/// ```dart
/// final cnct = Cnct.host(CnctHosts.development);
/// final chat = cnct.chat(CnctChatPublicKey('the-inbox-public-key'));
/// chat.states.listen(render);
/// await chat.boot();
/// await chat.start(displayName: 'Layla');
/// await chat.send('Do you open on Fridays?');
/// ```
library;

export 'src/agent/agent_client.dart';
export 'src/agent/agent_models.dart';
export 'src/chat/chat_client.dart' show CnctChatClient, CnctSocketFactory;
export 'src/chat/chat_events.dart';
export 'src/chat/chat_models.dart';
export 'src/chat/chat_state.dart';
export 'src/cnct.dart';
export 'src/config.dart';
export 'src/contacts/contact_models.dart';
export 'src/contacts/contacts_client.dart';
export 'src/contacts/operator_auth.dart';
export 'src/credentials.dart';
export 'src/exception.dart';
export 'src/token_store.dart';
export 'src/transport.dart' show CnctTransport;
