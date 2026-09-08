import 'exception.dart';

/// A credential CNCT issued you, and the only thing that decides which parts of this SDK you can
/// use.
///
/// There are three, they are not interchangeable, and the difference between them is not
/// convenience — it is what happens when one leaks. Each subclass says what it opens and where it
/// is safe to keep it.
sealed class CnctCredentials {
  const CnctCredentials();

  /// The headers this credential travels on. Different for each, deliberately: see
  /// [CnctChatPublicKey] for why the chat session token is not an `Authorization` header.
  Map<String, String> get headers;

  /// A redacted form, for logs and error messages. Never returns the secret.
  String get redacted;
}

/// An inbox's public key — the credential a customer-facing app carries.
///
/// **This one is meant to be in your app binary.** It identifies an inbox, not a person and not an
/// account: everything it opens is the visitor's own conversation, and a visitor is anonymous until
/// they volunteer a phone number. It is the same key that sits in the URL of the hosted chat page,
/// so it was already public.
///
/// It grants chat and nothing else. It cannot read contacts, cannot list conversations, and cannot
/// see another visitor's thread.
final class CnctChatPublicKey extends CnctCredentials {
  CnctChatPublicKey(this.publicKey) {
    if (publicKey.trim().isEmpty) {
      throw CnctException('A chat public key cannot be empty.', code: CnctErrorCode.invalid);
    }
  }

  final String publicKey;

  /// The public key is part of the path rather than a header, so there is nothing to add here. The
  /// per-visitor session token is added by the chat client itself, on `x-chat-token` — never on
  /// `Authorization`, because the platform's rate limiter keys on `ip + authorization` and a
  /// visitor who invents that header would be minting themselves a fresh budget.
  @override
  Map<String, String> get headers => const {};

  @override
  String get redacted => 'publicKey:${_tail(publicKey)}';
}

/// A server-to-server API key, minted in the console under Integrations. Starts with `kaer_sk_`.
///
/// **Do not ship this in an app.** It is account-wide: it can read and write bookings and tickets
/// for every customer the account has, and a key inside an installed binary is a key anybody with
/// the binary has. It belongs on a server you control, with the app calling that server.
///
/// The SDK will let you do it anyway — refusing outright would only push people to hand-roll the
/// same requests with less care — but [assertNotInProductionApp] exists so you can make the check
/// yourself, and the constructor logs nothing that would put the key in a crash report.
final class CnctApiKey extends CnctCredentials {
  CnctApiKey(this.key) {
    if (key.trim().isEmpty) {
      throw CnctException('An API key cannot be empty.', code: CnctErrorCode.invalid);
    }
    if (!key.startsWith(prefix)) {
      throw CnctException(
        'A CNCT API key starts with "$prefix". Check you have not pasted an inbox public key or a '
        'session token.',
        code: CnctErrorCode.invalid,
      );
    }
  }

  /// Every key ever issued begins with this. Recognisable on sight in a log or a pull request, and
  /// greppable by the secret scanners that look for exactly this shape.
  static const prefix = 'kaer_sk_';

  final String key;

  @override
  Map<String, String> get headers => {'authorization': 'Bearer $key'};

  @override
  String get redacted => 'apiKey:${_tail(key)}';

  /// Throws when this key is about to be used somewhere it should not be. Call it behind
  /// `kReleaseMode` in a Flutter app if you want the mistake to be loud rather than quiet.
  void assertNotInProductionApp() {
    throw CnctException(
      'This API key is account-wide and must not ship inside a client application. Put it on a '
      'server and have the app call that.',
      code: CnctErrorCode.invalid,
    );
  }
}

/// An operator's console session — the credential behind contacts and the rest of the account
/// surface.
///
/// It is a person's login, eight hours long, and it carries whatever that person's role allows. Use
/// it for back-office tools, internal apps and integrations run by staff. It is the wrong credential
/// for anything a customer holds.
///
/// Obtain one with `CnctOperatorAuth.login(...)`, or pass a token you already have.
final class CnctOperatorToken extends CnctCredentials {
  CnctOperatorToken(this.token, {this.expiresAt}) {
    if (token.trim().isEmpty) {
      throw CnctException('An operator token cannot be empty.', code: CnctErrorCode.invalid);
    }
  }

  final String token;

  /// When this stops working, where the caller knows. The server issues eight-hour tokens; this is
  /// filled in by `CnctOperatorAuth.login` and left null for a token handed in from elsewhere.
  final DateTime? expiresAt;

  /// True once [expiresAt] has passed. Null [expiresAt] answers false — an unknown expiry is not an
  /// expired one, and guessing would log people out of a session that still works.
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  @override
  Map<String, String> get headers => {'authorization': 'Bearer $token'};

  @override
  String get redacted => 'operator:${_tail(token)}';
}

/// The last four characters, which is enough to tell two credentials apart in a log and not enough
/// to be one. The first characters are the same on every key ever issued, so they say nothing.
String _tail(String secret) =>
    secret.length <= 4 ? '****' : '…${secret.substring(secret.length - 4)}';
