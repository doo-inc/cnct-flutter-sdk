import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/foundation.dart';

import 'events.dart';
import 'files/open.dart';
import 'files/picked_file.dart';
import 'files/prepare.dart';
import 'files/source.dart';
import 'l10n/chat_l10n.dart';

/// Which screen the chat is on.
enum ChatPhase {
  /// Waiting for the inbox to answer.
  loading,

  /// The link is wrong, the inbox is off, or the platform could not be reached.
  unavailable,

  /// The inbox asks for a name before anything else.
  intro,

  /// The conversation: live, ended, or about to start with the first message.
  chat,
}

/// Something to say to the visitor: a key from the string tables, or the server's own sentence.
@immutable
class ChatNotice {
  const ChatNotice(this.key, [this.vars = const {}]) : message = null;
  const ChatNotice.sentence(String this.message)
      : key = null,
        vars = const {};

  final String? key;
  final Map<String, Object> vars;
  final String? message;

  String resolve(ChatL10n l10n) => message ?? l10n.t(key!, vars);

  /// The words for a failure: the server's sentence where it gave one, the generic line otherwise.
  static ChatNotice of(Object error) {
    if (error is CnctException) {
      if (error.isRetryable && error.code != CnctErrorCode.rateLimited) {
        return const ChatNotice('genericError');
      }
      if (error.status != null && error.message.isNotEmpty) {
        return ChatNotice.sentence(error.message);
      }
    }
    return const ChatNotice('genericError');
  }
}

/// Where a picked file is.
enum UploadStatus { preparing, uploading, done, failed }

/// One file in the tray above the composer.
class UploadChip {
  UploadChip({required this.key, required this.name, required this.mimeType, required this.length});

  final String key;
  String name;
  String mimeType;
  int length;

  /// The picture itself, for a thumbnail — and, once sent, for the bubble, without fetching it back.
  Uint8List? preview;
  UploadStatus status = UploadStatus.preparing;
  CnctUpload? upload;
  CnctChatAttachment? attachment;
  bool removed = false;

  /// 0 to 1. Its own notifier, so a progress ring redraws without redrawing the conversation. Never
  /// disposed: a chip leaves the tray while its ring may still be listening, and an unheard notifier
  /// costs nothing.
  final progress = ValueNotifier<double>(0);

  bool get isImage => mimeType.startsWith('image/');
}

/// Where a closed conversation's rating card is.
enum RatingStage { faces, comment, done }

