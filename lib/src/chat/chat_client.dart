import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../credentials.dart';
import '../exception.dart';
import '../token_store.dart';
import '../transport.dart';
import 'chat_events.dart';
import 'chat_models.dart';
import 'chat_state.dart';

/// How a WebSocket gets made. Swappable so tests can drive a fake one without a server.
typedef CnctSocketFactory = WebSocketChannel Function(Uri url);

/// Live chat with a CNCT inbox, from Flutter or plain Dart.
///
/// **Headless on purpose.** There is no widget in here, not one, and that is the reason to reach for
/// this rather than an embedded web view: a business building their own app has a design system
/// already, and shipping them a bubble to restyle answers a question they did not ask. This ships
/// state and events; the interface is yours.
///
/// Three properties are load-bearing and you get them without having to know:
///
/// **A reconnect reloads.** The platform's fan-out replays nothing after a drop — deliberately — so
/// this client refetches the whole transcript on every reconnect rather than splicing a gap it
/// cannot measure. A UI that renders [state] is always rendering the truth.
///
/// **A send is idempotent.** Every message carries a `clientKey` that is unique per conversation on
/// the server, so a frame replayed across a reconnect returns the row it already wrote instead of
/// writing a second one. That is what makes [send] safe to reject on a timeout and [retry] safe to
/// call.
///
/// **It degrades rather than breaks.** The server announces what it accepts on the handshake. Sends
/// go over the socket where that is offered and fall back to HTTP where it is not — which covers
/// both an older server and the ordinary case of the socket being between connections.
///
/// ```dart
/// final chat = CnctChatClient(
///   config: CnctConfig(baseUrl: CnctHosts.development),
///   credentials: CnctChatPublicKey('the-inbox-public-key'),
/// );
/// chat.states.listen(render);
/// final inbox = await chat.boot();
/// if (inbox.isActive) {
///   await chat.start(displayName: 'Layla');
///   await chat.send('Do you open on Fridays?');
/// }
/// ```
class CnctChatClient {
  CnctChatClient({
    required CnctConfig config,
    required CnctChatPublicKey credentials,
    CnctTokenStore? tokenStore,
    String? storageKey,
    CnctTransport? transport,
    CnctSocketFactory? socketFactory,
  })  : _config = config,
        _publicKey = credentials.publicKey,
        _store = tokenStore ?? CnctTokenStore.memory(),
        _storageKey = storageKey ?? 'cnct_chat_${credentials.publicKey}',
        _transport = transport ?? CnctTransport(config: config),
        _socketFactory = socketFactory ?? WebSocketChannel.connect;

  final CnctConfig _config;
  final String _publicKey;
  final CnctTokenStore _store;
  final String _storageKey;
  final CnctTransport _transport;
  final CnctSocketFactory _socketFactory;

  final _states = StreamController<CnctChatState>.broadcast();
  final _events = StreamController<CnctChatEvent>.broadcast();
  final _random = Random();

  /// Frame id → the send waiting for its `ack`.
  final Map<String, Completer<CnctChatMessage>> _awaiting = {};
  final Map<String, Timer> _awaitingTimers = {};

  CnctChatState _state = const CnctChatState();
  String? _token;
  bool _tokenLoaded = false;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  Timer? _typingClearTimer;
  DateTime? _lastTypingSentAt;
  int _reconnectAttempt = 0;
  bool _socketSendSupported = false;
  bool _closedByUs = false;
  bool _disposed = false;

  /// The current snapshot. Never null, never half-applied.
  CnctChatState get state => _state;

  /// Every state change, including the first. Broadcast: listen from as many widgets as you like.
  Stream<CnctChatState> get states => _states.stream;

  /// Things that happened, for the parts of a UI that act rather than render.
  Stream<CnctChatEvent> get events => _events.stream;

  /// True when a session token is held — the visitor has been here before and [resume] will work.
  bool get hasSession => _token != null;

  // ── The front door ────────────────────────────────────────────────────────────────────────────

  /// What this inbox says before anybody has typed: the greeting, whether it is switched on, and
  /// whether it wants a phone number first.
  ///
  /// Readable without a session, and worth calling before you draw anything — an inbox with
  /// [CnctChatInbox.isActive] false will refuse a session, and saying so up front is better than
  /// letting somebody type into a composer that cannot deliver.
  Future<CnctChatInbox> boot() async {
    final json = await _transport.get('/api/chat/public/${Uri.encodeComponent(_publicKey)}');
    final inbox = CnctChatInbox.fromJson(_asMap(json));
    _patch(_state.copyWith(inbox: inbox, clearError: true));
    return inbox;
  }

