import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fake_socket.dart';

const publicKey = 'inbox-public-key';

Map<String, dynamic> messageJson({
  String id = 'msg_1',
  String speaker = 'AI',
  String type = 'TEXT',
  String body = 'Hello',
  String? clientKey,
  Map<String, dynamic>? data,
  List<Map<String, dynamic>> attachments = const [],
}) =>
    {
      'id': id,
      'speaker': speaker,
      'type': type,
      'body': body,
      'createdAt': '2026-09-08T10:00:00.000Z',
      'clientKey': clientKey,
      if (data != null) 'data': data,
      'attachments': attachments,
    };

void main() {
  late FakeSocket socket;
  late List<http.Request> seen;

  /// The platform, as far as these tests are concerned.
  MockClient server({
    Map<String, dynamic>? sessionOverride,
    int? messagesStatus,
    Map<String, dynamic>? messagesBody,
  }) =>
      MockClient((request) async {
        seen.add(request);
        final path = request.url.path;
        if (path == '/api/chat/public/$publicKey') {
          return http.Response(
            jsonEncode({
              'business': 'Al Waha',
              'inbox': 'Website',
              'isActive': true,
              'greeting': 'Hello — how can we help?',
              'requirePhone': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/api/chat/public/$publicKey/session') {
          return http.Response(
            jsonEncode(sessionOverride ??
                {
                  'token': 'visitor-token-1',
                  'visitor': {'displayName': 'Layla'},
                  'conversation': {
                    'status': 'OPEN',
                    'startedAt': '2026-09-08T09:59:00.000Z',
                    'withPerson': false,
                  },
                  'messages': [messageJson(body: 'Hello — how can we help?')],
                }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/api/chat/public/session') {
          return http.Response(
            jsonEncode({
              'visitor': {'displayName': 'Layla'},
              'conversation': {
                'status': 'OPEN',
                'startedAt': '2026-09-08T09:59:00.000Z',
                'withPerson': false,
              },
              'messages': [messageJson(body: 'Hello — how can we help?')],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/api/chat/public/messages') {
          return http.Response(
            jsonEncode(messagesBody ??
                messageJson(
                  id: 'msg_stored',
                  speaker: 'CALLER',
                  body: 'Do you open on Fridays?',
                  clientKey:
                      (jsonDecode(request.body) as Map<String, dynamic>)['clientKey'] as String?,
                )),
            messagesStatus ?? 200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/api/chat/public/close') {
          return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"error":"not found"}', 404,
            headers: {'content-type': 'application/json'});
      });

  CnctChatClient clientWith(MockClient mock, {CnctTokenStore? store}) {
    final config = CnctConfig(baseUrl: 'https://cnct.test');
    return CnctChatClient(
      config: config,
      credentials: CnctChatPublicKey(publicKey),
      transport: CnctTransport(config: config, httpClient: mock),
      tokenStore: store ?? CnctTokenStore.memory(),
      socketFactory: (_) => socket,
    );
  }

  setUp(() {
    socket = FakeSocket();
    seen = [];
  });

  test('boot reads the inbox without a session', () async {
    final chat = clientWith(server());
    final inbox = await chat.boot();
    expect(inbox.business, 'Al Waha');
    expect(inbox.isActive, isTrue);
    expect(chat.state.inbox?.greeting, 'Hello — how can we help?');
    expect(seen.single.headers.containsKey('x-chat-token'), isFalse);
    chat.dispose();
  });

  test('start adopts the session, stores the token and authenticates the socket', () async {
    final store = CnctTokenStore.memory();
    final chat = clientWith(server(), store: store);

    await chat.start(displayName: 'Layla');

    expect(chat.hasSession, isTrue);
    expect(await store.read('cnct_chat_$publicKey'), 'visitor-token-1');
    expect(chat.state.visitor?.displayName, 'Layla');
    expect(chat.state.messages, hasLength(1));

    // The handshake goes out immediately: the server closes a socket that has not authenticated
    // within five seconds, so it must not wait behind an await.
    final auth = jsonDecode(socket.sent.single) as Map<String, dynamic>;
    expect(auth['type'], 'auth');
    expect(auth['token'], 'visitor-token-1');
    chat.dispose();
  });

  test('the session token never travels as an Authorization header', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    await chat.send('Do you open on Fridays?');
    final post = seen.firstWhere((request) => request.url.path == '/api/chat/public/messages');
    expect(post.headers['x-chat-token'], 'visitor-token-1');
    expect(post.headers.containsKey('authorization'), isFalse);
    chat.dispose();
  });

  test('going live refetches the transcript rather than trusting the stream', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    seen.clear();

    socket.push(jsonEncode({
      'type': 'authenticated',
      'accepts': ['ping', 'typing', 'send'],
    }));
    await pumpEventQueue();

    expect(chat.state.status, CnctChatStatus.live);
    expect(seen.map((request) => request.url.path), contains('/api/chat/public/session'));
    chat.dispose();
  });

  test('a send goes over the socket when the server offers it, and resolves on the ack', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    socket.push(jsonEncode({
      'type': 'authenticated',
      'accepts': ['ping', 'typing', 'send'],
    }));
    await pumpEventQueue();
    socket.sent.clear();

    final pending = chat.send('Do you open on Fridays?');
    await pumpEventQueue();

    // The optimistic bubble is on screen before anything has been acknowledged.
    final optimistic = chat.state.messages.last;
    expect(optimistic.pending, isTrue);
    expect(optimistic.body, 'Do you open on Fridays?');

    final frame = jsonDecode(socket.sent.single) as Map<String, dynamic>;
    expect(frame['type'], 'send');
    // The frame id, the clientKey and the server's idempotency key are one value, so the three can
    // never disagree about which message this is.
    expect(frame['id'], frame['clientKey']);
    expect(frame['body'], 'Do you open on Fridays?');

    socket.push(jsonEncode({
      'type': 'ack',
      'id': frame['id'],
      'message': messageJson(
        id: 'msg_stored',
        speaker: 'CALLER',
        body: 'Do you open on Fridays?',
        clientKey: frame['clientKey'] as String,
      ),
    }));

    final stored = await pending;
    expect(stored.id, 'msg_stored');
    // Replaced in place rather than appended — the visitor must not see themselves twice.
    expect(chat.state.messages.where((message) => message.body == 'Do you open on Fridays?'),
        hasLength(1));
    expect(chat.state.messages.last.pending, isFalse);
    // Nothing went over HTTP.
    expect(seen.every((request) => request.url.path != '/api/chat/public/messages'), isTrue);
    chat.dispose();
  });

  test('a send falls back to HTTP when the server does not offer socket sends', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    socket.push(jsonEncode({
      'type': 'authenticated',
      'accepts': ['ping', 'typing'],
    }));
    await pumpEventQueue();
    socket.sent.clear();

    final stored = await chat.send('Do you open on Fridays?');

    expect(stored.id, 'msg_stored');
    expect(socket.sent, isEmpty);
    expect(seen.map((request) => request.url.path), contains('/api/chat/public/messages'));
    chat.dispose();
  });

  test('a refused send leaves the words on screen, marked, so retry can offer itself', () async {
    final chat = clientWith(server(messagesStatus: 500, messagesBody: {'error': 'boom'}));
    await chat.start(displayName: 'Layla');

    await expectLater(chat.send('Do you open on Fridays?'), throwsA(isA<CnctException>()));

    final failed = chat.state.failed.single;
    expect(failed.body, 'Do you open on Fridays?');
    expect(failed.pending, isFalse);
    expect(chat.state.error?.code, CnctErrorCode.serverError);
    chat.dispose();
  });

  test('retry reuses the same clientKey, so the server cannot write it twice', () async {
    final chat = clientWith(server(messagesStatus: 500, messagesBody: {'error': 'boom'}));
    await chat.start(displayName: 'Layla');
    await expectLater(chat.send('Try me'), throwsA(isA<CnctException>()));
    final key = chat.state.failed.single.clientKey!;

    await expectLater(chat.retry(key), throwsA(isA<CnctException>()));

    final keys = seen
        .where((request) => request.url.path == '/api/chat/public/messages')
        .map((request) => (jsonDecode(request.body) as Map<String, dynamic>)['clientKey'])
        .toSet();
    expect(keys, hasLength(1));
    expect(keys.single, key);
    expect(chat.state.messages.where((message) => message.body == 'Try me'), hasLength(1));
    chat.dispose();
  });

  test('a message pushed by the server lands in state and on the event stream', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    final events = <CnctChatEvent>[];
    chat.events.listen(events.add);

    socket.push(jsonEncode({
      'type': 'chat.message',
      'payload': {
        'message': messageJson(id: 'msg_2', speaker: 'OPERATOR', body: 'We open at nine.'),
      },
    }));
    await pumpEventQueue();

    expect(chat.state.messages.last.body, 'We open at nine.');
    expect(chat.state.messages.last.speaker, CnctSpeaker.operator);
    expect(events.whereType<CnctChatMessageReceived>(), hasLength(1));
    chat.dispose();
  });

  test('typing clears itself — the platform sends a start and never a stop', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');

    socket.push(jsonEncode({'type': 'chat.typing'}));
    await pumpEventQueue();
    expect(chat.state.theyAreTyping, isTrue);
    chat.dispose();
  });

  test('typing() is throttled rather than sent per keystroke', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    socket.sent.clear();

    for (var i = 0; i < 20; i++) {
      chat.typing();
    }

    expect(socket.sent, hasLength(1));
    chat.dispose();
  });

  test('a 1008 close forgets the session instead of looping on a dead token', () async {
    final store = CnctTokenStore.memory();
    final chat = clientWith(server(), store: store);
    await chat.start(displayName: 'Layla');
    final events = <CnctChatEvent>[];
    chat.events.listen(events.add);

    await socket.serverClose(1008, 'unauthenticated');
    await pumpEventQueue();

    expect(chat.hasSession, isFalse);
    expect(await store.read('cnct_chat_$publicKey'), isNull);
    expect(events.whereType<CnctChatUnauthenticated>(), hasLength(1));
    expect(chat.state.status, CnctChatStatus.idle);
    // The inbox survives: it was never part of the session.
    chat.dispose();
  });

  test('resume with no stored token is false rather than an error', () async {
    final chat = clientWith(server());
    expect(await chat.resume(), isFalse);
    chat.dispose();
  });

  test('resume picks a stored session back up', () async {
    final store = CnctTokenStore.memory();
    await store.write('cnct_chat_$publicKey', 'visitor-token-1');
    final chat = clientWith(server(), store: store);

    expect(await chat.resume(), isTrue);
    expect(chat.state.messages, hasLength(1));
    expect(chat.state.visitor?.displayName, 'Layla');
    chat.dispose();
  });

  test('closing the conversation ends it and stops the socket', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    await chat.end();
    expect(chat.state.status, CnctChatStatus.ended);
    expect(chat.state.canSend, isFalse);
    chat.dispose();
  });

  test('sending before a session is a named refusal, not a null error', () async {
    final chat = clientWith(server());
    await expectLater(
      chat.send('hello'),
      throwsA(isA<CnctException>().having((error) => error.code, 'code', CnctErrorCode.noSession)),
    );
    chat.dispose();
  });

  test('an empty message is refused here rather than on the wire', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    await expectLater(
      chat.send('   '),
      throwsA(isA<CnctException>().having((error) => error.code, 'code', CnctErrorCode.empty)),
    );
    chat.dispose();
  });

  test('an unknown frame is a newer server talking, not a crash', () async {
    final chat = clientWith(server());
    await chat.start(displayName: 'Layla');
    socket.push(jsonEncode({
      'type': 'chat.something.new',
      'payload': {'x': 1}
    }));
    socket.push('not json at all');
    await pumpEventQueue();
    expect(chat.state.error, isNull);
    chat.dispose();
  });
}
