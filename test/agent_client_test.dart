import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late List<http.Request> seen;

  CnctAgentClient clientWith(
      Map<String, dynamic> Function(String tool, Map<String, dynamic> args) answer,
      {Map<String, dynamic>? catalogue}) {
    final config = CnctConfig(baseUrl: 'https://cnct.test');
    final mock = MockClient((request) async {
      seen.add(request);
      if (request.url.path == '/api/booking-tools') {
        return http.Response(
          jsonEncode(catalogue ??
              {
                'tools': [
                  {
                    'name': 'check_availability',
                    'description': 'List the free times.',
                    'parameters': {}
                  },
                ],
                'rules': {
                  'timezone': 'Asia/Bahrain',
                  'capacity': 4,
                  'slotMinutes': 30,
                  'services': [
                    {'id': 'svc_1', 'name': 'Dinner', 'durationMinutes': 90},
                  ],
                  'resources': [
                    {'id': 'res_1', 'name': 'Table 4', 'kind': 'TABLE', 'seats': 6},
                  ],
                  'policy': {'allowResourcePreference': true},
                },
              }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final tool = request.url.pathSegments.last;
      final args = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      return http.Response(jsonEncode(answer(tool, args)), 200,
          headers: {'content-type': 'application/json'});
    });
    return CnctAgentClient(
      config: config,
      credentials: CnctApiKey('kaer_sk_test'),
      transport: CnctTransport(config: config, httpClient: mock),
    );
  }

  setUp(() => seen = []);

  test('the catalogue says what this account may do, and the rules it works under', () async {
    final agent = clientWith((_, __) => {});
    final answer = await agent.catalogue();

    expect(answer.tools.single.name, 'check_availability');
    expect(answer.rules.timezone, 'Asia/Bahrain');
    expect(answer.rules.services.single.minutes, 90);
    expect(answer.rules.resources.single.seats, 6);
    // The unmodelled half is still reachable.
    expect((answer.rules.raw['policy'] as Map)['allowResourcePreference'], isTrue);
    expect(seen.single.headers['authorization'], 'Bearer kaer_sk_test');
    agent.close();
  });

  test('a tool that declines answers 200 with a sentence, and that becomes an exception', () async {
    final agent = clientWith((tool, args) => {'error': 'That time is in the past.'});

    await expectLater(
      agent.bookings.checkAvailability(date: '2020-01-01'),
      throwsA(isA<CnctException>()
          .having((error) => error.code, 'code', CnctErrorCode.toolRefused)
          .having((error) => error.message, 'message', 'That time is in the past.')),
    );
    agent.close();
  });

  test('the raw escape hatch hands a refusal back rather than raising it', () async {
    final agent = clientWith((tool, args) => {'error': 'Nope.'});
    final result = await agent.call('some_new_tool', {'x': 1});
    expect(result['error'], 'Nope.');
    agent.close();
  });

  test('availability parses, and startsAt survives as the exact token to send back', () async {
    final agent = clientWith((tool, args) => {
          'date': args['date'],
          'free': [
            {'time': '19:30', 'startsAt': '2026-09-15T16:30:00.000Z'},
            {'time': '20:00', 'startsAt': '2026-09-15T17:00:00.000Z', 'with': 'Table 4'},
          ],
          'note': 'Offer only these times.',
        });

    final day = await agent.bookings.checkAvailability(date: '2026-09-15', partySize: 4);
    expect(day.free, hasLength(2));
    expect(day.free.first.startsAt, '2026-09-15T16:30:00.000Z');
    expect(day.free.last.resourceName, 'Table 4');
    expect(day.free.first.startsAtUtc, DateTime.parse('2026-09-15T16:30:00.000Z'));

    final sent = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(sent['date'], '2026-09-15');
    expect(sent['partySize'], 4);
    agent.close();
  });

  test('an empty day is an answer with a reason, not an error', () async {
    final agent = clientWith((tool, args) => {
          'date': args['date'],
          'free': <Object>[],
          'note': 'No table seats six that day. Offer the caller another date.',
        });

    final day = await agent.bookings.checkAvailability(date: '2026-09-15', partySize: 6);
    expect(day.isEmpty, isTrue);
    expect(day.note, contains('seats six'));
    agent.close();
  });

  test('creating a booking sends startsAt verbatim and names the customer by number', () async {
    final agent = clientWith((tool, args) => {
          'confirmed': true,
          'bookingId': 'bkg_1',
          'when': 'Tuesday 15 September at 19:30',
          'partySize': 4,
          'name': 'Layla',
          'with': 'Table 4',
        });

    final booking = await agent.bookings.create(
      startsAt: '2026-09-15T16:30:00.000Z',
      customerPhone: '+97312345678',
      name: 'Layla',
      partySize: 4,
    );

    expect(booking.bookingId, 'bkg_1');
    expect(booking.when, 'Tuesday 15 September at 19:30');
    expect(booking.resourceName, 'Table 4');

    final sent = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(sent['startsAt'], '2026-09-15T16:30:00.000Z');
    expect(sent['customerPhone'], '+97312345678');
    // Defaults false: a name given for somebody else must not rename the number's owner.
    expect(sent['nameIsTheCaller'], isFalse);
    agent.close();
  });

  test('an empty list of people keeps the sentence that says why', () async {
    final agent = clientWith((tool, args) => {
          'people': <Object>[],
          'note':
              'This business assigns whoever is free. Never offer the caller a choice of person.',
        });

    final people = await agent.bookings.people();
    expect(people.isEmpty, isTrue);
    expect(people.note, contains('Never offer'));
    agent.close();
  });

  test('ticket types with nothing configured come back empty and say so', () async {
    final agent = clientWith((tool, args) => {
          'types': <Object>[],
          'error': 'Not raised. No ticket types are set up on this account yet.',
        });

    final types = await agent.tickets.types();
    expect(types.isEmpty, isTrue);
    expect(types.refusal, contains('No ticket types'));
    agent.close();
  });

  test('a ticket type reports only the questions still worth asking', () async {
    final agent = clientWith((tool, args) => {
          'ticketTypeId': 'tt_1',
          'name': 'Maintenance',
          'alreadyKnown': {'flat': '12B'},
          'askFor': [
            {'key': 'issue', 'required': true, 'question': 'What is wrong?'},
            {
              'key': 'urgency',
              'required': false,
              'question': 'How urgent is it?',
              'mustBeOneOf': ['low', 'high'],
            },
          ],
        });

    final type = await agent.tickets.type('tt_1');
    expect(type.alreadyKnown['flat'], '12B');
    expect(type.askFor.map((field) => field.key), ['issue', 'urgency']);
    expect(type.askFor.last.mustBeOneOf, ['low', 'high']);
    expect(type.askFor.first.isRequired, isTrue);
    agent.close();
  });

  test('an idempotency key travels, so a retry returns the same ticket', () async {
    final agent =
        clientWith((tool, args) => {'ok': true, 'ticketNumber': 1042, 'note': 'Raised as #1042.'});

    final ticket = await agent.tickets.create(
      ticketTypeId: 'tt_1',
      title: 'Leaking tap',
      reasonUnresolved: 'Needs a plumber',
      customerPhone: '+97312345678',
      fields: {'flat': '12B'},
      idempotencyKey: 'attempt-1',
    );

    expect(ticket.ticketNumber, 1042);
    final sent = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(sent['idempotencyKey'], 'attempt-1');
    expect(sent['fields'], {'flat': '12B'});
    agent.close();
  });

  test('an HTTP failure is still an HTTP failure, not a refusal', () async {
    final config = CnctConfig(baseUrl: 'https://cnct.test');
    final agent = CnctAgentClient(
      config: config,
      credentials: CnctApiKey('kaer_sk_bad'),
      transport: CnctTransport(
        config: config,
        httpClient: MockClient((_) async => http.Response(
              '{"error":"Send an API key as `Authorization: Bearer kaer_sk_…`"}',
              401,
              headers: {'content-type': 'application/json'},
            )),
      ),
    );

    await expectLater(
      agent.bookings.services(),
      throwsA(isA<CnctException>()
          .having((error) => error.code, 'code', CnctErrorCode.unauthenticated)
          .having((error) => error.isUnauthenticated, 'isUnauthenticated', isTrue)),
    );
    agent.close();
  });
}
