/// The fixture conversation: CNCT's scripted chat, behind a fake transport and a fake socket, so the
/// chat UI can be shown, tested and screenshotted with no key and no network.
///
/// ```dart
/// final fixture = CnctChatFixture(language: 'ar');
/// await fixture.prepare();
/// runApp(MaterialApp(home: CnctChat(client: fixture.client)));
/// ```
///
/// Every CNCT SDK renders this same conversation for its screenshots: a greeting, a question, the
/// assistant's answer with two choices, a photo, an operator's invoice, a line mixing Arabic and a
/// phone number, a message that failed to send, and the team typing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'src/fixture/photo.dart';

export 'src/fixture/photo.dart' show fixturePdf, fixturePhoto;

/// The scripted conversation, in English or Arabic.
class CnctChatFixture {
  CnctChatFixture({
    this.language = 'en',
    this.interactive = false,
    this.stalledUploads = const {},
    DateTime? now,
  }) : _now = now ?? DateTime.now() {
    final config = CnctConfig(baseUrl: 'https://fixture.cnct.invalid');
    client = CnctChatClient(
      config: config,
      credentials: CnctChatPublicKey(publicKey),
      transport: CnctTransport(config: config, httpClient: MockClient.streaming(_handle)),
      tokenStore: _store,
      socketFactory: (_) => _socket = _FixtureSocket(this),
      timeZone: () => 'Asia/Bahrain',
    );
  }

  static const publicKey = 'fixture';

  /// `en` or `ar`: the language the business and the visitor write in.
  final String language;

  /// When true, the fixture answers what the visitor sends — for an example app to click through.
  /// Off for screenshots, which must not change while they are taken.
  final bool interactive;

  /// File names whose upload stops part-way, at the fraction given, and never finishes — the
  /// "mid-upload" chip of the screenshots.
  final Map<String, double> stalledUploads;

  final DateTime _now;
  late final CnctChatClient client;

  /// Every request the fixture answered, as `METHOD /path`, in order — for a test that checks what
  /// the chat asked for and when.
  final List<String> calls = [];
  final _store = CnctTokenStore.memory();
  _FixtureSocket? _socket;
  bool _closed = false;
  int _sent = 0;

  /// Files stored by the fake upload endpoint, by id, so a message sent with them carries them back.
  final Map<String, Map<String, Object?>> _stored = {};
  late final Uint8List photo = fixturePhoto();

  bool get _ar => language == 'ar';
  String _say(String en, String ar) => _ar ? ar : en;

  /// The words of the message that fails, so a test can find it.
  String get failedText => _say('Can I pay by card?', 'هل يمكنني الدفع بالبطاقة؟');

  /// Put the conversation where the screenshots show it: a stored session that resumes into
  /// messages 1–6, and message 7 sent and failed.
  Future<void> prepare() async {
    await _store.write('cnct_chat_$publicKey', 'fixture-visitor-token');
    await client.resume();
    try {
      await client.send(failedText);
    } on CnctException {
      // Meant to fail: it is the bubble with the retry button.
    }
  }

  void dispose() => client.dispose();

  // ── The conversation ──────────────────────────────────────────────────────────────────────────

  String _at(int minute) => _now.subtract(Duration(minutes: 20 - minute)).toUtc().toIso8601String();

  Map<String, Object?> get _inbox => {
        'business': _say('Bayside Café', 'مقهى البحر'),
        'inbox': 'App',
        'isActive': true,
        'greeting': _say('Hello. How can we help?', 'مرحبًا. كيف يمكننا مساعدتك؟'),
        'requirePhone': false,
        'widget': {
          'brand': {
            'color': '#b52d93',
            'appearance': 'auto',
            'avatarUrl': null,
            'language': 'auto',
            'showBranding': true,
          },
          'chat': {
            'allowAttachments': true,
            'allowEmoji': true,
            'allowEndConversation': true,
            'start': 'details',
            'askForRating': true,
          },
        },
        'team': [
          {'name': _say('Sara', 'سارة'), 'avatar': 'woman'},
        ],
        'availability': {'open': true, 'opensAt': null, 'assistant': true, 'replyMinutes': 4},
      };

  Map<String, Object?> get _sara =>
      {'kind': 'person', 'name': _say('Sara', 'سارة'), 'avatar': 'woman'};

  Map<String, Object?> _conversation({bool closed = false}) => {
        'id': 'conv_fixture',
        'status': closed ? 'CLOSED' : 'OPEN',
        'startedAt': _at(0),
        if (closed) 'closedAt': _now.toUtc().toIso8601String(),
        'withPerson': true,
        'assignee': null,
        'ratable': closed,
      };