  /// Begin, or come back as the same person.
  ///
  /// Sending a stored token reuses that visitor rather than minting a stranger, so somebody who
  /// chatted last week is still attached to the contact record the business has for them.
  ///
  /// Pass [phone] whenever you know it. A visitor is anonymous until they volunteer a number: if
  /// your app has already signed this person in, passing the number you hold is the difference
  /// between a thread that joins their history and one that starts a second record for them.
  Future<void> start({String? displayName, String? phone}) async {
    await _loadToken();
    final json = await _transport.post(
      '/api/chat/public/${Uri.encodeComponent(_publicKey)}/session',
      body: {
        if (displayName != null && displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
      headers: _tokenHeader(),
    );
    await _adoptSession(_asMap(json));
    connect();
  }

  /// Pick up where a restart left off. Resolves to false when there is no session to pick up —
  /// which is not an error, just a first-time visitor.
  ///
  /// A refused token is cleared here rather than thrown: the visitor's thirty days ran out or the
  /// business closed the conversation, and neither is something an app can act on beyond going back
  /// to its pre-chat screen.
  Future<bool> resume() async {
    await _loadToken();
    if (_token == null) return false;
    try {
      final json = await _transport.get('/api/chat/public/session', headers: _tokenHeader());
      final data = _asMap(json);
      await _adoptSession(data);
      if (_state.conversation?.status == CnctConversationStatus.closed) {
        _patch(_state.copyWith(status: CnctChatStatus.ended));
      } else {
        connect();
      }
      return true;
    } on CnctException catch (error) {
      if (error.isUnauthenticated) {
        await _forgetSession();
        return false;
      }
      rethrow;
    }
  }

  // ── Saying something ──────────────────────────────────────────────────────────────────────────

  /// Say something. Resolves once the server has it.
  ///
  /// The optimistic bubble goes into [state] immediately and is replaced in place when the real row
  /// arrives — matched on `clientKey`, which is also the frame id and also the server's idempotency
  /// key, so the three can never disagree about which message this is.
  ///
  /// On failure the bubble stays, marked [CnctChatMessage.failed], and the exception is thrown. Do
  /// not clear it: the words somebody typed vanishing is worse than a retry button.
  Future<CnctChatMessage> send(String body, {String? clientKey}) async {
    await _loadToken();
    if (_token == null) {
      throw CnctException('Start a conversation first.', code: CnctErrorCode.noSession);
    }
    final text = body.trim();
    if (text.isEmpty) {
      throw CnctException('Nothing to send.', code: CnctErrorCode.empty);
    }
    final key = clientKey ?? _uid();

    final existing = _state.messages.indexWhere((message) => message.clientKey == key);
    if (existing >= 0) {
      final messages = _state.messages.toList();
      messages[existing] = messages[existing].copyWith(pending: true, failed: false);
      _patch(_state.copyWith(messages: messages));
    } else {
      _patch(_state.copyWith(
        messages: [..._state.messages, CnctChatMessage.optimistic(clientKey: key, body: text)],
      ));
    }

    try {
      if (_socketSendSupported && _socket != null) {
        return await _sendOverSocket(key, text);
      }
      // The fallback, and a real path rather than a formality: it runs against a server that
      // predates socket sends, and whenever the socket happens to be between connections. Same
      // endpoint, same idempotency key.
      final json = await _transport.post(
        '/api/chat/public/messages',
        body: {'body': text, 'clientKey': key},
        headers: _tokenHeader(),
      );
      final message = CnctChatMessage.fromJson(_asMap(json));
      _absorb(message);
      return message;
    } on CnctException catch (error) {
      _markFailed(key);
      _fail(error.status == 409
          ? CnctException(error.message,
              code: CnctErrorCode.conversationClosed, status: error.status)
          : error);
      rethrow;
    }
  }

  /// Re-send a message that failed. The same `clientKey`, so the server cannot write it twice.
  Future<CnctChatMessage> retry(String clientKey) {
    for (final message in _state.messages) {
      if (message.clientKey == clientKey) return send(message.body, clientKey: clientKey);
    }
    throw CnctException('No message with that key.', code: CnctErrorCode.notFound);
  }

  /// Tell the other side somebody is typing. Throttled to one frame every three seconds here, and
  /// again on the server — call it on every keystroke without thinking about it.
  void typing() {
    final now = DateTime.now();
    if (_lastTypingSentAt != null && now.difference(_lastTypingSentAt!).inSeconds < 3) return;
    if (_socket == null) return;
    _lastTypingSentAt = now;
    _say({'type': 'typing'});
  }

  /// The visitor ends it. Their own conversation, so there is nothing to identify.
  Future<void> end() async {
    await _loadToken();
    if (_token == null) return;
    await _transport.post('/api/chat/public/close', headers: _tokenHeader());
    _closedByUs = true;
    _patch(_state.copyWith(status: CnctChatStatus.ended));
    _teardownSocket();
  }

  // ── Files ─────────────────────────────────────────────────────────────────────────────────────

  /// The bytes of a file an operator sent. Scoped to this visitor's own conversation by the server;
  /// an id from anywhere else is a 404 rather than a refusal, so a stranger learns nothing.
  Future<List<int>> downloadAttachment(String attachmentId) async {
    await _loadToken();
    if (_token == null) {
      throw CnctException('Start a conversation first.', code: CnctErrorCode.noSession);
    }
    return _transport.bytes(
      '/api/chat/public/attachments/${Uri.encodeComponent(attachmentId)}',
      headers: _tokenHeader(),
    );
  }

  /// The URL an attachment lives at, and the headers needed to fetch it.
  ///
  /// Together, these are what a custom image loader wants — `Image.network` cannot carry the session
  /// header on its own, so this returns both rather than a URL that would 401 in a widget somebody
  /// spent an afternoon debugging.
  ({Uri url, Map<String, String> headers}) attachmentRequest(String attachmentId) => (
        url: _config.resolve('/api/chat/public/attachments/${Uri.encodeComponent(attachmentId)}'),
        headers: {..._config.headers, ..._tokenHeader()},
      );

  // ── The socket ────────────────────────────────────────────────────────────────────────────────

  /// Open the socket. Called for you by [start] and [resume]; public for an app that disconnects
  /// while backgrounded and wants to come back.
  void connect() {
    if (_disposed || _token == null || _socket != null) return;
    _closedByUs = false;
    _patch(_state.copyWith(
      status:
          _state.status == CnctChatStatus.live ? CnctChatStatus.live : CnctChatStatus.connecting,
    ));

    final WebSocketChannel channel;
    try {
      channel = _socketFactory(_config.socketBaseUrl.replace(
        path: '${_config.socketBaseUrl.path}/ws/chat',
      ));
    } catch (error) {
      _config.logger?.call(CnctLogLevel.warning, 'Could not open the chat socket', error);
      _scheduleReconnect();
      return;
    }
    _socket = channel;

    _socketSubscription = channel.stream.listen(
      _handleFrame,
      onError: (Object error) {
        _config.logger?.call(CnctLogLevel.warning, 'Chat socket error', error);
      },
      onDone: () => _handleSocketClosed(channel.closeCode),
      cancelOnError: false,
    );

    // The handshake. Five seconds to authenticate or the server closes the connection, so this goes
    // out the moment the channel exists rather than after any await.
    _say({'type': 'auth', 'token': _token});
    _startKeepAlive();
  }

  /// Close the socket and stop reconnecting. The session survives — [resume] picks it up again.
  void disconnect() {
    _closedByUs = true;
    _teardownSocket();
    if (_state.status != CnctChatStatus.ended) {
      _patch(_state.copyWith(status: CnctChatStatus.offline));
    }
  }

  /// Release everything. Call it from `dispose()`; the client is unusable afterwards.
  void dispose() {
    _disposed = true;
    disconnect();
    _transport.close();
    _states.close();
    _events.close();
  }

  // ── Internals ─────────────────────────────────────────────────────────────────────────────────

  void _handleFrame(dynamic raw) {
    final Map<String, dynamic> frame;
    try {
      frame = _asMap(jsonDecode(raw is String ? raw : utf8.decode((raw as List).cast<int>())));
    } catch (_) {
      return;
    }

    switch ('${frame['type']}') {
      case 'authenticated':
        _reconnectAttempt = 0;
        final accepts =
            (frame['accepts'] as List<Object?>?)?.map((item) => '$item').toList() ?? const [];
        _socketSendSupported = accepts.contains('send');
        _patch(_state.copyWith(status: CnctChatStatus.live, clearError: true));
        // **The reload that makes this client safe to render directly.** Pub/sub replays nothing,
        // so anything said while the socket was down is missing and there is no way to know how
        // much. Refetching is the only answer that cannot be subtly wrong.
        unawaited(resume().catchError((Object _) => false));
        _emit(const CnctChatConnected());
      case 'pong':
        return;
      case 'ack':
        final id = frame['id'] as String?;
        final payload = frame['message'];
        final message = payload is Map ? CnctChatMessage.fromJson(_asMap(payload)) : null;
        if (message != null) _absorb(message);
        if (id != null) {
          final waiting = _awaiting.remove(id);
          _awaitingTimers.remove(id)?.cancel();
          if (message != null) {
            waiting?.complete(message);
          } else {
            waiting?.completeError(
              CnctException('The server acknowledged without a message.',
                  code: CnctErrorCode.badResponse),
            );
          }
        }
      case 'error':
        final id = frame['id'] as String?;
        final error = CnctException(
          frame['error'] as String? ?? 'That did not work.',
          code: frame['code'] as String? ?? CnctErrorCode.requestFailed,
        );
        if (id != null) {
          final waiting = _awaiting.remove(id);
          _awaitingTimers.remove(id)?.cancel();
          // Leave the optimistic bubble in place but mark it, so a UI can offer a retry rather than
          // making the words the person typed disappear.
          _markFailed(id);
          waiting?.completeError(error);
        }
        _fail(error);
      case 'chat.message':
        final payload = (frame['payload'] as Map<Object?, Object?>?)?['message'];
        if (payload is Map) {
          final message = CnctChatMessage.fromJson(_asMap(payload));
          _absorb(message);
          _emit(CnctChatMessageReceived(message));
        }
      case 'chat.typing':
        _patch(_state.copyWith(theyAreTyping: true));
        _typingClearTimer?.cancel();
        _typingClearTimer = Timer(const Duration(seconds: 4), () {
          if (!_disposed) _patch(_state.copyWith(theyAreTyping: false));
        });
        _emit(const CnctChatTypingReceived());
      case 'chat.conversation.updated':
        final payload = (frame['payload'] as Map<Object?, Object?>?)?['conversation'];
        if (payload is Map) {
          final conversation = CnctChatConversation.fromJson(_asMap(payload));
          _patch(_state.copyWith(conversation: conversation));
          _emit(CnctChatConversationUpdated(conversation));
        }
      case 'chat.closed':
        _closedByUs = true;
        _patch(_state.copyWith(status: CnctChatStatus.ended));
        _emit(const CnctChatClosed());
        _teardownSocket();
      default:
        // An unknown frame is a newer server talking, not an error. Ignored on purpose.
        return;
    }
  }

  void _handleSocketClosed(int? closeCode) {
    _stopKeepAlive();
    _socket = null;
    _socketSendSupported = false;
    _failAllAwaiting(
      CnctException('The connection dropped before that was sent.', code: CnctErrorCode.offline),
    );

    // 1008 is what the server closes with when the token did not resolve. Reconnecting would loop
    // against a credential that will never work, so this is the one close that ends things rather
    // than backing off.
    if (closeCode == 1008) {
      unawaited(_forgetSession());
      _emit(const CnctChatUnauthenticated());
      return;
    }
    if (_state.status != CnctChatStatus.ended) {
      _patch(_state.copyWith(status: CnctChatStatus.offline));
    }
    _emit(const CnctChatDisconnected());
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closedByUs || _disposed || _reconnectTimer != null) return;
    // Exponential with a ceiling and jitter — a thousand phones recovering from the same blip
    // should not all arrive in the same millisecond.
    final base = min(30000, 500 * pow(2, _reconnectAttempt).toInt());
    final wait = (base * (0.7 + _random.nextDouble() * 0.6)).round();
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(milliseconds: wait), () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _startKeepAlive() {
    _stopKeepAlive();
    // Quiet connections get closed by proxies long before they get closed by anybody's intent.
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) => _say({'type': 'ping'}));
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  void _teardownSocket() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _typingClearTimer?.cancel();
    _typingClearTimer = null;
    _stopKeepAlive();
    _failAllAwaiting(CnctException('Disconnected.', code: CnctErrorCode.offline));
    unawaited(_socketSubscription?.cancel());
    _socketSubscription = null;
    final socket = _socket;
    _socket = null;
    _socketSendSupported = false;
    unawaited(socket?.sink.close(1000, 'Client closed'));
  }

