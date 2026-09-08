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
}