  List<Map<String, Object?>> get _messages => [
        {
          'id': 'm1',
          'speaker': 'SYSTEM',
          'type': 'TEXT',
          'body': _say('Hello. How can we help?', 'مرحبًا. كيف يمكننا مساعدتك؟'),
          'createdAt': _at(0),
        },
        {
          'id': 'm2',
          'speaker': 'CALLER',
          'type': 'TEXT',
          'body': _say('Do you open on Fridays?', 'هل تفتحون يوم الجمعة؟'),
          'createdAt': _at(1),
          'clientKey': 'k2',
        },
        {
          'id': 'm3',
          'speaker': 'AI',
          'type': 'TEXT',
          'body': _say(
            'Yes, from 2pm to 10pm. Would you like to book a visit?\n1. Book a visit\n'
                '2. Talk to a person\nReply with the number.',
            'نعم، من الساعة 2 ظهرًا حتى 10 مساءً. هل تود حجز زيارة؟\n1. احجز زيارة\n'
                '2. تحدث مع موظف\nأرسل الرقم.',
          ),
          'createdAt': _at(2),
          'sender': {'kind': 'ai', 'name': 'Assistant', 'mascot': 'owl'},
          'flow': {
            'text': _say(
              'Yes, from 2pm to 10pm. Would you like to book a visit?',
              'نعم، من الساعة 2 ظهرًا حتى 10 مساءً. هل تود حجز زيارة؟',
            ),
            'layout': 'buttons',
            'choices': [
              {'id': 'book', 'title': _say('Book a visit', 'احجز زيارة')},
              {'id': 'person', 'title': _say('Talk to a person', 'تحدث مع موظف')},
            ],
          },
        },
        {
          'id': 'm4',
          'speaker': 'CALLER',
          'type': 'TEXT',
          'body': '',
          'createdAt': _at(4),
          'clientKey': 'k4',
          'attachments': [
            {
              'id': 'att_photo',
              'kind': 'IMAGE',
              'mimeType': 'image/jpeg',
              'filename': 'photo.jpg',
              'bytes': 1258291,
            },
          ],
        },
        {
          'id': 'm5',
          'speaker': 'OPERATOR',
          'type': 'TEXT',
          'body': _say('Thanks, here is your invoice.', 'شكرًا، هذه فاتورتك.'),
          'createdAt': _at(6),
          'sender': _sara,
          'attachments': [
            {
              'id': 'att_invoice',
              'kind': 'DOCUMENT',
              'mimeType': 'application/pdf',
              'filename': 'invoice.pdf',
              'bytes': 225280,
            },
          ],
        },
        {
          'id': 'm6',
          'speaker': 'CALLER',
          'type': 'TEXT',
          'body': _say(
            'Call me on +973 3311 2233 please',
            'اتصلوا بي على +973 3311 2233 من فضلك',
          ),
          'createdAt': _at(7),
          'clientKey': 'k6',
        },
      ];

  // ── The fake platform ─────────────────────────────────────────────────────────────────────────