/// Everything the chat screen does, kept out of its widgets.
///
/// It is built on the headless client's public API alone — the same calls an app building its own
/// screen would make — and adds only what is a screen's business: which phase it is in, the words
/// written before a session existed, the tray of picked files, and the cards.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.client,
    this.ownsClient = false,
    CnctChatIdentity? identity,
    this.onEvent,
    FileSource? files,
    this.decode,
  })  : _identity = identity,
        files = files ?? SystemFileSource() {
    _subscription = client.states.listen(_onState);
  }

  final CnctChatClient client;

  /// True when the chat made its client from a public key, and so closes it.
  final bool ownsClient;
  final ValueChanged<CnctChatUiEvent>? onEvent;
  final FileSource files;

  /// A stand-in for the platform's image decoder, for tests.
  final ImageDecoder? decode;

  CnctChatIdentity? _identity;
  late final StreamSubscription<CnctChatState> _subscription;
  final _random = Random();

  ChatPhase phase = ChatPhase.loading;
  ChatNotice? unavailableTitle;
  ChatNotice? unavailableBody;

  /// The line above the composer: a refused file, a send that failed, a rate limit.
  ChatNotice? notice;

  bool confirmingEnd = false;
  bool introBusy = false;
  ChatNotice? introError;
  bool profileBusy = false;
  ChatNotice? profileError;

  /// The name just given in the thread's card, for a "thanks" in its place.
  String? justNamed;

  RatingStage? _ratingStage;
  int? _ratingScore;
  ChatNotice? ratingError;

  /// Files picked, on their way up or waiting to go with the next message.
  final List<UploadChip> uploads = [];

  /// The visitor's words written before there was a session to send them to — the first message
  /// of a chat that lets them type first. Shown at once; the client's own bubble, with the same
  /// key, takes over the moment the session exists.
  final List<CnctChatMessage> _local = [];

  /// True while a new conversation is being composed after an old one closed: the client still
  /// holds the closed one, and the screen should not.
  bool _fresh = false;

  Future<void>? _starting;
  bool _onScreen = false;
  bool _disposed = false;

  // ── What the screen shows ─────────────────────────────────────────────────────────────────────

  CnctChatState get state => client.state;
  CnctChatInbox? get inbox => state.inbox;
  CnctChatSettings get settings => inbox?.widget.chat ?? const CnctChatSettings();

  /// The conversation on screen. Null before the first message, and while a new one is composed.
  CnctChatConversation? get conversation => _fresh ? null : state.conversation;

  /// True while the visitor can write: no conversation yet, or one that is still open.
  bool get isLive {
    final current = conversation;
    if (current == null) return true;
    return !current.isClosed && state.status != CnctChatStatus.ended;
  }

  /// Oldest first: the server's, then words still waiting for a session.
  List<CnctChatMessage> get messages {
    final stored = _fresh ? const <CnctChatMessage>[] : state.messages;
    final keys = {for (final message in stored) message.clientKey};
    return [
      ...stored,
      for (final local in _local)
        if (!keys.contains(local.clientKey)) local,
    ];
  }

  /// The inbox's greeting, as the first line of a conversation not yet started — the same line the
  /// server writes the moment the session begins.
  String? get greeting {
    final words = inbox?.greeting ?? '';
    return conversation == null && words.trim().isNotEmpty ? words : null;
  }

  CnctChatFlow? get awaiting => _fresh ? null : state.awaiting;
  List<String> get suggestions => _fresh ? const [] : state.suggestions;
  bool get theyAreTyping => !_fresh && isLive && state.theyAreTyping;

  /// The socket is down on a live conversation — the "reconnecting" banner. Never an error: sends
  /// still go over HTTP.
  bool get isOffline => conversation != null && isLive && state.status == CnctChatStatus.offline;

  bool get canAttach => isLive && settings.allowAttachments && !confirmingEnd;
  bool get canEnd => settings.allowEndConversation && conversation != null && isLive;
  bool get uploading => uploads.any(
      (chip) => chip.status == UploadStatus.preparing || chip.status == UploadStatus.uploading);

  bool get _named => state.visitor != null && !state.visitor!.anonymous;

  /// The name card in the thread: an anonymous visitor who has said something is asked for a name.
  bool get asksForName =>
      conversation != null &&
      justNamed == null &&
      (state.visitor?.anonymous ?? false) &&
      messages.any((message) => message.isMine && !message.pending && !message.failed);

  bool get showsRating {
    final current = conversation;
    return current != null &&
        current.isClosed &&
        settings.askForRating &&
        (current.ratable || current.rating != null);
  }

  RatingStage get ratingStage =>
      _ratingStage ?? (conversation?.rating == null ? RatingStage.faces : RatingStage.done);
  int? get ratingScore => _ratingScore ?? conversation?.rating?.score;

  // ── Opening ───────────────────────────────────────────────────────────────────────────────────

  /// Boot, sign in if the app said who this is, pick up a stored conversation, and land.
  Future<void> open() async {
    phase = ChatPhase.loading;
    _notify();
    final CnctChatInbox inbox;
    try {
      inbox = await client.boot();
    } on CnctException catch (error) {
      _unavailable(
        error.status == 404 ? const ChatNotice('linkInvalid') : const ChatNotice('chatUnavailable'),
        error.status == 404
            ? const ChatNotice('linkInvalidBody')
            : const ChatNotice('tryAgainSoon'),
      );
      return;
    }
    if (!inbox.isActive) {
      _unavailable(
        ChatNotice('notTakingChats', {'business': inbox.business}),
        const ChatNotice('notTakingChatsBody'),
      );
      return;
    }
    _emit(CnctChatUiEventType.opened);

    // Signed in first, when the app says who this is, so the conversation read next is theirs.
    final identity = _identity;
    if (identity != null) await _identify(identity);

    try {
      await client.resume();
    } on CnctException catch (error) {
      debugPrint('[cnct] Could not pick the conversation back up: ${error.message}');
      _unavailable(const ChatNotice('chatUnavailable'), const ChatNotice('tryAgainSoon'));
      return;
    }
    _land();
  }

  /// The app signed somebody in — or out, with null — after the chat opened.
  Future<void> setIdentity(CnctChatIdentity? identity) async {
    _identity = identity;
    if (identity == null || phase == ChatPhase.loading || phase == ChatPhase.unavailable) return;
    await _identify(identity);
    _land();
  }

  /// A failure is said in the log for the app's developer and otherwise ignored: the visitor still
  /// gets a working, anonymous chat, as the hosted widget does.
  Future<void> _identify(CnctChatIdentity identity) async {
    try {
      await client.identify(identity);
    } on CnctException catch (error) {
      debugPrint('[cnct] Could not sign this visitor in (${error.code}): ${error.message}');
    }
  }

  void _land() {
    phase = state.conversation == null && settings.start == CnctChatStartMode.details && !_named
        ? ChatPhase.intro
        : ChatPhase.chat;
    _notify();
  }

  void _unavailable(ChatNotice title, ChatNotice body) {
    phase = ChatPhase.unavailable;
    unavailableTitle = title;
    unavailableBody = body;
    _notify();
  }

  // ── Starting ──────────────────────────────────────────────────────────────────────────────────

  /// The name form, for an inbox that asks first.
  Future<void> submitIntro({required String name, String? phone}) async {
    if (name.trim().isEmpty || introBusy) return;
    introBusy = true;
    introError = null;
    _notify();
    try {
      await client.start(displayName: name.trim(), phone: phone);
      _fresh = false;
      phase = ChatPhase.chat;
      _emit(CnctChatUiEventType.started);
    } on CnctException catch (error) {
      introError = error.code == CnctErrorCode.rateLimited
          ? const ChatNotice('tooManyChats')
          : ChatNotice.of(error);
    } finally {
      introBusy = false;
      _notify();
    }
  }

  /// "Start a new conversation", after one has ended.
  void startNew() {
    _clearUploads();
    _fresh = true;
    _local.clear();
    confirmingEnd = false;
    notice = null;
    justNamed = null;
    _ratingStage = null;
    _ratingScore = null;
    ratingError = null;
    phase =
        settings.start == CnctChatStartMode.details && !_named ? ChatPhase.intro : ChatPhase.chat;
    _notify();
  }

  /// The conversation exists on the server — started now, if this is the first thing the visitor
  /// does. A message and a file in the same moment share one start rather than racing to make two.
  Future<void> _ensureSession() {
    if (!_fresh && state.conversation != null && client.hasSession) return Future.value();
    return _starting ??= () async {
      try {
        await client.start();
        _fresh = false;
        _emit(CnctChatUiEventType.started);
      } finally {
        _starting = null;
      }
    }();
  }

  // ── Saying something ──────────────────────────────────────────────────────────────────────────

  /// Send the composer's words and every finished file. Resolves to whether the composer should
  /// clear — false when there was nothing to send, or files are still on their way.
  Future<bool> send(String text) async {
    if (!isLive || uploading) return false;
    final body = text.trim();
    final attachments = [
      for (final chip in uploads)
        if (chip.status == UploadStatus.done && chip.attachment != null) chip.attachment!,
    ];
    if (body.isEmpty && attachments.isEmpty) return false;
    notice = null;
    // Out of the tray at once; their pictures live on as the bubble's, from the client's cache.
    _clearUploads();
    unawaited(_deliver(_uid(), body, attachments));
    return true;
  }

  /// Tap a flow's choice.
  Future<void> choose(CnctFlowChoice choice) async {
    if (!isLive) return;
    notice = null;
    _notify();
    try {
      await client.choose(choice);
    } on CnctException catch (error) {
      _sendFailed(error);
    }
  }

  /// Tap one of the assistant's suggested replies.
  Future<void> suggest(String text) => send(text);

  /// Try a failed message again, with the same key, so it cannot be written twice.
  Future<void> retry(CnctChatMessage message) async {
    final key = message.clientKey;
    if (key == null) return;
    notice = null;
    final at = _local.indexWhere((local) => local.clientKey == key);
    if (at < 0) {
      try {
        await client.retry(key);
      } on CnctException catch (error) {
        _sendFailed(error);
      }
      return;
    }
    _local.removeAt(at);
    await _deliver(key, message.body, message.attachments, replyId: message.replyId);
  }

  Future<void> _deliver(
    String key,
    String body,
    List<CnctChatAttachment> attachments, {
    String? replyId,
  }) async {
    final needsSession = _fresh || state.conversation == null;
    if (needsSession) {
      _local.add(CnctChatMessage.optimistic(
        clientKey: key,
        body: body,
        attachments: attachments,
        replyId: replyId,
      ));
      _notify();
      try {
        await _ensureSession();
      } on CnctException catch (error) {
        _markLocalFailed(key);
        notice = error.code == CnctErrorCode.rateLimited
            ? const ChatNotice('tooManyChats')
            : ChatNotice.of(error);
        _notify();
        return;
      }
    }
    try {
      await client.send(body, clientKey: key, attachments: attachments, replyId: replyId);
      _emit(CnctChatUiEventType.sent, attachments: attachments.length);
      for (final file in attachments) {
        _emit(CnctChatUiEventType.attachmentSent, mimeType: file.mimeType);
      }
    } on CnctException catch (error) {
      _sendFailed(error);
    } finally {
      // The client holds this message now, under the same key — sent, failed, or gone with a
      // conversation that closed underneath.
      _local.removeWhere((local) => local.clientKey == key);
      _notify();
    }
  }

  void _sendFailed(CnctException error) {
    if (error.code == CnctErrorCode.conversationClosed) return;
    notice = error.code == CnctErrorCode.rateLimited
        ? const ChatNotice('slowDown')
        : ChatNotice.of(error);
    _notify();
  }

  void _markLocalFailed(String key) {
    for (var i = 0; i < _local.length; i++) {
      if (_local[i].clientKey == key) _local[i] = _local[i].copyWith(pending: false, failed: true);
    }
  }

  /// Somebody is typing in the composer. The client throttles it.
  void typed() {
    if (!_fresh && state.conversation != null) client.typing();
  }

  // ── Files ─────────────────────────────────────────────────────────────────────────────────────

  /// Pick from the photo library, the camera or the file system, and start each upload.
  Future<void> pick(Future<List<PickedFile>> Function() source) async {
    try {
      addFiles(await source());
    } catch (error) {
      // A picker that failed — no permission, cancelled oddly — has nothing to add, and nothing
      // to tell the visitor that the system did not already.
      debugPrint('[cnct] The picker failed: $error');
    }
  }

  /// Check each file, put it in the tray and send it up at once. **Refused before uploading**, with
  /// a sentence: the eleventh file, a file over 50 MB, a type the platform does not take.
  void addFiles(List<PickedFile> picked) {
    if (!canAttach || picked.isEmpty) return;
    notice = null;
    for (final file in picked) {
      if (uploads.length >= CnctAttachmentRules.maxFiles) {
        notice = const ChatNotice('tooMany');
        break;
      }
      if (file.length > CnctAttachmentRules.maxBytes) {
        notice = ChatNotice('tooBig', {'name': file.name});
        continue;
      }
      final heic = CnctAttachmentRules.isHeic(file.mimeType, file.name);
      if (!heic && !CnctAttachmentRules.accepts(file.mimeType)) {
        notice = ChatNotice('notAccepted', {'name': file.name});
        continue;
      }
      final chip = UploadChip(
        key: _uid(),
        name: file.name,
        mimeType: file.mimeType,
        length: file.length,
      );
      uploads.add(chip);
      unawaited(_process(chip, file));
    }
    _notify();
  }

  Future<void> _process(UploadChip chip, PickedFile file) async {
    final PreparedFile prepared;
    try {
      prepared = await prepareForUpload(file, decode: decode);
    } catch (error) {
      debugPrint('[cnct] Could not prepare ${file.name}: $error');
      return _failChip(chip, ChatNotice('notAccepted', {'name': file.name}));
    }
    if (chip.removed) return;
    chip
      ..name = prepared.name
      ..mimeType = prepared.mimeType
      ..length = prepared.length
      ..preview =
          prepared.bytes != null && prepared.mimeType.startsWith('image/') ? prepared.bytes : null;
    final refusal = CnctAttachmentRules.check(
      filename: prepared.name,
      mimeType: prepared.mimeType,
      bytes: prepared.length,
    );
    if (refusal != null) {
      return _failChip(
        chip,
        refusal.code == CnctErrorCode.tooLarge
            ? ChatNotice('tooBig', {'name': prepared.name})
            : ChatNotice('notAccepted', {'name': prepared.name}),
      );
    }
    _notify();

    try {
      await _ensureSession();
    } on CnctException catch (error) {
      return _failChip(
        chip,
        error.code == CnctErrorCode.rateLimited
            ? const ChatNotice('tooManyChats')
            : ChatNotice.of(error),
      );
    }
    if (chip.removed || _disposed) return;

    final upload = client.upload(prepared.toUploadFile());
    chip
      ..upload = upload
      ..status = UploadStatus.uploading;
    _notify();
    final progress = upload.progressChanges.listen((value) => chip.progress.value = value);
    try {
      chip.attachment = await upload.result;
      chip.status = UploadStatus.done;
      chip.progress.value = 1;
    } on CnctException catch (error) {
      if (error.code == CnctErrorCode.cancelled || chip.removed) return;
      if (error.code == CnctErrorCode.conversationClosed) return;
      _failChip(
        chip,
        switch (error.code) {
          CnctErrorCode.tooLarge => ChatNotice('tooBig', {'name': chip.name}),
          CnctErrorCode.unsupportedType => ChatNotice('notAccepted', {'name': chip.name}),
          _ => ChatNotice('uploadFailed', {'name': chip.name}),
        },
      );
    } finally {
      await progress.cancel();
      _notify();
    }
  }

  void _failChip(UploadChip chip, ChatNotice why) {
    if (chip.removed) return;
    chip.status = UploadStatus.failed;
    notice = why;
    _notify();
  }

  void removeUpload(UploadChip chip) {
    chip.removed = true;
    chip.upload?.cancel();
    uploads.remove(chip);
    _notify();
  }

  void _clearUploads() {
    for (final chip in uploads) {
      chip.removed = true;
      if (chip.status != UploadStatus.done) chip.upload?.cancel();
    }
    uploads.clear();
  }

  /// A received file's bytes, fetched with the visitor's token and cached by id.
  Future<Uint8List> fileBytes(String attachmentId) => client.downloadAttachment(attachmentId);

  /// Download a received file and hand it to the platform to open or share.
  Future<void> openAttachment(CnctChatAttachment attachment, {Rect? origin}) async {
    try {
      final bytes = await fileBytes(attachment.id);
      await openReceivedFile(
        bytes,
        filename: attachment.filename ?? 'file',
        mimeType: attachment.mimeType,
        origin: origin,
      );
    } catch (error) {
      notice = ChatNotice('couldNotLoad', {'name': attachment.filename ?? ''});
      debugPrint('[cnct] Could not open ${attachment.filename}: $error');
      _notify();
    }
  }

  // ── The name card, ending, rating ─────────────────────────────────────────────────────────────

  Future<void> saveProfile({required String name, String? phone}) async {
    if (name.trim().isEmpty || profileBusy) return;
    profileBusy = true;
    profileError = null;
    _notify();
    try {
      await client.updateProfile(displayName: name.trim(), phone: phone);
      justNamed = name.trim();
    } on CnctException catch (error) {
      profileError = ChatNotice.of(error);
    } finally {
      profileBusy = false;
      _notify();
    }
  }

  void askToEnd() {
    confirmingEnd = true;
    _notify();
  }

  void keepChatting() {
    confirmingEnd = false;
    _notify();
  }

  Future<void> end() async {
    confirmingEnd = false;
    _notify();
    try {
      await client.end();
      _emit(CnctChatUiEventType.ended);
    } on CnctException catch (error) {
      notice = ChatNotice.of(error);
      _notify();
    }
  }

  /// Tapping a face saves it at once — the face *is* the answer, and a visitor who taps and closes
  /// the app has still told the business something — and then offers a box for more.
  Future<void> rate(int score) async {
    final id = conversation?.id;
    if (id == null) return;
    final stageBefore = _ratingStage;
    final scoreBefore = _ratingScore;
    _ratingScore = score;
    _ratingStage = RatingStage.comment;
    ratingError = null;
    _notify();
    try {
      await client.rate(score, conversationId: id);
      _emit(CnctChatUiEventType.rated, score: score);
    } on CnctException catch (error) {
      _ratingStage = stageBefore;
      _ratingScore = scoreBefore;
      ratingError = ChatNotice.of(error);
      _notify();
    }
  }

  /// The comment, sent as a second answer to the same question.
  Future<void> sendRatingComment(String comment) async {
    final id = conversation?.id;
    final score = ratingScore;
    if (id == null || score == null) return;
    _ratingStage = RatingStage.done;
    ratingError = null;
    _notify();
    try {
      await client.rate(score, comment: comment.trim(), conversationId: id);
    } on CnctException catch (error) {
      _ratingStage = RatingStage.comment;
      ratingError = ChatNotice.of(error);
      _notify();
    }
  }

  void skipRatingComment() {
    _ratingStage = RatingStage.done;
    _notify();
  }

  // ── Read receipts ─────────────────────────────────────────────────────────────────────────────

  /// Whether the chat is on screen in an app in the foreground. Only then has anybody read anything.
  set onScreen(bool value) {
    if (_onScreen == value) return;
    _onScreen = value;
    _reportRead();
  }

  void _reportRead() {
    if (!_onScreen || _fresh || phase != ChatPhase.chat || state.conversation == null) return;
    unawaited(client.markRead().then<void>((_) {}, onError: (Object error) {
      debugPrint('[cnct] Could not mark the reply read: $error');
    }));
  }

  // ── Plumbing ──────────────────────────────────────────────────────────────────────────────────

  void _onState(CnctChatState next) {
    if (next.conversation?.isClosed ?? false) {
      // Files waiting for a conversation that has ended have nowhere to go.
      if (uploads.isNotEmpty) _clearUploads();
      confirmingEnd = false;
    }
    _reportRead();
    _notify();
  }

  void _emit(
    CnctChatUiEventType type, {
    int attachments = 0,
    String? mimeType,
    int? score,
  }) {
    final callback = onEvent;
    if (callback == null) return;
    try {
      callback(CnctChatUiEvent(
        type,
        conversationId: state.conversation?.id,
        attachments: attachments,
        mimeType: mimeType,
        score: score,
      ));
    } catch (error) {
      // An analytics callback is never the reason a chat breaks.
      debugPrint('[cnct] onEvent threw: $error');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _uid() {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = List.generate(8, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
    return 'u$stamp$noise';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    _clearUploads();
    if (ownsClient) client.dispose();
    super.dispose();
  }
}
