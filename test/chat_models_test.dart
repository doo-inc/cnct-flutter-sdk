import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('cards', () {
    test('a ticket card parses into its four published fields', () {
      final message = CnctChatMessage.fromJson({
        'id': 'm1',
        'speaker': 'SYSTEM',
        'type': 'TICKET_UPDATE',
        'body': 'We have opened ticket #1042 for this: Refund not received',
        'createdAt': '2026-09-08T10:00:00.000Z',
        'data': {
          'ticketNumber': 1042,
          'title': 'Refund not received',
          'status': 'OPEN',
          'raisedAt': '2026-09-08T09:58:00.000Z',
        },
      });

      expect(message.type, CnctMessageType.ticketUpdate);
      expect(message.ticket?.ticketNumber, 1042);
      expect(message.ticket?.title, 'Refund not received');
      expect(message.booking, isNull);
    });

    test('a booking card carries where and when, and nothing internal', () {
      final message = CnctChatMessage.fromJson({
        'id': 'm2',
        'speaker': 'AI',
        'type': 'BOOKING_UPDATE',
        'body': 'Booked for Tuesday at 19:30.',
        'createdAt': '2026-09-08T10:00:00.000Z',
        'data': {
          'title': 'Dinner',
          'startsAt': '2026-09-15T16:30:00.000Z',
          'endsAt': '2026-09-15T18:00:00.000Z',
          'status': 'CONFIRMED',
          'locationName': 'Adliya',
          'partySize': 4,
        },
      });

      expect(message.booking?.partySize, 4);
      expect(message.booking?.locationName, 'Adliya');
      // Converted to the device's zone, because a customer reads their own clock.
      expect(message.booking?.startsAt.isUtc, isFalse);
    });

    test('a card type this SDK has never met degrades to text with a readable body', () {
      final message = CnctChatMessage.fromJson({
        'id': 'm3',
        'speaker': 'AI',
        'type': 'DELIVERY_UPDATE',
        'body': 'Your order is out for delivery.',
        'createdAt': '2026-09-08T10:00:00.000Z',
        'data': {'courier': 'Aramex'},
      });

      expect(message.type, CnctMessageType.other);
      expect(message.rawType, 'DELIVERY_UPDATE');
      expect(message.body, 'Your order is out for delivery.');
      // The fields are still there for an app that wants to opt in early.
      expect(message.data?['courier'], 'Aramex');
    });

    test('a malformed card does not take the message down with it', () {
      final message = CnctChatMessage.fromJson({
        'id': 'm4',
        'speaker': 'SYSTEM',
        'type': 'TICKET_UPDATE',
        'body': 'A ticket was raised.',
        'createdAt': '2026-09-08T10:00:00.000Z',
        'data': {'title': 'no number here'},
      });

      expect(message.ticket, isNull);
      expect(message.body, 'A ticket was raised.');
    });
  });

  group('speakers and statuses', () {
    test('an unknown speaker is a speaker, not an exception', () {
      expect(CnctSpeaker.parse('MARTIAN'), CnctSpeaker.unknown);
      expect(CnctSpeaker.parse('CALLER').isFromBusiness, isFalse);
      expect(CnctSpeaker.parse('OPERATOR').isFromBusiness, isTrue);
    });

    test('conversation status parses the three the platform has', () {
      expect(CnctConversationStatus.parse('OPEN'), CnctConversationStatus.open);
      expect(CnctConversationStatus.parse('SNOOZED'), CnctConversationStatus.snoozed);
      expect(CnctConversationStatus.parse('CLOSED'), CnctConversationStatus.closed);
      expect(CnctConversationStatus.parse('ARCHIVED'), CnctConversationStatus.unknown);
    });
  });

  test('attachments arrive typed', () {
    final message = CnctChatMessage.fromJson({
      'id': 'm5',
      'speaker': 'OPERATOR',
      'type': 'TEXT',
      'body': 'Here is the quote.',
      'createdAt': '2026-09-08T10:00:00.000Z',
      'attachments': [
        {
          'id': 'att_1',
          'kind': 'DOCUMENT',
          'mimeType': 'application/pdf',
          'filename': 'quote.pdf',
          'bytes': 20480,
        },
      ],
    });

    expect(message.attachments.single.kind, CnctAttachmentKind.document);
    expect(message.attachments.single.filename, 'quote.pdf');
  });

  test('state reports what a composer should do', () {
    const idle = CnctChatState();
    expect(idle.canSend, isFalse);

    final live = idle.copyWith(
      status: CnctChatStatus.live,
      conversation: CnctChatConversation(
        status: CnctConversationStatus.open,
        startedAt: DateTime.utc(2026, 9, 8),
        withPerson: false,
      ),
    );
    expect(live.canSend, isTrue);

    final ended = live.copyWith(status: CnctChatStatus.ended);
    expect(ended.canSend, isFalse);
  });

  group('the full message', () {
    final flowMessage = {
      'id': 'm10',
      'speaker': 'AI',
      'type': 'TEXT',
      'body': '1. Book a visit\n2. Talk to a person\nReply with the number',
      'createdAt': '2026-09-08T10:00:00.000Z',
      'sender': {'kind': 'ai', 'name': 'Assistant', 'mascot': 'owl', 'colour': 'teal'},
      'flow': {
        'text': 'Would you like to book a visit?',
        'layout': 'buttons',
        'choices': [
          {'id': 'c1', 'title': 'Book a visit'},
          {'id': 'c2', 'title': 'Talk to a person', 'description': 'Someone from the team'},
          {'id': 3, 'title': 'not a choice: the id is not a string'},
        ],
        'footer': 'Open daily',
        'media': {'kind': 'image', 'url': 'https://cdn.test/menu.jpg'},
        'expects': 'phone',
      },
      'suggestions': ['Yes', '', 'No', 'Maybe', 'Later'],
    };

    test('sender, flow and suggestions', () {
      final message = CnctChatMessage.fromJson(flowMessage);
      expect(message.sender?.kind, CnctSenderKind.ai);
      expect(message.sender?.name, 'Assistant');
      expect(message.sender?.isAssistant, isTrue);
      expect(message.drawsAsFlow, isTrue);
      expect(message.words, 'Would you like to book a visit?');
      expect(message.flow?.choices.map((choice) => choice.id), ['c1', 'c2']);
      expect(message.flow?.choices.last.description, 'Someone from the team');
      expect(message.flow?.footer, 'Open daily');
      expect(message.flow?.media?.kind, CnctAttachmentKind.image);
      expect(message.flow?.expects, CnctFlowExpects.phone);
      // Up to three, and never an empty one.
      expect(message.suggestions, ['Yes', 'No', 'Maybe']);
    });

    test('a flow without its own words falls back to the body', () {
      final message = CnctChatMessage.fromJson({
        ...flowMessage,
        'flow': {
          'choices': [
            {'id': 'c1', 'title': 'Book a visit'},
          ],
        },
      });
      expect(message.drawsAsFlow, isFalse);
      expect(message.words, startsWith('1. Book a visit'));
    });

    test('flow media is only ever an http(s) address', () {
      final message = CnctChatMessage.fromJson({
        ...flowMessage,
        'flow': {
          'text': 'Look',
          'media': {'kind': 'image', 'url': 'javascript:alert(1)'},
        },
      });
      expect(message.flow?.media, isNull);
    });

    test('a quote, and an operator signed by first name', () {
      final message = CnctChatMessage.fromJson({
        'id': 'm11',
        'speaker': 'OPERATOR',
        'body': 'Yes, that one.',
        'createdAt': '2026-09-08T10:00:00.000Z',
        'sender': {'kind': 'person', 'name': 'Sara', 'avatar': 'woman-curly'},
        'replyTo': {'messageId': 'm9', 'mine': true, 'attachmentKind': 'IMAGE'},
      });
      expect(message.sender?.name, 'Sara');
      expect(message.sender?.kind, CnctSenderKind.person);
      expect(message.replyTo?.mine, isTrue);
      expect(message.replyTo?.excerpt, isNull);
      expect(message.replyTo?.attachmentKind, CnctAttachmentKind.image);
      expect(message.type, CnctMessageType.text);
    });

    test('an unknown type renders as its body', () {
      final message = CnctChatMessage.fromJson({
        'id': 'm12',
        'speaker': 'AI',
        'type': 'CAROUSEL',
        'body': 'Three things you might like.',
        'createdAt': '2026-09-08T10:00:00.000Z',
      });
      expect(message.type, CnctMessageType.other);
      expect(message.words, 'Three things you might like.');
    });
  });

  group('what the composer offers', () {
    CnctChatState live(List<Map<String, dynamic>> messages) => CnctChatState(
          status: CnctChatStatus.live,
          conversation: CnctChatConversation(
            id: 'c',
            status: CnctConversationStatus.open,
            startedAt: DateTime.utc(2026, 9, 8),
            withPerson: false,
          ),
          messages: messages.map(CnctChatMessage.fromJson).toList(),
        );

    Map<String, dynamic> said(String speaker, String body,
            {Map<String, dynamic>? flow, List<String>? suggestions, int minute = 0}) =>
        {
          'id': '$speaker$minute',
          'speaker': speaker,
          'body': body,
          'createdAt': '2026-09-08T10:${'$minute'.padLeft(2, '0')}:00.000Z',
          if (flow != null) 'flow': flow,
          if (suggestions != null) 'suggestions': suggestions,
        };

    final choices = {
      'text': 'Pick one',
      'choices': [
        {'id': 'c1', 'title': 'Book a visit'},
      ],
    };

    test('a flow waits only while it is the last thing said', () {
      expect(live([said('AI', 'Pick one', flow: choices)]).awaiting?.choices, hasLength(1));
      expect(
        live([said('AI', 'Pick one', flow: choices), said('CALLER', 'Hm', minute: 1)]).awaiting,
        isNull,
      );
      expect(
        live([said('AI', 'Pick one', flow: choices)])
            .copyWith(status: CnctChatStatus.ended)
            .awaiting,
        isNull,
      );
    });

    test('suggestions come from the assistant’s trailing messages, and never beside choices', () {
      expect(
        live([
          said('AI', 'We open at two.', suggestions: ['Book', 'Thanks']),
          said('AI', '(a picture)', minute: 1),
        ]).suggestions,
        ['Book', 'Thanks'],
      );
      expect(
        live([
          said('AI', 'We open at two.', suggestions: ['Book']),
          said('OPERATOR', 'Hi, Sara here', minute: 1),
        ]).suggestions,
        isEmpty,
      );
      expect(
        live([
          said('AI', 'Pick one', flow: {...choices}, suggestions: ['Book']),
        ]).suggestions,
        isEmpty,
      );
    });

    test('the newest reply is the one a read receipt is about', () {
      final state = live([
        said('AI', 'Hello'),
        said('OPERATOR', 'Sara here', minute: 1),
        said('CALLER', 'Hi Sara', minute: 2),
      ]);
      expect(state.lastReply?.id, 'OPERATOR1');
    });
  });
}