  http.StreamedResponse _json(Object? body, [int status = 200]) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );

  Future<http.StreamedResponse> _handle(http.BaseRequest request, http.ByteStream body) async {
    final route = '${request.method} ${request.url.path}';
    calls.add(route);
    if (route == 'POST /api/chat/public/attachments') return _upload(request, body);
    final text = await body.bytesToString();
    final json =
        text.isEmpty ? const <String, Object?>{} : jsonDecode(text) as Map<String, Object?>;
    switch (route) {
      case 'GET /api/chat/public/$publicKey':
        return _json(_inbox);
      case 'GET /api/chat/public/session':
        return _json({
          'visitor': {'displayName': _say('Layla', 'ليلى'), 'anonymous': false},
          'conversation': _conversation(closed: _closed),
          'messages': _messages,
        });
      case 'POST /api/chat/public/$publicKey/session':
        _closed = false;
        return _json({
          'token': 'fixture-visitor-token',
          'visitor': {'displayName': _say('Layla', 'ليلى'), 'anonymous': false},
          'conversation': {..._conversation(), 'id': 'conv_fixture_2', 'withPerson': false},
          'messages': [_messages.first],
        });
      case 'POST /api/chat/public/messages':
        if (json['body'] == failedText) return _json({'error': 'Service unavailable'}, 503);
        _sent += 1;
        if (interactive) _answerLater();
        return _json({
          'id': 'sent_$_sent',
          'speaker': 'CALLER',
          'type': 'TEXT',
          'body': json['body'],
          'clientKey': json['clientKey'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'attachments': [
            for (final id in (json['attachmentIds'] as List<Object?>? ?? const []))
              if (_stored[id] != null) _stored[id],
          ],
        });
      case 'GET /api/chat/public/attachments/att_photo':
        return http.StreamedResponse(Stream.value(photo), 200);
      case 'GET /api/chat/public/attachments/att_invoice':
        return http.StreamedResponse(Stream.value(fixturePdf), 200);
      case 'POST /api/chat/public/close':
        _closed = true;
        return _json({'ok': true});
      case 'GET /api/chat/public/conversations/conv_fixture':
        return _json({'conversation': _conversation(closed: _closed), 'messages': _messages});
      case 'POST /api/chat/public/conversations/conv_fixture/rating':
        return _json({
          'conversation': {
            ..._conversation(closed: true),
            'rating': {'score': json['score'], 'comment': json['comment']},
          },
        });
      case 'POST /api/chat/public/conversations/conv_fixture/read':
      case 'POST /api/chat/public/conversations/conv_fixture_2/read':
        return http.StreamedResponse(const Stream.empty(), 204);
      case 'POST /api/chat/public/$publicKey/identify':
        return _json({
          'token': 'fixture-signed-in-token',
          'visitor': {
            'displayName': json['name'] ?? 'Layla',
            'anonymous': false,
            'identified': true
          },
        });
      case 'POST /api/chat/public/profile':
        return _json({
          'visitor': {'displayName': json['displayName'], 'anonymous': false},
        });
    }
    return _json({'error': 'Not in the fixture: $route'}, 404);
  }

  /// Stores a file — or, for one named in [stalledUploads], reads it part-way and stops there.
  Future<http.StreamedResponse> _upload(http.BaseRequest request, http.ByteStream body) async {
    final total = request.contentLength ?? 0;
    var read = 0;
    String? filename;
    await for (final chunk in body) {
      read += chunk.length;
      filename ??=
          RegExp('filename="([^"]+)"').firstMatch(latin1.decode(chunk.take(600).toList()))?[1];
      final stop = stalledUploads[filename];
      if (stop != null && total > 0 && read >= total * stop) {
        // The upload stays where it is, mid-ring, for as long as anybody looks.
        await Completer<void>().future;
      }
    }
    final name = filename ?? 'file';
    final type = CnctAttachmentRules.mimeTypeFor(name);
    final attachment = {
      'id': 'att_up_${_stored.length + 1}',
      'kind': CnctAttachmentKind.forMimeType(type).wireName,
      'mimeType': type,
      'filename': name,
      'bytes': read,
    };
    _stored[attachment['id']! as String] = attachment;
    return _json({'attachment': attachment}, 201);
  }

  void _answerLater() {
    Timer(const Duration(milliseconds: 600), () => _socket?.push({'type': 'chat.typing'}));
    Timer(const Duration(milliseconds: 2200), () {
      _socket?.push({
        'type': 'chat.message',
        'payload': {
          'message': {
            'id': 'reply_$_sent',
            'speaker': 'OPERATOR',
            'type': 'TEXT',
            'body': _say(
              'Thanks — this is the fixture conversation, so nobody will reply for real.',
              'شكرًا، هذه محادثة تجريبية ولن يرد عليها أحد فعليًا.',
            ),
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'sender': _sara,
          },
        },
      });
    });
  }
}

/// The socket half: authenticates whatever token it is given, and then says the team is typing.
class _FixtureSocket extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  _FixtureSocket(this._fixture);

  final CnctChatFixture _fixture;
  // Closed by the sink, as a real socket's stream is closed by its connection.
  // ignore: close_sinks
  final _inbound = StreamController<dynamic>();
  int? _closeCode;

  void push(Map<String, Object?> frame) {
    if (!_inbound.isClosed) _inbound.add(jsonEncode(frame));
  }

  void _heard(Object? raw) {
    final frame = jsonDecode('$raw') as Map<String, Object?>;
    if (frame['type'] == 'auth') {
      scheduleMicrotask(() {
        // No `send` in what it accepts: the fixture takes messages over HTTP, where it can refuse
        // the one that fails.
        push({
          'type': 'authenticated',
          'accepts': ['ping', 'typing']
        });
        if (!_fixture._closed) push({'type': 'chat.typing'});
      });
    }
  }

  @override
  Stream<dynamic> get stream => _inbound.stream;

  // The client closes it, as it would a real socket's.
  @override
  // ignore: close_sinks
  late final WebSocketSink sink = _FixtureSink(this);

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();
}

class _FixtureSink implements WebSocketSink {
  _FixtureSink(this._socket);

  final _FixtureSocket _socket;
  final _done = Completer<void>();

  @override
  void add(dynamic event) => _socket._heard(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _socket._closeCode = closeCode;
    if (!_socket._inbound.isClosed) await _socket._inbound.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
