import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../credentials.dart';
import '../exception.dart';
import '../token_store.dart';
import '../transport.dart';
import 'attachments.dart';
import 'chat_events.dart';
import 'chat_models.dart';
import 'chat_state.dart';

/// How a WebSocket gets made. Swappable so tests can drive a fake one without a server.
typedef CnctSocketFactory = WebSocketChannel Function(Uri url);

/// Where the device's IANA time zone comes from — `Asia/Bahrain`, `Europe/London`.
///
/// A callback rather than a lookup this package does itself, because plain Dart cannot answer it:
/// `DateTime.timeZoneName` is an abbreviation ("+03", "AST") that names no zone. A Flutter app asks
/// the platform (`cnct_flutter_ui` does); a server knows its own.
typedef CnctTimeZoneResolver = FutureOr<String?> Function();

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
///   config: CnctConfig(), // https://app.doo.ooo
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
    CnctTimeZoneResolver? timeZone,
  })  : _config = config,
        _publicKey = credentials.publicKey,
        _store = tokenStore ?? CnctTokenStore.memory(),
        _storageKey = storageKey ?? 'cnct_chat_${credentials.publicKey}',
        _transport = transport ?? CnctTransport(config: config),
        _socketFactory = socketFactory ?? WebSocketChannel.connect,
        _timeZone = timeZone;

  final CnctConfig _config;
  final String _publicKey;
  final CnctTokenStore _store;
  final String _storageKey;
  final CnctTransport _transport;
  final CnctSocketFactory _socketFactory;
  final CnctTimeZoneResolver? _timeZone;

  /// The inbox's public key, for a UI that was handed a client and needs to say which inbox it is.
  String get publicKey => _publicKey;

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

  /// Per conversation, the newest reply already reported read, so each is reported once.
  final Map<String, String> _reported = {};

  /// Files already fetched, newest use last, within [_fileBudget] bytes. The thread is redrawn on
  /// every message, and without this every photo in it would be downloaded again each time.
  final Map<String, Uint8List> _files = {};
  final Map<String, Future<Uint8List>> _fetching = {};
  int _fileBytes = 0;
  static const _fileBudget = 64 * 1024 * 1024;

  /// The current snapshot. Never null, never half-applied.
  CnctChatState get state => _state;

  /// Every state change, including the first. Broadcast: listen from as many widgets as you like.
  Stream<CnctChatState> get states => _states.stream;

  /// Things that happened, for the parts of a UI that act rather than render.
  Stream<CnctChatEvent> get events => _events.stream;

  /// True when a session token is held — the visitor has been here before and [resume] will work.
  bool get hasSession => _token != null;

  // ── The front door ────────────────────────────────────────────────────────────────────────────

  /// What this inbox says before anybody has typed: the greeting, whether it is switched on, how
  /// the business branded it, who will answer and whether they are in.
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
  /// chatted last week is still attached to the contact record the business has for them. After a
  /// conversation has closed, this is also how a new one starts.
  ///
  /// Pass [phone] whenever you know it. A visitor is anonymous until they volunteer a number: if
  /// your app has already signed this person in, passing the number you hold is the difference
  /// between a thread that joins their history and one that starts a second record for them — or
  /// better, [identify] them.
  ///
  /// [timeZone] is the device's IANA zone; leave it out to ask the resolver this client was made
  /// with.
  Future<void> start({String? displayName, String? phone, String? timeZone}) async {
    await _loadToken();
    final zone = await _zoneFor(timeZone);
    final json = await _transport.post(
      '/api/chat/public/${Uri.encodeComponent(_publicKey)}/session',
      body: {
        if (displayName != null && displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (zone != null) 'timezone': zone,
      },
      headers: _tokenHeader(),
    );
    // A new conversation starts with nothing on screen but what the server says is in it.
    _patch(_state.copyWith(messages: const [], status: CnctChatStatus.connecting));
    await _adoptSession(_asMap(json));
    connect();
  }

  /// Pick up where a restart left off. Resolves to false when there is no session to pick up —
  /// which is not an error, just a first-time visitor.
  ///
  /// A refused token is cleared here rather than thrown: the visitor's thirty days ran out or the
  /// business closed the conversation, and neither is something an app can act on beyond going back
  /// to its pre-chat screen.
  Future<bool> resume({String? timeZone}) async {
    await _loadToken();
    if (_token == null) return false;
    try {
      final zone = await _zoneFor(timeZone);
      final json = await _transport.get(
        '/api/chat/public/session',
        query: {'timezone': zone},
        headers: _tokenHeader(),
      );
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

  /// Sign this visitor in as one of the business's own users.
  ///
  /// The current token goes with the call, so a conversation started anonymously before they signed
  /// in moves across with them; the token that comes back replaces it, in the store too. If a
  /// conversation was already on screen it is re-read, because it may now be a different one — the
  /// signed-in user's own.
  ///
  /// Refusals: [CnctErrorCode.identityNotConfigured] when the inbox has no identity secret (409),
  /// [CnctErrorCode.identityRejected] when the hash does not verify (401). Either way the anonymous
  /// session is untouched, so the visitor still has a working chat — which is what the hosted widget
  /// does, and what `cnct_flutter_ui` does.
  Future<CnctChatVisitor> identify(CnctChatIdentity identity) async {
    await _loadToken();
    final dynamic json;
    try {
      json = await _transport.post(
        '/api/chat/public/${Uri.encodeComponent(_publicKey)}/identify',
        body: identity.toJson(),
        headers: _tokenHeader(),
      );
    } on CnctException catch (error) {
      throw switch (error.status) {
        409 => CnctException(error.message,
            code: CnctErrorCode.identityNotConfigured, status: 409, details: error.details),
        401 => CnctException(error.message,
            code: CnctErrorCode.identityRejected, status: 401, details: error.details),
        _ => error,
      };
    }
    final data = _asMap(json);
    final hadSession = _state.status != CnctChatStatus.idle;
    if (hadSession) _teardownSocket();
    await _adoptSession({'token': data['token'], 'visitor': data['visitor']});
    final visitor = _state.visitor ?? const CnctChatVisitor(displayName: '');
    if (hadSession) await resume();
    return visitor;
  }

  /// Give the visitor a name — the card a thread shows once an anonymous visitor has said
  /// something — and, where the inbox wants one, a number.
  Future<CnctChatVisitor> updateProfile({required String displayName, String? phone}) async {
    await _sessionReady();
    final json = await _transport.post(
      '/api/chat/public/profile',
      body: {
        'displayName': displayName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
      headers: _tokenHeader(),
    );
    final visitor = CnctChatVisitor.fromJson(_asMap(_asMap(json)['visitor']));
    _patch(_state.copyWith(visitor: visitor, clearError: true));
    return visitor;
  }

  // ── Past conversations ────────────────────────────────────────────────────────────────────────

  /// The visitor's conversations, up to fifty, newest first, each with its last message as
  /// [CnctChatConversation.preview].
  Future<CnctChatConversations> conversations() async {
    await _sessionReady();
    final data = _asMap(await _transport.get(
      '/api/chat/public/conversations',
      headers: _tokenHeader(),
    ));
    final visitor =
        data['visitor'] is Map ? CnctChatVisitor.fromJson(_asMap(data['visitor'])) : null;
    if (visitor != null) _patch(_state.copyWith(visitor: visitor));
    return CnctChatConversations(
      visitor: visitor,
      conversations: (data['conversations'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((item) => CnctChatConversation.fromJson(_asMap(item)))
          .toList(growable: false),
    );
  }

  /// One of the visitor's conversations, with everything said in it — an old one included, which
  /// is what makes past chats readable. Does not change [state]; the live conversation is the one
  /// [state] follows.
  Future<CnctChatTranscript> conversation(String id) async {
    await _sessionReady();
    final data = _asMap(await _transport.get(
      '/api/chat/public/conversations/${Uri.encodeComponent(id)}',
      headers: _tokenHeader(),
    ));
    return CnctChatTranscript(
      visitor: data['visitor'] is Map ? CnctChatVisitor.fromJson(_asMap(data['visitor'])) : null,
      conversation: CnctChatConversation.fromJson(_asMap(data['conversation'])),
      messages: (data['messages'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((item) => CnctChatMessage.fromJson(_asMap(item)))
          .toList(growable: false),
    );
  }

  /// Tell the team their newest reply is on the visitor's screen — the ticks in the console.
  ///
  /// **Once per reply.** Call it whenever a reply might be showing (it arrived while the chat was
  /// open, the app came back to the foreground) without counting: the newest reply already reported
  /// is remembered, and nothing is sent until a newer one arrives. A failed report is forgotten so
  /// the next call tries again. Resolves to whether anything was sent.
  ///
  /// Only call it while the reply really is on screen — a conversation scrolled out of sight or an
  /// app in the background has not read anything.
  Future<bool> markRead() async {
    final conversation = _state.conversation;
    if (_token == null || conversation == null || conversation.id.isEmpty) return false;
    final reply = _state.lastReply;
    if (reply == null || _reported[conversation.id] == reply.id) return false;
    _reported[conversation.id] = reply.id;
    try {
      await _transport.post(
        '/api/chat/public/conversations/${Uri.encodeComponent(conversation.id)}/read',
        headers: _tokenHeader(),
      );
      return true;
    } on CnctException {
      if (_reported[conversation.id] == reply.id) _reported.remove(conversation.id);
      rethrow;
    }
  }

  /// Rate a closed conversation, 1 (worst) to 5 (best), with an optional comment. Defaults to the
  /// conversation in [state].
  ///
  /// The hosted widget saves the face the moment it is tapped and sends the comment as a second
  /// rating with the same score — call this twice the same way. A conversation that can no longer
  /// be rated answers [CnctErrorCode.conflict].
  Future<CnctChatConversation> rate(int score, {String? comment, String? conversationId}) async {
    await _sessionReady();
    if (score < 1 || score > 5) {
      throw CnctException('A rating is 1 to 5.', code: CnctErrorCode.invalid);
    }
    final id = conversationId ?? _state.conversation?.id ?? '';
    if (id.isEmpty) {
      throw CnctException('There is no conversation to rate.', code: CnctErrorCode.notFound);
    }
    final json = await _transport.post(
      '/api/chat/public/conversations/${Uri.encodeComponent(id)}/rating',
      body: {'score': score, if (comment != null) 'comment': comment},
      headers: _tokenHeader(),
    );
    final rated = CnctChatConversation.fromJson(_asMap(_asMap(json)['conversation']));
    if (_state.conversation?.id == id) {
      _patch(_state.copyWith(conversation: rated, clearError: true));
    }
    return rated;
  }

  // ── Saying something ──────────────────────────────────────────────────────────────────────────

  /// Say something — words, files, or both. Resolves once the server has it.
  ///
  /// [attachments] are files already uploaded with [upload]; their ids go as `attachmentIds`.
  /// [replyId] is the id of a flow choice the visitor tapped — [choose] sets it for you.
  ///
  /// The optimistic bubble goes into [state] immediately and is replaced in place when the real row
  /// arrives — matched on `clientKey`, which is also the frame id and also the server's idempotency
  /// key, so the three can never disagree about which message this is.
  ///
  /// On failure the bubble stays, marked [CnctChatMessage.failed], and the exception is thrown. Do
  /// not clear it: the words somebody typed vanishing is worse than a retry button. The one
  /// exception is a conversation that has ended underneath (409): the bubble goes, the state ends,
  /// and the exception says [CnctErrorCode.conversationClosed].
  Future<CnctChatMessage> send(
    String body, {
    String? clientKey,
    List<CnctChatAttachment> attachments = const [],
    String? replyId,
  }) async {
    await _loadToken();
    if (_token == null) {
      throw CnctException('Start a conversation first.', code: CnctErrorCode.noSession);
    }
    final text = body.trim();
    if (text.isEmpty && attachments.isEmpty) {
      throw CnctException('Nothing to send.', code: CnctErrorCode.empty);
    }
    if (text.length > maxMessageLength) {
      throw CnctException(
        'A message is at most $maxMessageLength characters.',
        code: CnctErrorCode.tooLarge,
      );
    }
    if (attachments.length > CnctAttachmentRules.maxFiles) {
      throw CnctException(
        'Up to ${CnctAttachmentRules.maxFiles} files at a time.',
        code: CnctErrorCode.tooManyFiles,
      );
    }
    final key = clientKey ?? _uid();

    final existing = _state.messages.indexWhere((message) => message.clientKey == key);
    if (existing >= 0) {
      final messages = _state.messages.toList();
      messages[existing] = messages[existing].copyWith(pending: true, failed: false);
      _patch(_state.copyWith(messages: messages));
    } else {
      _patch(_state.copyWith(
        messages: [
          ..._state.messages,
          CnctChatMessage.optimistic(
            clientKey: key,
            body: text,
            attachments: attachments,
            replyId: replyId,
          ),
        ],
      ));
    }

    final frame = {
      'body': text,
      'clientKey': key,
      if (attachments.isNotEmpty) 'attachmentIds': [for (final file in attachments) file.id],
      if (replyId != null) 'replyId': replyId,
    };
    try {
      if (_socketSendSupported && _socket != null) {
        return await _sendOverSocket(key, frame);
      }
      // The fallback, and a real path rather than a formality: it runs against a server that
      // predates socket sends, and whenever the socket happens to be between connections. Same
      // endpoint, same idempotency key.
      final json = await _transport.post(
        '/api/chat/public/messages',
        body: frame,
        headers: _tokenHeader(),
      );
      final message = CnctChatMessage.fromJson(_asMap(json));
      _absorb(message);
      return message;
    } on CnctException catch (error) {
      if (error.status == 409 || error.code == CnctErrorCode.conversationClosed) {
        final closed = CnctException(error.message,
            code: CnctErrorCode.conversationClosed, status: error.status);
        _patch(_state.copyWith(
          messages: _state.messages.where((message) => message.clientKey != key).toList(),
        ));
        _closedUnderneath();
        _fail(closed);
        throw closed;
      }
      _markFailed(key);
      _fail(error);
      rethrow;
    }
  }

  /// The longest message the platform takes.
  static const maxMessageLength = 4000;

  /// Tap a flow's choice: its title is sent as the visitor's words, with its id as `replyId`, so
  /// the flow follows the button exactly rather than reading the title as typing.
  Future<CnctChatMessage> choose(CnctFlowChoice choice) => send(choice.title, replyId: choice.id);

  /// Re-send a message that failed — its words, its files and its choice. The same `clientKey`, so
  /// the server cannot write it twice.
  Future<CnctChatMessage> retry(String clientKey) {
    for (final message in _state.messages) {
      if (message.clientKey == clientKey) {
        return send(
          message.body,
          clientKey: clientKey,
          attachments: message.attachments,
          replyId: message.replyId,
        );
      }
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
  ///
  /// The server's view of the closed conversation — whether it can be rated — is fetched straight
  /// after, so a rating card can be drawn without another call.
  Future<void> end() async {
    await _loadToken();
    if (_token == null) return;
    await _transport.post('/api/chat/public/close', headers: _tokenHeader());
    _closedUnderneath();
  }

  // ── Files ─────────────────────────────────────────────────────────────────────────────────────

  /// Send one file up, ahead of the message it goes with.
  ///
  /// Checked first against [CnctAttachmentRules] — size, type, HEIC — so a refusal arrives before a
  /// byte is sent. Needs a session: upload after [start], and send the message with
  /// `send(text, attachments: [await upload.result])`.
  ///
  /// The server's refusals arrive as [CnctErrorCode.attachmentsOff] (the inbox takes no files, or
  /// the deployment keeps none), [CnctErrorCode.conversationClosed], [CnctErrorCode.tooLarge] and
  /// [CnctErrorCode.unsupportedType], each with the server's own sentence as the message.
  CnctUpload upload(CnctUploadFile file, {void Function(double progress)? onProgress}) {
    final upload = DrivenUpload(file);
    if (onProgress != null) upload.progressChanges.listen(onProgress);
    final refusal = file.check();
    if (refusal != null) {
      upload.fail(refusal);
    } else {
      unawaited(_upload(upload));
    }
    return upload;
  }

  Future<void> _upload(DrivenUpload upload) async {
    await _loadToken();
    if (_token == null) {
      upload.fail(CnctException('Start a conversation first.', code: CnctErrorCode.noSession));
      return;
    }
    final file = upload.file;
    try {
      final json = await _transport.postMultipart(
        '/api/chat/public/attachments',
        field: 'file',
        content: file.openRead(),
        length: file.length,
        filename: file.filename,
        mimeType: file.mimeType,
        headers: _tokenHeader(),
        onProgress: (sent, total) => upload.report(total == 0 ? 1 : sent / total),
        isCancelled: () => upload.isCancelled,
      );
      final attachment = CnctChatAttachment.fromJson(_asMap(_asMap(json)['attachment']));
      if (attachment.id.isEmpty) {
        throw CnctException('The server stored the file but did not say where.',
            code: CnctErrorCode.badResponse);
      }
      // The visitor's own copy is already here; the bubble that shows it should not fetch it back.
      final bytes = file.bytes;
      if (bytes != null) cacheAttachment(attachment.id, bytes);
      upload.complete(attachment);
    } on CnctException catch (error) {
      if (error.status == 409) _closedUnderneath();
      upload.fail(_uploadRefusal(error));
    }
  }

  /// The status said it better than the generic mapping does: a 403 here is the inbox's setting,
  /// not a bad token, and must not send anybody back to sign in.
  CnctException _uploadRefusal(CnctException error) {
    final code = switch (error.status) {
      403 || 503 => CnctErrorCode.attachmentsOff,
      409 => CnctErrorCode.conversationClosed,
      413 => CnctErrorCode.tooLarge,
      422 || 415 => CnctErrorCode.unsupportedType,
      _ => null,
    };
    return code == null
        ? error
        : CnctException(error.message, code: code, status: error.status, details: error.details);
  }

  /// The bytes of a file in one of this visitor's conversations — a past one included. Scoped by
  /// the server; an id from anywhere else is a 404 rather than a refusal, so a stranger learns
  /// nothing.
  ///
  /// **Cached by id**, within a budget, and a second request for a file already on its way waits
  /// for the first rather than starting another.
  Future<Uint8List> downloadAttachment(String attachmentId) {
    final held = _files.remove(attachmentId);
    if (held != null) {
      _files[attachmentId] = held;
      return Future.value(held);
    }
    // A block, not an arrow: `remove` returns this very future, and a `whenComplete` callback that
    // returns a future is waited on — which would be the future waiting for itself.
    return _fetching[attachmentId] ??= _fetchAttachment(attachmentId).whenComplete(() {
      _fetching.remove(attachmentId);
    });
  }

  Future<Uint8List> _fetchAttachment(String attachmentId) async {
    await _sessionReady();
    final bytes = await _transport.bytes(
      '/api/chat/public/attachments/${Uri.encodeComponent(attachmentId)}',
      headers: _tokenHeader(),
    );
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    cacheAttachment(attachmentId, data);
    return data;
  }

  /// Keep a file's bytes under its id, so [downloadAttachment] answers without the network. Done
  /// for you after an upload made from bytes.
  void cacheAttachment(String attachmentId, List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final previous = _files.remove(attachmentId);
    if (previous != null) _fileBytes -= previous.length;
    if (data.length > _fileBudget) return;
    _files[attachmentId] = data;
    _fileBytes += data.length;
    while (_fileBytes > _fileBudget && _files.isNotEmpty) {
      final oldest = _files.keys.first;
      _fileBytes -= _files.remove(oldest)!.length;
    }
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
      case 'chat.message.updated':
        // Edited, deleted, or a file that finished storing. Replaced where it stands, by id — a
        // message nobody has on screen is left for the next reload rather than appended out of
        // nowhere.
        final payload = frame['payload'];
        final raw =
            payload is Map ? (payload['message'] is Map ? payload['message'] : payload) : null;
        if (raw is Map) {
          final message = CnctChatMessage.fromJson(_asMap(raw));
          final at = _state.messages.indexWhere((candidate) => candidate.id == message.id);
          if (message.id.isNotEmpty && at >= 0) {
            final messages = _state.messages.toList()..[at] = message;
            _patch(_state.copyWith(messages: messages));
            _emit(CnctChatMessageUpdated(message));
          }
        }
      case 'chat.read':
        final at = DateTime.tryParse('${(frame['payload'] as Map<Object?, Object?>?)?['at']}');
        final conversation = _state.conversation;
        if (at != null && conversation != null) {
          _patch(_state.copyWith(conversation: conversation.copyWith(seenAt: at.toLocal())));
          _emit(CnctChatRead(at.toLocal()));
        }
      case 'chat.conversation.updated':
        final payload = frame['payload'];
        if (payload is! Map) return;
        final CnctChatConversation? conversation;
        if (payload['conversation'] is Map) {
          conversation = CnctChatConversation.fromJson(_asMap(payload['conversation']));
        } else {
          // The current server sends the change itself — `{status, withPerson, assignee}`, each
          // only when it changed — rather than the whole conversation.
          final current = _state.conversation;
          final patch = _asMap(payload);
          conversation = current?.copyWith(
            status:
                patch.containsKey('status') ? CnctConversationStatus.parse(patch['status']) : null,
            withPerson: patch['withPerson'] as bool?,
            assignee: patch['assignee'] is Map
                ? CnctChatSender.fromJson(_asMap(patch['assignee']),
                    fallbackKind: CnctSenderKind.person)
                : null,
            clearAssignee: patch.containsKey('assignee') && patch['assignee'] == null,
          );
        }
        if (conversation != null) {
          _patch(_state.copyWith(conversation: conversation));
          _emit(CnctChatConversationUpdated(conversation));
        }
      case 'chat.closed':
        _closedUnderneath();
        _emit(const CnctChatClosed());
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

  Future<CnctChatMessage> _sendOverSocket(String key, Map<String, Object?> body) {
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
    _say({'type': 'send', 'id': key, ...body});
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
    final stored = (data['messages'] as List<Object?>?)
        ?.whereType<Map<Object?, Object?>>()
        .map((item) => CnctChatMessage.fromJson(_asMap(item)))
        .toList();
    List<CnctChatMessage>? messages;
    if (stored != null) {
      // The server's transcript is the truth, but it cannot know about words still on their way
      // or ones that failed: those stay, unless the server's copy says they arrived after all.
      final arrived = {for (final message in stored) message.clientKey};
      messages = [
        ...stored,
        for (final local in _state.messages)
          if ((local.pending || local.failed) && !arrived.contains(local.clientKey)) local,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    _patch(_state.copyWith(
      visitor: visitor is Map ? CnctChatVisitor.fromJson(_asMap(visitor)) : null,
      conversation:
          conversation is Map ? CnctChatConversation.fromJson(_asMap(conversation)) : null,
      messages: messages,
      clearError: true,
    ));
  }

  /// The conversation ended while the visitor was in it — an operator closed it, the inbox's timer
  /// did, they pressed End, or a send found it gone. The socket goes, and the server's view of the
  /// closed conversation (whether it can be rated) is fetched to replace the guess made here.
  void _closedUnderneath() {
    _closedByUs = true;
    final conversation = _state.conversation;
    _patch(_state.copyWith(
      status: CnctChatStatus.ended,
      theyAreTyping: false,
      conversation: conversation?.copyWith(
        status: CnctConversationStatus.closed,
        closedAt: conversation.closedAt ?? DateTime.now(),
      ),
    ));
    _teardownSocket();
    if (conversation != null && conversation.id.isNotEmpty && _token != null) {
      unawaited(_rereadClosed(conversation.id));
    }
  }

  // Best effort: the rating card waits for the next load if this fails, and the thread is already
  // right.
  Future<void> _rereadClosed(String id) async {
    try {
      final transcript = await conversation(id);
      if (_disposed || _state.conversation?.id != id) return;
      _patch(_state.copyWith(conversation: transcript.conversation));
    } on CnctException catch (error) {
      _config.logger?.call(CnctLogLevel.debug, 'Could not re-read the closed conversation', error);
    }
  }

  Future<String?> _zoneFor(String? given) async {
    if (given != null && given.trim().isNotEmpty) return given.trim();
    try {
      final zone = await _timeZone?.call();
      return zone == null || zone.trim().isEmpty ? null : zone.trim();
    } catch (error) {
      // A time zone is a courtesy to the team, never a reason a conversation fails to start.
      _config.logger?.call(CnctLogLevel.debug, 'Could not read the time zone', error);
      return null;
    }
  }

  Future<void> _sessionReady() async {
    await _loadToken();
    if (_token == null) {
      throw CnctException('Start a conversation first.', code: CnctErrorCode.noSession);
    }
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
