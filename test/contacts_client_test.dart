import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Map<String, dynamic> contactJson({
  String id = 'c_1',
  String? name = 'Layla',
  String? phone = '+97312345678',
  List<Map<String, dynamic>> tags = const [],
}) =>
    {
      'id': id,
      'name': name,
      'phoneNumber': phone,
      'email': null,
      'identifier': null,
      'company': 'Al Waha',
      'notes': null,
      'blocked': false,
      'customAttributes': {'plan': 'gold'},
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-09-08T10:00:00.000Z',
      'tags': tags,
      '_count': {'chatConversations': 3, 'bookings': 1},
    };

void main() {
  late List<http.Request> seen;

  CnctContactsClient clientWith(Future<http.Response> Function(http.Request) handler) {
    final config = CnctConfig(baseUrl: 'https://cnct.test');
    return CnctContactsClient(
      config: config,
      credentials: CnctOperatorToken('operator-jwt'),
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

  setUp(() => seen = []);

  test('a page carries the total and the cursor, and the token goes on Authorization', () async {
    final contacts = clientWith((_) async => json({
          'contacts': [contactJson()],
          'total': 1240,
          'nextCursor': 'cursor-2',
        }));

    final page = await contacts.list(query: 'layla', limit: 50);

    expect(page.contacts.single.displayName, 'Layla');
    expect(page.contacts.single.customAttributes['plan'], 'gold');
    expect(page.total, 1240);
    expect(page.hasMore, isTrue);
    expect(seen.single.url.queryParameters, {'q': 'layla', 'take': '50'});
    expect(seen.single.headers['authorization'], 'Bearer operator-jwt');
    contacts.close();
  });

  test('a short page issues no cursor, which is the only reliable end of a list', () async {
    final contacts = clientWith((_) async => json({
          'contacts': [contactJson()],
          'total': 1,
          'nextCursor': null,
        }));

    final page = await contacts.list();
    expect(page.hasMore, isFalse);
    contacts.close();
  });

  test('listAll follows cursors until the platform stops issuing them', () async {
    var call = 0;
    final contacts = clientWith((_) async {
      call += 1;
      return json({
        'contacts': [contactJson(id: 'c_$call')],
        'total': 3,
        'nextCursor': call < 3 ? 'cursor-$call' : null,
      });
    });

    final all = await contacts.listAll(pageSize: 1).toList();
    expect(all.map((contact) => contact.id), ['c_1', 'c_2', 'c_3']);
    expect(seen[1].url.queryParameters['cursor'], 'cursor-1');
    contacts.close();
  });

  test('a contact needs an identity, and that is refused before a request is made', () async {
    final contacts = clientWith((_) async => json({}));

    await expectLater(
      contacts.create(name: 'Just a name'),
      throwsA(isA<CnctException>().having((error) => error.code, 'code', CnctErrorCode.invalid)),
    );
    expect(seen, isEmpty);
    contacts.close();
  });

  test('a collision names who it collided with, so an app can offer to open them', () async {
    final contacts = clientWith((_) async => json({
          'error': 'Layla already has that phone number.',
          'contact': {'id': 'c_existing', 'name': 'Layla'},
        }, 409));

    await expectLater(
      contacts.create(phoneNumber: '+97312345678', name: 'Layla Ahmed'),
      throwsA(isA<CnctContactConflict>()
          .having((error) => error.existingId, 'existingId', 'c_existing')
          .having((error) => error.existingName, 'existingName', 'Layla')),
    );
    contacts.close();
  });

  test('an update sends only what changed', () async {
    final contacts = clientWith((_) async => json(contactJson(name: 'Layla Ahmed')));

    await contacts.update('c_1', name: 'Layla Ahmed', customAttributes: {'plan': null});

    final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(body.keys, ['name', 'customAttributes']);
    expect(body['customAttributes'], {'plan': null});
    expect(seen.single.method, 'PATCH');
    contacts.close();
  });

  test('tags come back with their assignment unwrapped', () async {
    final contacts = clientWith((_) async => json(contactJson(tags: [
          {
            'tag': {'id': 't_1', 'name': 'VIP', 'color': '#ffcc00'},
          },
        ])));

    final contact = await contacts.get('c_1');
    expect(contact.tags.single.name, 'VIP');
    expect(contact.tags.single.colour, '#ffcc00');
    contacts.close();
  });

  test('the tag list carries how many people wear each one', () async {
    final contacts = clientWith((_) async => json([
          {'id': 't_1', 'name': 'VIP', 'color': '#ffcc00', 'contactCount': 12},
        ]));

    final tags = await contacts.tags();
    expect(tags.single.contactCount, 12);
    contacts.close();
  });

  test('merging returns the record that was kept', () async {
    final contacts = clientWith((_) async => json({
          'merged': true,
          'contact': contactJson(id: 'c_kept'),
          'moved': {'bookings': 2},
        }));

    final kept = await contacts.merge(contactId: 'c_dupe', into: 'c_kept');
    expect(kept.id, 'c_kept');
    expect(jsonDecode(seen.single.body), {'into': 'c_kept'});
    contacts.close();
  });

  test('a display name falls back to whatever can identify somebody', () {
    expect(CnctContact.fromJson(contactJson(name: null)).displayName, '+97312345678');
    expect(CnctContact.fromJson(contactJson(name: '  ')).displayName, '+97312345678');
    expect(CnctContact.fromJson(contactJson(name: null, phone: null)).displayName, 'Unknown');
  });

  test('an expired session is a named refusal an app can act on', () async {
    final contacts = clientWith((_) async => json({'error': 'Session expired'}, 401));

    await expectLater(
      contacts.list(),
      throwsA(isA<CnctException>()
          .having((error) => error.isUnauthenticated, 'isUnauthenticated', isTrue)),
    );
    contacts.close();
  });
}
