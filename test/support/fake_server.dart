import 'dart:async';
import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_socket.dart';

const publicKey = 'inbox-public-key';

Map<String, dynamic> messageJson({
  String id = 'msg_1',
  String speaker = 'AI',
  String type = 'TEXT',
  String body = 'Hello',
  String createdAt = '2026-09-08T10:00:00.000Z',
  String? clientKey,
  Map<String, dynamic>? data,
  Map<String, dynamic>? sender,
  Map<String, dynamic>? flow,
  List<String>? suggestions,
  List<Map<String, dynamic>> attachments = const [],
}) =>
    {
      'id': id,
      'speaker': speaker,
      'type': type,
      'body': body,
      'createdAt': createdAt,
      'clientKey': clientKey,
      if (data != null) 'data': data,
      if (sender != null) 'sender': sender,
      if (flow != null) 'flow': flow,
      if (suggestions != null) 'suggestions': suggestions,
      'attachments': attachments,
    };

Map<String, dynamic> conversationJson({String status = 'OPEN', bool ratable = false}) => {
      'id': 'conv_1',
      'status': status,
      'startedAt': '2026-09-08T09:59:00.000Z',
      'withPerson': false,
      'ratable': ratable,
    };

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// The visitor half of the platform, as far as these tests are concerned: every route the hosted
/// widget calls, answering from [routes] first so a test can change one answer and keep the rest.
class FakeServer {
  FakeServer({Map<String, FutureOr<http.Response> Function(http.Request request)>? routes})
      : routes = routes ?? {};

  final Map<String, FutureOr<http.Response> Function(http.Request request)> routes;
  final List<http.Request> seen = [];

  /// The socket the client opened last. A reconnect — after `identify`, say — opens a new one, as a
  /// real client does.
  FakeSocket socket = FakeSocket();
  final List<FakeSocket> sockets = [];

  /// What `POST /messages` stores, so the client's own clientKey comes back on it.
  Map<String, dynamic> stored(http.Request request, {String id = 'msg_stored'}) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    return messageJson(
      id: id,
      speaker: 'CALLER',
      body: body['body'] as String? ?? '',
      clientKey: body['clientKey'] as String?,
      createdAt: '2026-09-08T10:05:00.000Z',
    );
  }

  late final MockClient httpClient = MockClient((request) async {
    seen.add(request);
    final key = '${request.method} ${request.url.path}';
    final override = routes[key];
    if (override != null) return override(request);
    switch (key) {
      case 'GET /api/chat/public/$publicKey':
        return json({
          'business': 'Al Waha',
          'inbox': 'Website',
          'isActive': true,
          'greeting': 'Hello — how can we help?',
          'requirePhone': false,
        });
      case 'POST /api/chat/public/$publicKey/session':
      case 'GET /api/chat/public/session':
        return json({
          // A token is minted by a start; a resume reads the session behind the token it was sent.
          if (request.method == 'POST') 'token': 'visitor-token-1',
          'visitor': {'displayName': 'Layla', 'anonymous': false},
          'conversation': conversationJson(),
          'messages': [messageJson(body: 'Hello — how can we help?')],
        });
      case 'POST /api/chat/public/messages':
        return json(stored(request));
      case 'POST /api/chat/public/close':
        return json({'ok': true});
      case 'GET /api/chat/public/conversations/conv_1':
        return json({
          'conversation': conversationJson(status: 'CLOSED', ratable: true),
          'messages': [messageJson(body: 'Hello — how can we help?')],
        });
    }
    return json({'error': 'not found'}, 404);
  });

  CnctChatClient client({CnctTokenStore? store, CnctTimeZoneResolver? timeZone}) {
    final config = CnctConfig(baseUrl: 'https://cnct.test');
    return CnctChatClient(
      config: config,
      credentials: CnctChatPublicKey(publicKey),
      transport: CnctTransport(config: config, httpClient: httpClient),
      tokenStore: store ?? CnctTokenStore.memory(),
      socketFactory: (_) {
        if (sockets.isNotEmpty) socket = FakeSocket();
        sockets.add(socket);
        return socket;
      },
      timeZone: timeZone,
    );
  }

  Iterable<http.Request> to(String method, String path) =>
      seen.where((request) => request.method == method && request.url.path == path);

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;
}
