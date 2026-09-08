import '../config.dart';
import '../credentials.dart';
import '../exception.dart';
import '../transport.dart';

/// One of the accounts a person has a seat in. Returned when a login has to be told which.
class CnctOrganizationChoice {
  const CnctOrganizationChoice({required this.slug, required this.name});

  factory CnctOrganizationChoice.fromJson(Map<String, dynamic> json) => CnctOrganizationChoice(
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  final String slug;
  final String name;
}

/// Thrown when the person signing in belongs to more than one account and did not say which.
///
/// Not a failure to recover from silently: put [organizations] in front of them and call
/// `login` again with the slug they chose.
class CnctChooseOrganization extends CnctException {
  CnctChooseOrganization(super.message, this.organizations)
      : super(code: CnctErrorCode.conflict, status: 409);

  final List<CnctOrganizationChoice> organizations;
}

/// A login that is one step from finished: the password was right, and a second factor is wanted.
///
/// Hold [mfaToken] — it is a five-minute credential and the only thing that ties the code to this
/// attempt — and call [CnctOperatorAuth.verifyMfa] with the code the person gives you.
class CnctMfaChallenge {
  const CnctMfaChallenge({required this.mfaToken, required this.method});

  /// `TOTP`, `EMAIL`. Decides what to say on the screen: an authenticator app or "check your email".
  final String method;

  /// Five minutes, and scoped to this attempt.
  final String mfaToken;
}

/// A finished login.
class CnctOperatorSession {
  const CnctOperatorSession({
    required this.credentials,
    required this.userId,
    required this.email,
    required this.role,
    required this.organizationName,
    required this.mustChangePassword,
  });

  /// Pass this to [CnctContactsClient].
  final CnctOperatorToken credentials;

  final String userId;
  final String email;

  /// Their role in this account. It decides what the rest of the API will let them do — this SDK
  /// does not second-guess it, the server does.
  final String role;

  final String organizationName;

  /// True when the platform wants a new password before real work. Honour it: the console does.
  final bool mustChangePassword;
}

/// Signing an operator in.
///
/// **This is a person's login, not an integration credential.** It lasts eight hours, it carries
/// whatever that person's role allows, and it is the right thing for a back-office app run by staff.
/// It is the wrong thing for anything a customer holds — for that, see `CnctChatPublicKey`; and for
/// unattended software, see `CnctApiKey`.
class CnctOperatorAuth {
  CnctOperatorAuth({required CnctConfig config, CnctTransport? transport})
      : _transport = transport ?? CnctTransport(config: config);

  final CnctTransport _transport;

  void close() => _transport.close();

  /// Sign in.
  ///
  /// Returns a [CnctOperatorSession] on success and a [CnctMfaChallenge] when a second factor is
  /// wanted — a record type rather than an exception, because a challenge is the ordinary path for
  /// an account with MFA on and not an error to catch.
  ///
  /// Throws [CnctChooseOrganization] when the person has seats in more than one account. Throws with
  /// [CnctErrorCode.unauthenticated] when the credentials are wrong; the server does not say which
  /// half was wrong and neither does this.
  Future<({CnctOperatorSession? session, CnctMfaChallenge? challenge})> login({
    required String email,
    required String password,
    String? organizationSlug,
  }) async {
    try {
      final json = await _transport.post('/api/auth/login', body: {
        'email': email,
        'password': password,
        if (organizationSlug != null) 'organizationSlug': organizationSlug,
      });
      final data = _map(json);
      if (data['mfaRequired'] == true) {
        return (
          session: null,
          challenge: CnctMfaChallenge(
            mfaToken: data['mfaToken'] as String? ?? '',
            method: data['mfaMethod'] as String? ?? 'TOTP',
          ),
        );
      }
      return (session: _session(data), challenge: null);
    } on CnctException catch (error) {
      throw _maybeChoice(error);
    }
  }

  /// Finish a login that wanted a second factor.
  Future<CnctOperatorSession> verifyMfa({required String mfaToken, required String code}) async {
    final json = await _transport.post(
      '/api/auth/mfa/verify',
      body: {'token': mfaToken, 'code': code},
    );
    return _session(_map(json));
  }

  /// Ask for the emailed code again, where the account's method is email.
  Future<void> resendEmailCode(String mfaToken) =>
      _transport.post('/api/auth/mfa/email/resend', body: {'token': mfaToken});

  /// Who a token belongs to, and which account. Also the cheapest way to check one is still good:
  /// an expired or revoked token answers [CnctErrorCode.unauthenticated] here.
  Future<CnctOperatorSession> whoAmI(CnctOperatorToken token) async {
    final json = await _transport.get('/api/auth/me', headers: token.headers);
    final data = _map(json);
    final user = (data['user'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? const {};
    final organization =
        (data['organization'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? const {};
    return CnctOperatorSession(
      credentials: token,
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      role: user['role'] as String? ?? '',
      organizationName: organization['name'] as String? ?? '',
      mustChangePassword: user['mustChangePassword'] as bool? ?? false,
    );
  }

  CnctOperatorSession _session(Map<String, dynamic> data) {
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw CnctException(
        'The server did not return a session token.',
        code: CnctErrorCode.badResponse,
      );
    }
    final user = (data['user'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? const {};
    final organization =
        (data['organization'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? const {};
    return CnctOperatorSession(
      // Eight hours is what the platform issues. Recorded rather than assumed anywhere else, so a
      // change on the server is one constant here rather than a stale comment in three files.
      credentials:
          CnctOperatorToken(token, expiresAt: DateTime.now().add(const Duration(hours: 8))),
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      role: user['role'] as String? ?? '',
      organizationName: organization['name'] as String? ?? '',
      mustChangePassword: user['mustChangePassword'] as bool? ?? false,
    );
  }

  CnctException _maybeChoice(CnctException error) {
    if (error.status != 409) return error;
    final details = error.details;
    final list = details is Map ? details['organizations'] : null;
    final organizations = (list as List<Object?>?)
            ?.whereType<Map<Object?, Object?>>()
            .map((item) => CnctOrganizationChoice.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false) ??
        const <CnctOrganizationChoice>[];
    return CnctChooseOrganization(error.message, organizations);
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    throw CnctException(
      'Expected an object from the server and got ${value.runtimeType}.',
      code: CnctErrorCode.badResponse,
    );
  }
}
