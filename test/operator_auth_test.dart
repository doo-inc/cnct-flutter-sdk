import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late List<http.Request> seen;

  CnctOperatorAuth authWith(Future<http.Response> Function(http.Request) handler) {
    final config = CnctConfig(baseUrl: 'https://cnct.test');
    return CnctOperatorAuth(
      config: config,
      transport: CnctTransport(
        config: config,
        httpClient: MockClient((request) {
          seen.add(request);
          return handler(request);
        }),
      ),
    );
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  final successBody = {
    'token': 'operator-jwt',
    'user': {
      'id': 'u_1',
      'email': 'sara@example.com',
      'role': 'ADMIN',
      'mustChangePassword': false
    },
    'organization': {'id': 'org_1', 'name': 'Al Waha'},
  };

  setUp(() => seen = []);

  test('a login returns a session ready to hand to the contacts client', () async {
    final auth = authWith((_) async => json(successBody));

    final result = await auth.login(email: 'sara@example.com', password: 'secret');

    expect(result.challenge, isNull);
    expect(result.session!.email, 'sara@example.com');
    expect(result.session!.organizationName, 'Al Waha');
    expect(result.session!.credentials.headers['authorization'], 'Bearer operator-jwt');
    // Eight hours, which is what the platform issues.
    expect(result.session!.credentials.isExpired, isFalse);
    auth.close();
  });

  test('MFA is the ordinary path for an account that has it on, not an exception', () async {
    final auth = authWith((_) async => json({
          'mfaRequired': true,
          'mfaMethod': 'EMAIL',
          'mfaToken': 'pending-token',
        }));

    final result = await auth.login(email: 'sara@example.com', password: 'secret');

    expect(result.session, isNull);
    expect(result.challenge!.method, 'EMAIL');
    expect(result.challenge!.mfaToken, 'pending-token');
    auth.close();
  });

  test('verifying the code finishes the login', () async {
    final auth = authWith((_) async => json(successBody));

    final session = await auth.verifyMfa(mfaToken: 'pending-token', code: '123456');

    expect(session.userId, 'u_1');
    expect(jsonDecode(seen.single.body), {'token': 'pending-token', 'code': '123456'});
    auth.close();
  });

  test('somebody with two seats is asked which, with the list to choose from', () async {
    final auth = authWith((_) async => json({
          'error': 'You have access to more than one company. Choose which to sign in to.',
          'organizations': [
            {'slug': 'al-waha', 'name': 'Al Waha'},
            {'slug': 'noor', 'name': 'Noor'},
          ],
        }, 409));

    await expectLater(
      auth.login(email: 'sara@example.com', password: 'secret'),
      throwsA(isA<CnctChooseOrganization>().having(
        (error) => error.organizations.map((organization) => organization.slug),
        'slugs',
        ['al-waha', 'noor'],
      )),
    );
    auth.close();
  });

  test('wrong credentials are unauthenticated, and the server does not say which half', () async {
    final auth = authWith((_) async => json({'error': 'Invalid credentials'}, 401));

    await expectLater(
      auth.login(email: 'sara@example.com', password: 'wrong'),
      throwsA(isA<CnctException>()
          .having((error) => error.isUnauthenticated, 'isUnauthenticated', isTrue)
          .having((error) => error.message, 'message', 'Invalid credentials')),
    );
    auth.close();
  });

  test('whoAmI is the cheapest way to know a token is still good', () async {
    final auth = authWith((_) async => json({
          'user': {'id': 'u_1', 'email': 'sara@example.com', 'role': 'ADMIN'},
          'organization': {'id': 'org_1', 'name': 'Al Waha'},
        }));

    final session = await auth.whoAmI(CnctOperatorToken('operator-jwt'));
    expect(session.organizationName, 'Al Waha');
    expect(seen.single.url.path, '/api/auth/me');
    auth.close();
  });
}
