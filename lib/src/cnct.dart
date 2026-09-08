import 'agent/agent_client.dart';
import 'chat/chat_client.dart';
import 'config.dart';
import 'contacts/contacts_client.dart';
import 'contacts/operator_auth.dart';
import 'credentials.dart';
import 'exception.dart';
import 'token_store.dart';

/// A part of CNCT a credential can open.
///
/// Not decoration: the three credentials are genuinely different keys to different doors, and an app
/// that asks [Cnct.modulesFor] what it holds can hide the tabs it cannot serve instead of finding
/// out with a 401 in front of a customer.
enum CnctModule {
  /// Live chat with an inbox, as a visitor.
  chat,

  /// The calendar: availability, bookings, reschedules, cancellations.
  bookings,

  /// Tickets raised for work somebody has to pick up.
  tickets,

  /// The account's contact directory.
  contacts,
}

/// The entry point. Holds the [CnctConfig] and hands out the clients a credential opens.
///
/// You do not have to use it — every client can be constructed directly — but it is the shortest
/// path from "here is our host and here is our key" to something working, and it is the one place
/// the host lives.
///
/// ```dart
/// final cnct = Cnct(config: CnctConfig(baseUrl: CnctHosts.development));
/// final chat = cnct.chat(CnctChatPublicKey('inbox-public-key'));
/// ```
///
/// **Swapping hosts** is [withBaseUrl]. Clients already made keep the host they were made with —
/// they hold open sockets and in-flight requests, and silently re-pointing those mid-conversation
/// would be worse than making a new client and saying so.
///
/// ```dart
/// final staging = cnct.withBaseUrl('https://staging.example.com');
/// ```
class Cnct {
  Cnct({required this.config});

  /// The short form, for the common case of a host and nothing else.
  Cnct.host(Object baseUrl) : config = CnctConfig(baseUrl: baseUrl);

  final CnctConfig config;

  /// The same SDK pointed somewhere else. Everything but the host is carried over.
  Cnct withBaseUrl(Object baseUrl) => Cnct(config: config.copyWith(baseUrl: baseUrl));

  /// What a credential opens.
  ///
  /// Contacts are absent from every list but the operator's, and that is the platform's boundary
  /// rather than this SDK's: there is no contacts surface on an API key today.
  static Set<CnctModule> modulesFor(CnctCredentials credentials) => switch (credentials) {
        CnctChatPublicKey() => const {CnctModule.chat},
        CnctApiKey() => const {CnctModule.bookings, CnctModule.tickets},
        CnctOperatorToken() => const {CnctModule.contacts},
      };

  /// Live chat, as a visitor. The credential is an inbox's public key — the one credential in this
  /// SDK that is meant to be inside your app.
  ///
  /// Pass a [tokenStore] to keep the visitor's session across restarts. The default keeps it in
  /// memory, which means a returning customer arrives as a stranger.
  CnctChatClient chat(
    CnctChatPublicKey credentials, {
    CnctTokenStore? tokenStore,
    String? storageKey,
  }) =>
      CnctChatClient(
        config: config,
        credentials: credentials,
        tokenStore: tokenStore,
        storageKey: storageKey,
      );

  /// Bookings and tickets, on an account-wide API key. **Server-side only** — see [CnctApiKey].
  CnctAgentClient agent(CnctApiKey credentials) =>
      CnctAgentClient(config: config, credentials: credentials);

  /// The contact directory, on an operator's console session.
  CnctContactsClient contacts(CnctOperatorToken credentials) =>
      CnctContactsClient(config: config, credentials: credentials);

  /// Signing an operator in, to get the token [contacts] needs.
  CnctOperatorAuth get auth => CnctOperatorAuth(config: config);

  /// The client for a credential, whatever kind it is.
  ///
  /// For an app that is handed one of the three and has to work out what it can do — a settings
  /// screen where somebody pastes whatever CNCT gave them, say. Throws
  /// [CnctErrorCode.missingCredential] for a credential this returns nothing for.
  Object clientFor(CnctCredentials credentials) => switch (credentials) {
        CnctChatPublicKey() => chat(credentials),
        CnctApiKey() => agent(credentials),
        CnctOperatorToken() => contacts(credentials),
      };
}