  Future<CnctChatMessage> _sendOverSocket(String key, String text) {
    final completer = Completer<CnctChatMessage>();
    _awaiting[key] = completer;
    _awaitingTimers[key] = Timer(_config.sendTimeout, () {
      _awaiting.remove(key);
      _awaitingTimers.remove(key);
      _markFailed(key);
      // Safe to say "retry": the clientKey means a second attempt cannot double-post.
      if (!completer.isCompleted) {
        completer.completeError(
          CnctException('That message has not been acknowledged yet.', code: CnctErrorCode.timeout),
        );
      }
    });
    _say({'type': 'send', 'id': key, 'body': text, 'clientKey': key});
    return completer.future;
  }

  void _say(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.sink.add(jsonEncode(frame));
    } catch (error) {
      _config.logger?.call(CnctLogLevel.warning, 'Could not write to the chat socket', error);
    }
  }

  void _failAllAwaiting(CnctException error) {
    for (final entry in _awaiting.entries) {
      _awaitingTimers.remove(entry.key)?.cancel();
      if (!entry.value.isCompleted) entry.value.completeError(error);
    }
    _awaiting.clear();
    for (final timer in _awaitingTimers.values) {
      timer.cancel();
    }
    _awaitingTimers.clear();
  }

  /// Merge a server message in, replacing the optimistic one it answers.
  void _absorb(CnctChatMessage message) {
    final messages = _state.messages.toList();
    final at = message.clientKey != null
        ? messages.indexWhere((candidate) => candidate.clientKey == message.clientKey)
        : messages.indexWhere((candidate) => candidate.id == message.id);
    if (at >= 0) {
      messages[at] = message;
    } else if (!messages.any((candidate) => candidate.id == message.id)) {
      messages.add(message);
    }
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _patch(_state.copyWith(messages: messages, clearError: true));
  }

  void _markFailed(String clientKey) {
    final messages = _state.messages
        .map((message) => message.clientKey == clientKey
            ? message.copyWith(pending: false, failed: true)
            : message)
        .toList(growable: false);
    _patch(_state.copyWith(messages: messages));
  }

  Future<void> _adoptSession(Map<String, dynamic> data) async {
    final token = data['token'];
    if (token is String && token.isNotEmpty) {
      _token = token;
      _tokenLoaded = true;
      await _store.write(_storageKey, token);
    }
    final visitor = data['visitor'];
    final conversation = data['conversation'];
    _patch(_state.copyWith(
      visitor: visitor is Map ? CnctChatVisitor.fromJson(_asMap(visitor)) : null,
      conversation:
          conversation is Map ? CnctChatConversation.fromJson(_asMap(conversation)) : null,
      messages: (data['messages'] as List<Object?>?)
              ?.whereType<Map<Object?, Object?>>()
              .map((item) => CnctChatMessage.fromJson(_asMap(item)))
              .toList(growable: false) ??
          _state.messages,
      clearError: true,
    ));
  }

  Future<void> _forgetSession() async {
    _token = null;
    _tokenLoaded = true;
    await _store.clear(_storageKey);
    _teardownSocket();
    _patch(const CnctChatState().copyWith(inbox: _state.inbox));
  }

  Future<void> _loadToken() async {
    if (_tokenLoaded) return;
    _token = await _store.read(_storageKey);
    _tokenLoaded = true;
  }

  /// Never `Authorization`. The platform's rate limiter keys on `ip + authorization`, so a visitor
  /// who sent that header would be minting themselves a fresh budget by inventing one.
  Map<String, String> _tokenHeader() => _token == null ? const {} : {'x-chat-token': _token!};

  void _patch(CnctChatState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _fail(CnctException error) {
    _patch(_state.copyWith(error: error));
    _emit(CnctChatErrored(error));
  }

  void _emit(CnctChatEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  String _uid() {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = List.generate(10, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
    return 'k$stamp$noise';
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    throw CnctException(
      'Expected an object from the server and got ${value.runtimeType}.',
      code: CnctErrorCode.badResponse,
    );
  }
}
