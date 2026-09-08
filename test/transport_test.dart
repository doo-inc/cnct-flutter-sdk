import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  CnctTransport transportWith(Future<http.Response> Function(http.Request) handler,
          {CnctConfig? config}) =>
      CnctTransport(
        config: config ?? CnctConfig(baseUrl: 'https://cnct.test'),
        httpClient: MockClient(handler),
      );

  test('every request identifies the SDK, and a custom agent replaces it', () async {
    late http.Request seen;
    final transport = transportWith((request) async {
      seen = request;
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    }, config: CnctConfig(baseUrl: 'https://cnct.test', userAgent: 'their-app/2.0'));

    await transport.get('/api/anything');
    expect(seen.headers['user-agent'], 'their-app/2.0');
    expect(seen.headers['accept'], 'application/json');
  });

  test('config headers travel on every request, for a proxy in front of CNCT', () async {
    late http.Request seen;
    final transport = transportWith((request) async {
      seen = request;
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    }, config: CnctConfig(baseUrl: 'https://proxy.test/cnct', headers: {'x-tenant': 'acme'}));

    await transport.get('/api/anything');
    expect(seen.headers['x-tenant'], 'acme');
    expect(seen.url.path, '/cnct/api/anything');
  });

  group('failures map to codes worth branching on', () {
    Future<CnctException> failureFor(int status, Object body) async {
      final transport = transportWith((_) async =>
          http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'}));
      try {
        await transport.get('/api/anything');
      } on CnctException catch (error) {
        return error;
      }
      throw StateError('expected a failure');
    }

    test('401 is unauthenticated and retrying it is pointless', () async {
      final error = await failureFor(401, {'error': 'Session expired'});
      expect(error.code, CnctErrorCode.unauthenticated);
      expect(error.isRetryable, isFalse);
    });

    test('429 is retryable', () async {
      final error = await failureFor(429, {'error': 'Slow down'});
      expect(error.code, CnctErrorCode.rateLimited);
      expect(error.isRetryable, isTrue);
    });

    test('500 is retryable', () async {
      final error = await failureFor(500, {'error': 'boom'});
      expect(error.code, CnctErrorCode.serverError);
      expect(error.isRetryable, isTrue);
    });

    test('a validation refusal keeps the fields that failed', () async {
      final error = await failureFor(400, {
        'error': {
          'fieldErrors': {
            'displayName': ['Required'],
          },
          'formErrors': <String>[],
        },
      });
      expect(error.code, CnctErrorCode.invalid);
      final fields = ((error.details as Map)['error'] as Map)['fieldErrors'] as Map;
      expect(fields['displayName'], ['Required']);
    });

    test('a problem+json code wins over the status line', () async {
      final error = await failureFor(409, {
        'title': 'The requested slot is no longer available',
        'code': 'booking_conflict',
      });
      expect(error.code, 'booking_conflict');
      expect(error.message, 'The requested slot is no longer available');
    });
  });

  test('a dead network is offline, not a refusal — a UI retries one and not the other', () async {
    final transport = transportWith((_) async => throw http.ClientException('Connection refused'));
    await expectLater(
      transport.get('/api/anything'),
      throwsA(isA<CnctException>()
          .having((error) => error.code, 'code', CnctErrorCode.offline)
          .having((error) => error.isRetryable, 'isRetryable', isTrue)),
    );
  });

  test('a login page instead of JSON says so, rather than a null somewhere later', () async {
    final transport = transportWith((_) async =>
        http.Response('<html>sign in</html>', 200, headers: {'content-type': 'text/html'}));
    await expectLater(
      transport.get('/api/anything'),
      throwsA(
          isA<CnctException>().having((error) => error.code, 'code', CnctErrorCode.badResponse)),
    );
  });
}
