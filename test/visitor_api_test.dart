import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_server.dart';

void main() {
  group('the inbox', () {
    test('carries widget, team and availability', () async {
      final server = FakeServer(routes: {
        'GET /api/chat/public/$publicKey': (_) => json({
              'business': 'Al Waha',
              'inbox': 'Website',
              'isActive': true,
              'greeting': 'Hello.',
              'requirePhone': true,
              'widget': {
                'brand': {
                  'color': '#1f6feb',
                  'appearance': 'auto',
                  'avatarUrl': 'https://cdn.test/logo.png',
                  'language': 'ar',
                  'showBranding': false,
                },
                'chat': {
                  'allowAttachments': false,
                  'allowEndConversation': true,
                  'start': 'message',
                  'askForRating': false,
                },
                'launcher': {'side': 'left'},
              },
              'team': [
                {'name': 'Sara', 'avatar': 'woman-curly'},
                {'name': 'Ali'},
              ],
              'availability': {
                'open': false,
                'opensAt': '2026-09-09T05:00:00.000Z',
                'assistant': true,
                'replyMinutes': null,
              },
            }),
      });
      final chat = server.client();
      final inbox = await chat.boot();

      expect(inbox.widget.brand.color, '#1f6feb');
      expect(inbox.widget.brand.appearance, CnctAppearanceSetting.auto);
      expect(inbox.widget.brand.avatarUrl, 'https://cdn.test/logo.png');
      expect(inbox.widget.brand.language, CnctLanguageSetting.ar);
      expect(inbox.widget.brand.showBranding, isFalse);
      expect(inbox.widget.chat.allowAttachments, isFalse);
      expect(inbox.widget.chat.allowEndConversation, isTrue);
      expect(inbox.widget.chat.start, CnctChatStartMode.message);
      expect(inbox.widget.chat.askForRating, isFalse);
      // Sections this SDK has no model for are kept as sent.
      expect((inbox.widget.raw['launcher'] as Map)['side'], 'left');

      expect(inbox.team.map((one) => one.name), ['Sara', 'Ali']);
      expect(inbox.team.first.kind, CnctSenderKind.person);
      expect(inbox.team.first.avatar, 'woman-curly');

      expect(inbox.availability?.open, isFalse);
      expect(inbox.availability?.assistant, isTrue);
      expect(inbox.availability?.opensAt?.isUtc, isFalse);
      expect(inbox.availability?.replyMinutes, isNull);
      chat.dispose();
    });

    test('a server that predates the widget reads as the defaults, section by section', () async {
      final server = FakeServer(routes: {
        'GET /api/chat/public/$publicKey': (_) => json({
              'business': 'Al Waha',
              'isActive': true,
              'widget': {
                // Half a section: the other half keeps its defaults rather than turning to nulls.
                'chat': {'allowEndConversation': true},
                'brand': {'color': 'not a colour'},
              },
            }),
      });
      final chat = server.client();
      final inbox = await chat.boot();
      expect(inbox.widget.chat.allowEndConversation, isTrue);
      expect(inbox.widget.chat.allowAttachments, isTrue);
      expect(inbox.widget.chat.start, CnctChatStartMode.details);
      expect(inbox.widget.chat.askForRating, isTrue);
      expect(inbox.widget.brand.color, CnctChatBrand.defaultColor);
      expect(inbox.widget.brand.appearance, CnctAppearanceSetting.light);
      expect(inbox.widget.brand.showBranding, isTrue);
      expect(inbox.team, isEmpty);
      expect(inbox.availability, isNull);

      final bare = CnctChatInbox.fromJson({'business': 'B', 'isActive': true});
      expect(bare.widget.brand.color, '#b52d93');
      chat.dispose();
    });
  });

  group('the session', () {
    test('start sends the device time zone', () async {
      final server = FakeServer();
      final chat = server.client(timeZone: () => 'Asia/Bahrain');
      await chat.start(displayName: 'Layla');
      final body = server.bodyOf(server.to('POST', '/api/chat/public/$publicKey/session').single);
      expect(body['timezone'], 'Asia/Bahrain');
      expect(body['displayName'], 'Layla');
      chat.dispose();
    });

    test('resume sends it as a query parameter, and a failing resolver sends nothing', () async {
      final store = CnctTokenStore.memory();
      await store.write('cnct_chat_$publicKey', 'visitor-token-1');

      final server = FakeServer();
      final chat = server.client(store: store, timeZone: () async => 'Europe/London');
      await chat.resume();
      expect(server.to('GET', '/api/chat/public/session').single.url.queryParameters['timezone'],
          'Europe/London');
      chat.dispose();

      final quiet = FakeServer();
      final other = quiet.client(store: store, timeZone: () => throw StateError('no plugin'));
      expect(await other.resume(), isTrue);
      expect(quiet.to('GET', '/api/chat/public/session').single.url.queryParameters,
          isNot(contains('timezone')));
      other.dispose();
    });
  });

  group('signed-in users', () {
    test('identify sends the current token and replaces it with the one it gets back', () async {
      final store = CnctTokenStore.memory();
      final server = FakeServer(routes: {
        'POST /api/chat/public/$publicKey/identify': (_) => json({
              'token': 'signed-in-token',
              'visitor': {'displayName': 'Layla', 'anonymous': false, 'identified': true},
            }),
      });
      final chat = server.client(store: store);
      await chat.start();

      final visitor = await chat.identify(const CnctChatIdentity(
        userId: 'user_42',
        userHash: 'abc123',
        name: 'Layla',
        email: 'layla@example.com',
      ));

      final call = server.to('POST', '/api/chat/public/$publicKey/identify').single;
      // The anonymous chat started before sign-in moves across because the old token goes along.
      expect(call.headers['x-chat-token'], 'visitor-token-1');
      expect(server.bodyOf(call), {
        'userId': 'user_42',
        'userHash': 'abc123',
        'name': 'Layla',
        'email': 'layla@example.com'
      });
      expect(visitor.identified, isTrue);
      expect(await store.read('cnct_chat_$publicKey'), 'signed-in-token');
      // The conversation is re-read on the new token, since it may now be the user's own.
      expect(server.to('GET', '/api/chat/public/session').last.headers['x-chat-token'],
          'signed-in-token');
      chat.dispose();
    });

    test('a 409 says identity is not set up, a 401 that the hash did not verify', () async {
      Future<CnctException> refusal(int status) async {
        final server = FakeServer(routes: {
          'POST /api/chat/public/$publicKey/identify': (_) => json({'error': 'No.'}, status),
        });
        final chat = server.client();
        try {
          await chat.identify(const CnctChatIdentity(userId: 'u', userHash: 'h'));
        } on CnctException catch (error) {
          chat.dispose();
          return error;
        }
        throw StateError('expected a refusal');
      }

      expect((await refusal(409)).code, CnctErrorCode.identityNotConfigured);
      expect((await refusal(401)).code, CnctErrorCode.identityRejected);
      expect((await refusal(401)).isUnauthenticated, isFalse);
    });

    test('a failed identify leaves the anonymous session working', () async {
      final store = CnctTokenStore.memory();
      final server = FakeServer(routes: {
        'POST /api/chat/public/$publicKey/identify': (_) => json({'error': 'Bad hash.'}, 401),
      });
      final chat = server.client(store: store);
      await chat.start();
      await expectLater(
          chat.identify(const CnctChatIdentity(userId: 'u', userHash: 'h')), throwsA(anything));
      expect(await store.read('cnct_chat_$publicKey'), 'visitor-token-1');
      await chat.send('Still here');
      chat.dispose();
    });
  });

  group('saying something', () {
    test('a tapped choice sends its title as the words and its id as replyId', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start();
      await chat.choose(const CnctFlowChoice(id: 'choice_book', title: 'Book a visit'));
      final body = server.bodyOf(server.to('POST', '/api/chat/public/messages').single);
      expect(body['body'], 'Book a visit');
      expect(body['replyId'], 'choice_book');
      chat.dispose();
    });

    test('over the socket, the send frame carries the same body', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start();
      server.socket.push(jsonEncode({
        'type': 'authenticated',
        'accepts': ['ping', 'typing', 'send'],
      }));
      await pumpEventQueue();
      server.socket.sent.clear();

      final attachment = CnctChatAttachment(
          id: 'att_1',
          kind: CnctAttachmentKind.image,
          mimeType: 'image/jpeg',
          filename: 'a.jpg',
          bytes: 3);
      final sending = chat.send('Here', attachments: [attachment], replyId: 'r1');
      await pumpEventQueue();
      final frame = jsonDecode(server.socket.sent.single) as Map<String, dynamic>;
      expect(frame['type'], 'send');
      expect(frame['attachmentIds'], ['att_1']);
      expect(frame['replyId'], 'r1');
      expect(frame['id'], frame['clientKey']);

      server.socket.push(jsonEncode({
        'type': 'ack',
        'id': frame['id'],
        'message': messageJson(
            id: 'msg_9', speaker: 'CALLER', body: 'Here', clientKey: frame['clientKey'] as String),
      }));
      expect((await sending).id, 'msg_9');
      chat.dispose();
    });

    test('a retry resends the same files and the same choice', () async {
      var calls = 0;
      late final FakeServer server;
      server = FakeServer(routes: {
        'POST /api/chat/public/messages': (request) {
          calls += 1;
          return calls == 1 ? json({'error': 'boom'}, 500) : json(server.stored(request));
        },
      });
      final chat = server.client();
      await chat.start();
      final attachment = CnctChatAttachment(
          id: 'att_1',
          kind: CnctAttachmentKind.image,
          mimeType: 'image/jpeg',
          filename: 'a.jpg',
          bytes: 3);
      await expectLater(
          chat.send('Here', attachments: [attachment], replyId: 'r1'), throwsA(anything));
      final failed = chat.state.failed.single;
      expect(failed.attachments.single.id, 'att_1');

      await chat.retry(failed.clientKey!);
      final bodies = server.to('POST', '/api/chat/public/messages').map(server.bodyOf).toList();
      expect(bodies.last['attachmentIds'], ['att_1']);
      expect(bodies.last['replyId'], 'r1');
      expect(bodies.last['clientKey'], bodies.first['clientKey']);
      chat.dispose();
    });

    test('a failed message survives the reload a reconnect does', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/messages': (_) => json({'error': 'down'}, 503),
      });
      final chat = server.client();
      await chat.start();
      await expectLater(chat.send('Can I pay by card?'), throwsA(anything));

      server.socket.push(jsonEncode({'type': 'authenticated', 'accepts': <String>[]}));
      await pumpEventQueue();

      expect(server.to('GET', '/api/chat/public/session'), isNotEmpty);
      expect(chat.state.failed.single.body, 'Can I pay by card?');
      chat.dispose();
    });

    test('a send that finds the conversation closed ends it rather than offering a retry',
        () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/messages': (_) => json({'error': 'It has ended.'}, 409),
      });
      final chat = server.client();
      await chat.start();
      await expectLater(
        chat.send('Hello?'),
        throwsA(
            isA<CnctException>().having((e) => e.code, 'code', CnctErrorCode.conversationClosed)),
      );
      expect(chat.state.status, CnctChatStatus.ended);
      expect(chat.state.failed, isEmpty);
      chat.dispose();
    });

    test('a message over four thousand characters is refused here', () async {
      final chat = FakeServer().client();
      await chat.start();
      await expectLater(
        chat.send('a' * 4001),
        throwsA(isA<CnctException>().having((e) => e.code, 'code', CnctErrorCode.tooLarge)),
      );
      chat.dispose();
    });
  });

  group('past conversations', () {
    test('the list, newest first, each with its last message', () async {
      final server = FakeServer(routes: {
        'GET /api/chat/public/conversations': (_) => json({
              'visitor': {'displayName': 'Layla'},
              'conversations': [
                {
                  ...conversationJson(),
                  'id': 'conv_2',
                  'preview': messageJson(speaker: 'OPERATOR', body: 'See you then'),
                },
                {
                  ...conversationJson(status: 'CLOSED'),
                  'rating': {'score': 5, 'comment': 'Lovely'},
                },
              ],
            }),
      });
      final chat = server.client();
      await chat.start();
      final list = await chat.conversations();
      expect(list.conversations.map((one) => one.id), ['conv_2', 'conv_1']);
      expect(list.conversations.first.preview?.body, 'See you then');
      expect(list.live?.id, 'conv_2');
      expect(list.conversations.last.rating?.score, 5);
      chat.dispose();
    });

    test('one conversation, with its messages', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start();
      final transcript = await chat.conversation('conv_1');
      expect(transcript.conversation.isClosed, isTrue);
      expect(transcript.conversation.ratable, isTrue);
      expect(transcript.messages.single.body, 'Hello — how can we help?');
      chat.dispose();
    });
  });

  group('read receipts', () {
    test('read is posted once per reply, and again for a newer one', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/conversations/conv_1/read': (_) => http.Response('', 204),
      });
      final chat = server.client();
      await chat.start();

      expect(await chat.markRead(), isTrue);
      expect(await chat.markRead(), isFalse);
      expect(await chat.markRead(), isFalse);
      final read = server.to('POST', '/api/chat/public/conversations/conv_1/read').toList();
      expect(read, hasLength(1));
      // No body, and so no content type: the server refuses one that says JSON and sends nothing.
      expect(read.single.body, isEmpty);
      expect(read.single.headers.containsKey('content-type'), isFalse);

      server.socket.push(jsonEncode({
        'type': 'chat.message',
        'payload': {
          'message': messageJson(id: 'msg_2', speaker: 'OPERATOR', body: 'Anything else?'),
        },
      }));
      await pumpEventQueue();
      expect(await chat.markRead(), isTrue);
      expect(server.to('POST', '/api/chat/public/conversations/conv_1/read'), hasLength(2));
      chat.dispose();
    });

    test('a failed report is forgotten, so the next look tries again', () async {
      var calls = 0;
      final server = FakeServer(routes: {
        'POST /api/chat/public/conversations/conv_1/read': (_) {
          calls += 1;
          return calls == 1 ? json({'error': 'down'}, 503) : http.Response('', 204);
        },
      });
      final chat = server.client();
      await chat.start();
      await expectLater(chat.markRead(), throwsA(isA<CnctException>()));
      expect(await chat.markRead(), isTrue);
      chat.dispose();
    });

    test('the visitor’s own words are not a reply to report', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/$publicKey/session': (_) => json({
              'token': 'visitor-token-1',
              'conversation': conversationJson(),
              'messages': [messageJson(speaker: 'CALLER', body: 'Hi')],
            }),
      });
      final chat = server.client();
      await chat.start();
      expect(await chat.markRead(), isFalse);
      chat.dispose();
    });

    test('chat.read says what the team has seen', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start();
      final events = <CnctChatEvent>[];
      chat.events.listen(events.add);
      final mine = await chat.send('Do you open on Fridays?');

      server.socket.push(jsonEncode({
        'type': 'chat.read',
        'payload': {'at': '2026-09-08T10:06:00.000Z'},
      }));
      await pumpEventQueue();

      expect(chat.state.conversation?.hasSeen(mine), isTrue);
      expect(events.whereType<CnctChatRead>(), hasLength(1));
      chat.dispose();
    });
  });

  group('socket frames', () {
    test('chat.message.updated replaces the message in place', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start();
      final before = chat.state.messages.length;

      server.socket.push(jsonEncode({
        'type': 'chat.message.updated',
        'payload': {'message': messageJson(body: 'Hello — how can we help you today?')},
      }));
      // One nobody has on screen is not appended out of nowhere.
      server.socket.push(jsonEncode({
        'type': 'chat.message.updated',
        'payload': {'message': messageJson(id: 'msg_unknown', body: 'Ghost')},
      }));
      await pumpEventQueue();

      expect(chat.state.messages, hasLength(before));
      expect(chat.state.messages.first.id, 'msg_1');
      expect(chat.state.messages.first.body, 'Hello — how can we help you today?');
      chat.dispose();
    });

    test('chat.conversation.updated takes the change itself, as the server sends it', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start();

      server.socket.push(jsonEncode({
        'type': 'chat.conversation.updated',
        'payload': {
          'withPerson': true,
          'assignee': {'name': 'Sara', 'avatar': 'woman-curly'},
        },
      }));
      await pumpEventQueue();
      expect(chat.state.conversation?.withPerson, isTrue);
      expect(chat.state.conversation?.assignee?.name, 'Sara');
      expect(chat.state.conversation?.id, 'conv_1');

      server.socket.push(jsonEncode({
        'type': 'chat.conversation.updated',
        'payload': {'assignee': null},
      }));
      await pumpEventQueue();
      expect(chat.state.conversation?.assignee, isNull);
      expect(chat.state.conversation?.withPerson, isTrue);
      chat.dispose();
    });

    test('chat.closed ends it, then learns whether it can be rated', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start();
      expect(chat.state.conversation?.ratable, isFalse);

      server.socket.push(jsonEncode({'type': 'chat.closed'}));
      await pumpEventQueue();

      expect(chat.state.status, CnctChatStatus.ended);
      expect(chat.state.conversation?.isClosed, isTrue);
      expect(chat.state.conversation?.ratable, isTrue);
      chat.dispose();
    });
  });

  group('rating and profile', () {
    test('a rating sends the score, then the comment as a second answer', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/conversations/conv_1/rating': (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return json({
            'conversation': {
              ...conversationJson(status: 'CLOSED', ratable: true),
              'rating': {'score': body['score'], 'comment': body['comment']},
            },
          });
        },
      });
      final chat = server.client();
      await chat.start();
      await chat.end();

      final rated = await chat.rate(4);
      expect(rated.rating?.score, 4);
      await chat.rate(4, comment: 'Quick and kind');

      final bodies = server
          .to('POST', '/api/chat/public/conversations/conv_1/rating')
          .map(server.bodyOf)
          .toList();
      expect(bodies.first, {'score': 4});
      expect(bodies.last, {'score': 4, 'comment': 'Quick and kind'});
      expect(chat.state.conversation?.rating?.comment, 'Quick and kind');
      await expectLater(chat.rate(6), throwsA(isA<CnctException>()));
      chat.dispose();
    });

    test('a profile gives the visitor a name', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/profile': (request) => json({
              'visitor': {
                'displayName': (jsonDecode(request.body) as Map)['displayName'],
                'anonymous': false,
              },
            }),
      });
      final chat = server.client();
      await chat.start();
      final visitor = await chat.updateProfile(displayName: ' Layla ', phone: '+97333112233');
      expect(visitor.displayName, 'Layla');
      expect(visitor.anonymous, isFalse);
      expect(server.bodyOf(server.to('POST', '/api/chat/public/profile').single),
          {'displayName': 'Layla', 'phone': '+97333112233'});
      expect(chat.state.visitor?.displayName, 'Layla');
      chat.dispose();
    });
  });
}
