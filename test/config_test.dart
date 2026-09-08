import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('CnctConfig.baseUrl', () {
    test('takes a String or a Uri', () {
      expect(CnctConfig(baseUrl: 'https://example.com').baseUrl.host, 'example.com');
      expect(CnctConfig(baseUrl: Uri.parse('https://example.com')).baseUrl.host, 'example.com');
    });

    test('strips a trailing slash so paths are built the same way either way', () {
      final withSlash = CnctConfig(baseUrl: 'https://example.com/');
      final without = CnctConfig(baseUrl: 'https://example.com');
      expect(
        withSlash.resolve('/api/chat/public/abc').toString(),
        without.resolve('/api/chat/public/abc').toString(),
      );
    });

    test('keeps a path prefix, for a client fronting CNCT on their own domain', () {
      final config = CnctConfig(baseUrl: 'https://theirdomain.com/support');
      expect(config.resolve('/api/contacts').toString(),
          'https://theirdomain.com/support/api/contacts');
    });

    test('refuses anything that is not an absolute http(s) URL', () {
      expect(() => CnctConfig(baseUrl: 'example.com'), throwsA(isA<CnctException>()));
      expect(() => CnctConfig(baseUrl: 'ftp://example.com'), throwsA(isA<CnctException>()));
      expect(() => CnctConfig(baseUrl: 42), throwsA(isA<CnctException>()));
    });

    test('derives the socket origin rather than taking a second URL', () {
      expect(
          CnctConfig(baseUrl: 'https://example.com').socketBaseUrl.toString(), 'wss://example.com');
      expect(CnctConfig(baseUrl: 'http://localhost:3000').socketBaseUrl.toString(),
          'ws://localhost:3000');
      expect(
        CnctConfig(baseUrl: 'https://theirdomain.com/support').socketBaseUrl.toString(),
        'wss://theirdomain.com/support',
      );
    });

    test('swaps host without losing anything else', () {
      final staging = CnctConfig(
        baseUrl: 'https://staging.example.com',
        userAgent: 'their-app/2.0',
        headers: {'x-tenant': 'acme'},
        sendTimeout: const Duration(seconds: 5),
      );
      final live = staging.copyWith(baseUrl: 'https://api.example.com');
      expect(live.baseUrl.host, 'api.example.com');
      expect(live.userAgent, 'their-app/2.0');
      expect(live.headers, {'x-tenant': 'acme'});
      expect(live.sendTimeout, const Duration(seconds: 5));
    });

    test('drops empty query values rather than sending take=', () {
      final config = CnctConfig(baseUrl: 'https://example.com');
      final url = config.resolve('/api/contacts', {'q': 'layla', 'cursor': null, 'tag': ''});
      expect(url.queryParameters, {'q': 'layla'});
    });

    test('repeats a query key for a list, which is how attribute filters travel', () {
      final config = CnctConfig(baseUrl: 'https://example.com');
      final url = config.resolve('/api/contacts', {
        'attr': ['plan:gold', 'city:manama'],
      });
      expect(url.queryParametersAll['attr'], ['plan:gold', 'city:manama']);
    });
  });

  group('Cnct', () {
    test('withBaseUrl carries the rest of the config over', () {
      final cnct = Cnct(config: CnctConfig(baseUrl: 'https://a.example.com', userAgent: 'x/1'));
      final moved = cnct.withBaseUrl('https://b.example.com');
      expect(moved.config.baseUrl.host, 'b.example.com');
      expect(moved.config.userAgent, 'x/1');
    });

    test('says what each credential opens', () {
      expect(Cnct.modulesFor(CnctChatPublicKey('pk')), {CnctModule.chat});
      expect(
        Cnct.modulesFor(CnctApiKey('kaer_sk_abcdef')),
        {CnctModule.bookings, CnctModule.tickets},
      );
      expect(Cnct.modulesFor(CnctOperatorToken('jwt')), {CnctModule.contacts});
    });
  });

  group('credentials', () {
    test('an API key must look like one', () {
      expect(() => CnctApiKey('sk-not-ours'), throwsA(isA<CnctException>()));
      expect(CnctApiKey('kaer_sk_abcdef').headers['authorization'], 'Bearer kaer_sk_abcdef');
    });

    test('redaction shows the tail, never the head — every key starts the same', () {
      expect(CnctApiKey('kaer_sk_abcdefgh').redacted, 'apiKey:…efgh');
      expect(CnctChatPublicKey('inbox-key-1234').redacted, 'publicKey:…1234');
    });

    test('a chat public key travels in the path, not in a header', () {
      expect(CnctChatPublicKey('pk').headers, isEmpty);
    });

    test('an operator token knows when it has expired', () {
      final stale =
          CnctOperatorToken('jwt', expiresAt: DateTime.now().subtract(const Duration(minutes: 1)));
      final fresh =
          CnctOperatorToken('jwt', expiresAt: DateTime.now().add(const Duration(hours: 1)));
      expect(stale.isExpired, isTrue);
      expect(fresh.isExpired, isFalse);
      // An unknown expiry is not an expired one; guessing would sign somebody out of a live session.
      expect(CnctOperatorToken('jwt').isExpired, isFalse);
    });
  });
}
