/// Who said it.
enum CnctSpeaker {
  /// The visitor — the person using your app.
  caller,

  /// The assistant.
  ai,

  /// A human on the business's side. [CnctChatMessage.sender] says who, by first name and face —
  /// never more than that, because a colleague's surname and role are not a customer's business.
  operator,

  /// The platform itself: a greeting, an out-of-hours notice, a "nobody is covering this" line.
  system,

  /// A speaker added after this version of the SDK was written. Render it as you would [system].
  unknown;

  static CnctSpeaker parse(Object? raw) => switch ('$raw') {
        'CALLER' => CnctSpeaker.caller,
        'AI' => CnctSpeaker.ai,
        'OPERATOR' => CnctSpeaker.operator,
        'SYSTEM' => CnctSpeaker.system,
        _ => CnctSpeaker.unknown,
      };

  /// True for anything that is not the visitor — the side of the bubble to draw it on.
  bool get isFromBusiness => this != CnctSpeaker.caller;

  /// True for the two speakers whose words are an answer: an operator's, or the assistant's. The
  /// ones worth telling the team were read, and the ones a "Seen" is about.
  bool get isReply => this == CnctSpeaker.operator || this == CnctSpeaker.ai;
}

/// Where a conversation is.
enum CnctConversationStatus {
  open,
  snoozed,
  closed,
  unknown;

  static CnctConversationStatus parse(Object? raw) => switch ('$raw') {
        'OPEN' => CnctConversationStatus.open,
        'SNOOZED' => CnctConversationStatus.snoozed,
        'CLOSED' => CnctConversationStatus.closed,
        _ => CnctConversationStatus.unknown,
      };
}

/// What to render a message as.
///
/// **Anything unrecognised is [text], and that is the whole compatibility story.** A card type added
/// to the platform next year arrives at an app built today with a `body` that reads correctly as a
/// sentence — "We have opened ticket #1042 for this: Refund not received" — so the app shows
/// something true rather than an empty bubble. Handling a new card is an opt-in improvement, never
/// a required migration.
enum CnctMessageType {
  text,
  ticketUpdate,
  bookingUpdate,

  /// A card this SDK does not know. [CnctChatMessage.rawType] has its name and
  /// [CnctChatMessage.data] its fields; [CnctChatMessage.body] is always safe to show.
  other;

  static CnctMessageType parse(Object? raw) => switch ('$raw') {
        'TICKET_UPDATE' => CnctMessageType.ticketUpdate,
        'BOOKING_UPDATE' => CnctMessageType.bookingUpdate,
        'TEXT' => CnctMessageType.text,
        _ => CnctMessageType.other,
      };
}

/// What kind of file was sent.
enum CnctAttachmentKind {
  image,
  video,
  audio,
  document,
  sticker,
  other;

  /// Case-insensitive, because the platform says `IMAGE` on an attachment and `image` on a flow's
  /// media, and both mean the same picture.
  static CnctAttachmentKind parse(Object? raw) => switch ('$raw'.toUpperCase()) {
        'IMAGE' => CnctAttachmentKind.image,
        'VIDEO' => CnctAttachmentKind.video,
        'AUDIO' => CnctAttachmentKind.audio,
        'DOCUMENT' => CnctAttachmentKind.document,
        'STICKER' => CnctAttachmentKind.sticker,
        _ => CnctAttachmentKind.other,
      };

  /// The same kind for a MIME type, for a file that has not been uploaded yet.
  static CnctAttachmentKind forMimeType(String mimeType) {
    final type = mimeType.toLowerCase();
    if (type.startsWith('image/')) return CnctAttachmentKind.image;
    if (type.startsWith('video/')) return CnctAttachmentKind.video;
    if (type.startsWith('audio/')) return CnctAttachmentKind.audio;
    return CnctAttachmentKind.document;
  }

  /// The platform's own spelling, which is also the key the string tables use (`quoteIMAGE`).
  String get wireName => name.toUpperCase();
}

// ── The inbox ─────────────────────────────────────────────────────────────────────────────────────

/// Light, dark, or whatever the device is set to. `auto` is the platform's word for the last.
enum CnctAppearanceSetting {
  light,
  dark,
  auto;

  static CnctAppearanceSetting parse(Object? raw) => switch ('$raw') {
        'dark' => CnctAppearanceSetting.dark,
        'auto' => CnctAppearanceSetting.auto,
        _ => CnctAppearanceSetting.light,
      };
}

/// The language a business pinned its chat to, or `auto` to follow each visitor's device.
enum CnctLanguageSetting {
  auto,
  en,
  ar;

  static CnctLanguageSetting parse(Object? raw) => switch ('$raw') {
        'en' => CnctLanguageSetting.en,
        'ar' => CnctLanguageSetting.ar,
        _ => CnctLanguageSetting.auto,
      };
}

/// How a conversation begins.
enum CnctChatStartMode {
  /// Ask for a name first — and a phone number, where the inbox wants one.
  details,

  /// Let them type first. The session starts on the first send, and the name is asked for in the
  /// thread once they have said something.
  message;

  static CnctChatStartMode parse(Object? raw) =>
      '$raw' == 'message' ? CnctChatStartMode.message : CnctChatStartMode.details;
}

/// How the business branded its chat in the CNCT console.
///
/// Every field has the value the hosted widget falls back to, so a server that predates a field —
/// or an inbox nobody has styled — still reads as something sensible rather than as nulls.
class CnctChatBrand {
  const CnctChatBrand({
    this.color = defaultColor,
    this.appearance = CnctAppearanceSetting.light,
    this.businessName,
    this.avatarUrl,
    this.language = CnctLanguageSetting.auto,
    this.showBranding = true,
  });

  factory CnctChatBrand.fromJson(Map<String, dynamic> json) {
    final color = json['color'];
    return CnctChatBrand(
      // Only a full `#rrggbb` is taken. Anything else is a value the console would not have saved,
      // and painting the send button an unparseable colour is worse than painting it ours.
      color: color is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color) ? color : defaultColor,
      appearance: CnctAppearanceSetting.parse(json['appearance']),
      businessName: _nonEmpty(json['businessName']),
      avatarUrl: _nonEmpty(json['avatarUrl']),
      language: CnctLanguageSetting.parse(json['language']),
      showBranding: json['showBranding'] as bool? ?? true,
    );
  }

  /// CNCT's own colour, for an inbox that has not chosen one.
  static const defaultColor = '#b52d93';

  /// `#rrggbb`. Always a valid one.
  final String color;
  final CnctAppearanceSetting appearance;

  /// Already folded into [CnctChatInbox.business] by the server; here for completeness.
  final String? businessName;

  /// The logo. Null means the business's first letter on its colour.
  final String? avatarUrl;
  final CnctLanguageSetting language;

  /// Whether the "Powered by CNCT" line shows.
  final bool showBranding;
}

/// What the business switched on for the conversation itself.
class CnctChatSettings {
  const CnctChatSettings({
    this.allowAttachments = true,
    this.allowEmoji = true,
    this.allowEndConversation = false,
    this.start = CnctChatStartMode.details,
    this.askForRating = true,
  });

  factory CnctChatSettings.fromJson(Map<String, dynamic> json) => CnctChatSettings(
        allowAttachments: json['allowAttachments'] as bool? ?? true,
        allowEmoji: json['allowEmoji'] as bool? ?? true,
        allowEndConversation: json['allowEndConversation'] as bool? ?? false,
        start: CnctChatStartMode.parse(json['start']),
        askForRating: json['askForRating'] as bool? ?? true,
      );

  /// Whether visitors may send files. The server refuses an upload with 403 when this is off, so a
  /// UI that hides the paperclip is only saying so first.
  final bool allowAttachments;
  final bool allowEmoji;

  /// Whether the visitor may end the conversation themselves.
  final bool allowEndConversation;
  final CnctChatStartMode start;

  /// Whether a closed conversation asks how it went.
  final bool askForRating;
}

/// The inbox's widget configuration, as the business set it in the CNCT console.
///
/// Merged section by section over the defaults, exactly as the server and the hosted widget merge
/// it — never a shallow copy, so a section the server sent half of keeps the rest of its defaults.
/// [raw] keeps everything as sent, including the sections this SDK has no model for (the hosted
/// widget's launcher and home screen).
class CnctChatWidgetConfig {
  const CnctChatWidgetConfig({
    this.brand = const CnctChatBrand(),
    this.chat = const CnctChatSettings(),
    this.raw = const {},
  });

  factory CnctChatWidgetConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CnctChatWidgetConfig();
    return CnctChatWidgetConfig(
      brand: CnctChatBrand.fromJson(_mapOf(json['brand'])),
      chat: CnctChatSettings.fromJson(_mapOf(json['chat'])),
      raw: json,
    );
  }

  final CnctChatBrand brand;
  final CnctChatSettings chat;
  final Map<String, dynamic> raw;
}

/// Whether the team is in, and what a visitor can expect if they write now.
class CnctChatAvailability {
  const CnctChatAvailability({
    this.open,
    this.opensAt,
    this.assistant = false,
    this.replyMinutes,
  });

  factory CnctChatAvailability.fromJson(Map<String, dynamic> json) => CnctChatAvailability(
        open: json['open'] as bool?,
        opensAt: DateTime.tryParse('${json['opensAt']}')?.toLocal(),
        assistant: json['assistant'] as bool? ?? false,
        replyMinutes: (json['replyMinutes'] as num?)?.toDouble(),
      );

  /// True inside opening hours, false outside them, and null for an inbox with no hours at all —
  /// in which case "in" and "out" would be a guess, and nothing should claim either.
  final bool? open;

  /// When the team is back, converted to the device's clock. Only while [open] is false.
  final DateTime? opensAt;

  /// Whether the assistant answers right now.
  final bool assistant;

  /// How fast replies have really come over the last month. Null without enough of a measurement
  /// to promise anything.
  final double? replyMinutes;
}

/// The inbox, as a visitor sees it before anybody has typed. Readable without a session — it is
/// the front door.
class CnctChatInbox {
  const CnctChatInbox({
    required this.business,
    required this.inbox,
    required this.isActive,
    required this.greeting,
    required this.requirePhone,
    this.widget = const CnctChatWidgetConfig(),
    this.team = const [],
    this.availability,
  });

  factory CnctChatInbox.fromJson(Map<String, dynamic> json) => CnctChatInbox(
        business: json['business'] as String? ?? '',
        inbox: json['inbox'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
        greeting: json['greeting'] as String? ?? '',
        requirePhone: json['requirePhone'] as bool? ?? false,
        widget: CnctChatWidgetConfig.fromJson(
          json['widget'] is Map ? _mapOf(json['widget']) : null,
        ),
        team: _listOf(json['team'])
            .map((item) => CnctChatSender.fromJson(item, fallbackKind: CnctSenderKind.person))
            .toList(growable: false),
        availability: json['availability'] is Map
            ? CnctChatAvailability.fromJson(_mapOf(json['availability']))
            : null,
      );

  /// The business's name, for your header.
  final String business;

  /// This inbox's name.
  final String inbox;

  /// **False means do not open the composer.** The inbox is switched off; a session start will be
  /// refused. Say so rather than letting somebody type into something that will not accept it.
  final bool isActive;

  /// What to show before the first message, in whatever language the business wrote it.
  final String greeting;

  /// True when this inbox wants a phone number before the conversation starts. Ask for it in your
  /// pre-chat step and pass it to `start(phone: …)` — it is what joins this visitor to the contact
  /// record the business already has.
  final bool requirePhone;

  /// How the business branded and configured its chat in the console.
  final CnctChatWidgetConfig widget;

  /// A few of the people who will answer: first names and faces, nothing more.
  final List<CnctChatSender> team;

  /// Whether the team is in. Null on a server that does not say.
  final CnctChatAvailability? availability;
}

// ── People ────────────────────────────────────────────────────────────────────────────────────────

/// Which kind of voice a [CnctChatSender] is.
enum CnctSenderKind {
  /// A person on the team.
  person,

  /// The business's assistant.
  ai,

  /// A shape this SDK has not met. Draw it as the business.
  unknown;

  static CnctSenderKind parse(Object? raw, {CnctSenderKind fallback = CnctSenderKind.unknown}) =>
      switch ('$raw') {
        'person' => CnctSenderKind.person,
        'ai' => CnctSenderKind.ai,
        _ => fallback,
      };
}

/// Who wrote a message, as much as a customer is told: a first name and a face.
///
/// [avatar] and [mascot] are keys into CNCT's own drawings — the face an operator picked for
/// themselves in the console, the assistant's mascot — not URLs. A UI without those drawings shows
/// the first letter of [name] instead, which is what the hosted widget does when a key is missing.
class CnctChatSender {
  const CnctChatSender({
    required this.kind,
    this.name,
    this.avatar,
    this.mascot,
    this.colour,
  });

  factory CnctChatSender.fromJson(
    Map<String, dynamic> json, {
    CnctSenderKind fallbackKind = CnctSenderKind.unknown,
  }) =>
      CnctChatSender(
        kind: CnctSenderKind.parse(json['kind'], fallback: fallbackKind),
        name: _nonEmpty(json['name']),
        avatar: _nonEmpty(json['avatar']),
        mascot: _nonEmpty(json['mascot']),
        colour: _nonEmpty(json['colour']),
      );

  final CnctSenderKind kind;

  /// A first name, or the assistant's name. Null for somebody the business did not name.
  final String? name;

  /// A person's face, as a key into CNCT's avatar set.
  final String? avatar;

  /// The assistant's mascot, as a key into CNCT's mascot set.
  final String? mascot;

  /// The assistant's colour, as a key.
  final String? colour;

  bool get isAssistant => kind == CnctSenderKind.ai;

  /// One comparable string for "the same voice", which is what decides where a run of bubbles
  /// starts and ends.
  String get identity => '${kind.name}:${name ?? ''}:${avatar ?? mascot ?? ''}';
}

/// The visitor, as the platform knows them.
class CnctChatVisitor {
  const CnctChatVisitor({
    required this.displayName,
    this.anonymous = false,
    this.identified = false,
  });

  factory CnctChatVisitor.fromJson(Map<String, dynamic> json) => CnctChatVisitor(
        displayName: json['displayName'] as String? ?? '',
        anonymous: json['anonymous'] as bool? ?? false,
        identified: json['identified'] as bool? ?? false,
      );

  final String displayName;

  /// True while the visitor has not given a name — the platform made one up (`Visitor 7KQ2`). The
  /// moment to ask for one, as the hosted widget does, is after they have said something.
  final bool anonymous;

  /// True when this visitor was signed in with `identify()`, as one of the business's own users.
  final bool identified;
}

// ── The conversation ──────────────────────────────────────────────────────────────────────────────

/// How a closed conversation was rated, worst (1) to best (5).
class CnctChatRating {
  const CnctChatRating({required this.score, this.comment, this.ratedAt});

  static CnctChatRating? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final json = _mapOf(raw);
    final score = json['score'];
    if (score is! num) return null;
    return CnctChatRating(
      score: score.toInt(),
      comment: _nonEmpty(json['comment']),
      ratedAt: DateTime.tryParse('${json['ratedAt']}')?.toLocal(),
    );
  }

  final int score;
  final String? comment;
  final DateTime? ratedAt;
}

/// One of the visitor's own conversations.
class CnctChatConversation {
  const CnctChatConversation({
    required this.status,
    required this.startedAt,
    required this.withPerson,
    this.id = '',
    this.closedAt,
    this.lastMessageAt,
    this.assignee,
    this.seenAt,
    this.ratable = false,
    this.rating,
    this.preview,
  });

  factory CnctChatConversation.fromJson(Map<String, dynamic> json) => CnctChatConversation(
        id: json['id'] as String? ?? '',
        status: CnctConversationStatus.parse(json['status']),
        startedAt: DateTime.tryParse('${json['startedAt']}')?.toLocal() ?? DateTime.now(),
        closedAt: DateTime.tryParse('${json['closedAt']}')?.toLocal(),
        lastMessageAt: DateTime.tryParse('${json['lastMessageAt']}')?.toLocal(),
        withPerson: json['withPerson'] as bool? ?? false,
        assignee: json['assignee'] is Map
            ? CnctChatSender.fromJson(_mapOf(json['assignee']), fallbackKind: CnctSenderKind.person)
            : null,
        seenAt: DateTime.tryParse('${json['seenAt']}')?.toLocal(),
        ratable: json['ratable'] as bool? ?? false,
        rating: CnctChatRating.tryFrom(json['rating']),
        preview: json['preview'] is Map ? CnctChatMessage.fromJson(_mapOf(json['preview'])) : null,
      );

  /// Empty on a server that predates conversation ids; everything that needs one says so.
  final String id;
  final CnctConversationStatus status;
  final DateTime startedAt;
  final DateTime? closedAt;
  final DateTime? lastMessageAt;

  /// True when somebody from the team is on this thread.
  final bool withPerson;

  /// The person it is assigned to, by first name and face, where the business shows that.
  final CnctChatSender? assignee;

  /// When the team last read the visitor's messages. A visitor message at or before this has been
  /// seen — the "Seen" under their last words.
  final DateTime? seenAt;

  /// Whether `rate()` will be accepted. A conversation can be rated once it is closed, for a while.
  final bool ratable;
  final CnctChatRating? rating;

  /// The last thing said, on a row from `conversations()`. Null elsewhere.
  final CnctChatMessage? preview;

  bool get isClosed => status == CnctConversationStatus.closed;

  /// True when [message], one of the visitor's, has been read by the team.
  bool hasSeen(CnctChatMessage message) {
    final at = seenAt;
    return at != null && !at.isBefore(message.createdAt);
  }

  CnctChatConversation copyWith({
    CnctConversationStatus? status,
    DateTime? closedAt,
    bool? withPerson,
    CnctChatSender? assignee,
    bool clearAssignee = false,
    DateTime? seenAt,
    bool? ratable,
    CnctChatRating? rating,
  }) =>
      CnctChatConversation(
        id: id,
        status: status ?? this.status,
        startedAt: startedAt,
        closedAt: closedAt ?? this.closedAt,
        lastMessageAt: lastMessageAt,
        withPerson: withPerson ?? this.withPerson,
        assignee: clearAssignee ? null : (assignee ?? this.assignee),
        seenAt: seenAt ?? this.seenAt,
        ratable: ratable ?? this.ratable,
        rating: rating ?? this.rating,
        preview: preview,
      );
}

/// The visitor's conversations, newest first, as `conversations()` answers.
class CnctChatConversations {
  const CnctChatConversations({required this.conversations, this.visitor});

  final List<CnctChatConversation> conversations;
  final CnctChatVisitor? visitor;

  /// The one still open, if any. A visitor has at most one at a time — the server's rule.
  CnctChatConversation? get live {
    for (final conversation in conversations) {
      if (!conversation.isClosed) return conversation;
    }
    return null;
  }
}

/// One conversation with everything said in it, as `conversation(id)` answers.
class CnctChatTranscript {
  const CnctChatTranscript({required this.conversation, required this.messages, this.visitor});

  final CnctChatConversation conversation;

  /// Oldest first.
  final List<CnctChatMessage> messages;
  final CnctChatVisitor? visitor;
}

// ── Cards ─────────────────────────────────────────────────────────────────────────────────────────

/// A ticket raised out of this conversation, where the inbox publishes them.
///
/// Off by default per inbox: a business that files a ticket for every awkward question has not
/// thereby agreed to tell the customer a case was opened.
class CnctTicketCard {
  const CnctTicketCard({
    required this.ticketNumber,
    required this.title,
    required this.status,
    required this.raisedAt,
  });

  static CnctTicketCard? tryFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final number = data['ticketNumber'];
    if (number is! num) return null;
    return CnctTicketCard(
      ticketNumber: number.toInt(),
      title: data['title'] as String? ?? '',
      status: data['status'] as String? ?? '',
      raisedAt: DateTime.tryParse('${data['raisedAt']}')?.toLocal(),
    );
  }

  /// What a customer quotes back to you.
  final int ticketNumber;
  final String title;

  /// `OPEN`, `RESOLVED`, and the rest of the lifecycle. A string rather than an enum on purpose:
  /// the lifecycle is per account and a closed enum here would turn a client adding a status into
  /// a crash in somebody's app.
  final String status;
  final DateTime? raisedAt;
}

/// A booking taken, moved or cancelled in this conversation, where the inbox publishes them.
///
/// All three moments arrive, not just the first — a card that announces an appointment and goes
/// quiet when it moves leaves a stale time on a screen the customer has every reason to trust.
class CnctBookingCard {
  const CnctBookingCard({
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.locationName,
    required this.partySize,
  });

  static CnctBookingCard? tryFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final startsAt = DateTime.tryParse('${data['startsAt']}');
    if (startsAt == null) return null;
    return CnctBookingCard(
      title: data['title'] as String? ?? '',
      startsAt: startsAt.toLocal(),
      endsAt: DateTime.tryParse('${data['endsAt']}')?.toLocal(),
      status: data['status'] as String? ?? '',
      locationName: data['locationName'] as String?,
      partySize: (data['partySize'] as num?)?.toInt(),
    );
  }

  /// The service, or the booking's own title where there is no service.
  final String title;

  /// **Render this in the customer's locale, not the business's.** It arrives as an instant and is
  /// converted to the device's zone here.
  final DateTime startsAt;
  final DateTime? endsAt;
  final String status;

  /// Where to go. Null where the business has one location.
  final String? locationName;

  /// Null unless the booking took one.
  final int? partySize;
}

// ── Files ─────────────────────────────────────────────────────────────────────────────────────────

/// A file sent with a message. Only files the platform actually holds are published, so anything in
/// this list can be fetched — with `downloadAttachment(id)`, which carries the visitor's token.
class CnctChatAttachment {
  const CnctChatAttachment({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.filename,
    required this.bytes,
  });

  factory CnctChatAttachment.fromJson(Map<String, dynamic> json) => CnctChatAttachment(
        id: json['id'] as String? ?? '',
        kind: CnctAttachmentKind.parse(json['kind']),
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        filename: json['filename'] as String?,
        bytes: (json['bytes'] as num?)?.toInt(),
      );

  final String id;
  final CnctAttachmentKind kind;
  final String mimeType;
  final String? filename;

  /// Size in bytes, where the platform recorded one.
  final int? bytes;

  /// True for a picture to show inline rather than a file to open.
  bool get isImage => kind == CnctAttachmentKind.image || mimeType.startsWith('image/');

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wireName,
        'mimeType': mimeType,
        'filename': filename,
        'bytes': bytes,
      };
}

// ── Flows ─────────────────────────────────────────────────────────────────────────────────────────

/// How a flow wants its choices drawn.
enum CnctFlowLayout {
  /// A few short pills.
  buttons,

  /// Rows, for choices with descriptions or too many to fit as pills.
  list;

  static CnctFlowLayout parse(Object? raw) =>
      '$raw' == 'list' ? CnctFlowLayout.list : CnctFlowLayout.buttons;
}

/// The kind of answer a flow is waiting for — which decides the keyboard.
enum CnctFlowExpects {
  name,
  number,
  email,
  phone,
  date;

  static CnctFlowExpects? parse(Object? raw) {
    for (final value in CnctFlowExpects.values) {
      if (value.name == '$raw') return value;
    }
    return null;
  }
}

/// One choice a flow offers. Tapping it sends [title] as the visitor's words with [id] as the
/// message's `replyId` — see `CnctChatClient.choose`.
class CnctFlowChoice {
  const CnctFlowChoice({required this.id, required this.title, this.description});

  static CnctFlowChoice? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final json = _mapOf(raw);
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    return CnctFlowChoice(id: id, title: title, description: _nonEmpty(json['description']));
  }

  final String id;
  final String title;
  final String? description;
}

/// A picture, film or document a flow puts above its words. [url] is public: it needs no token.
class CnctFlowMedia {
  const CnctFlowMedia({required this.kind, required this.url, this.filename});

  static CnctFlowMedia? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final json = _mapOf(raw);
    final url = Uri.tryParse('${json['url']}');
    // Only ever an http(s) address: anything else in a stranger-facing bubble is a trick.
    if (url == null || (url.scheme != 'http' && url.scheme != 'https')) return null;
    return CnctFlowMedia(
      kind: CnctAttachmentKind.parse(json['kind']),
      url: url,
      filename: _nonEmpty(json['filename']),
    );
  }

  final CnctAttachmentKind kind;
  final Uri url;
  final String? filename;
}

/// An assistant's structured message: words, choices, and what it is waiting for.
///
/// A flow message's `body` is numbered text — "1. Book a visit … Reply with the number" — because
/// that reads correctly anywhere that knows nothing of flows. A UI that does know draws [text],
/// [media] and [footer] itself and puts [choices] under the thread as buttons.
class CnctChatFlow {
  const CnctChatFlow({
    this.text,
    this.layout = CnctFlowLayout.buttons,
    this.choices = const [],
    this.footer,
    this.listButton,
    this.media,
    this.expects,
  });

  static CnctChatFlow? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final json = _mapOf(raw);
    return CnctChatFlow(
      text: json['text'] as String?,
      layout: CnctFlowLayout.parse(json['layout']),
      choices: (json['choices'] as List<Object?>? ?? const [])
          .map(CnctFlowChoice.tryFrom)
          .whereType<CnctFlowChoice>()
          .toList(growable: false),
      footer: _nonEmpty(json['footer']),
      listButton: _nonEmpty(json['listButton']),
      media: CnctFlowMedia.tryFrom(json['media']),
      expects: CnctFlowExpects.parse(json['expects']),
    );
  }

  /// The words, without the numbered choices. Null on a message stored before the server sent
  /// them, in which case `body` is what to show.
  final String? text;
  final CnctFlowLayout layout;
  final List<CnctFlowChoice> choices;
  final String? footer;

  /// The label a list of choices goes under.
  final String? listButton;
  final CnctFlowMedia? media;

  /// What a typed answer should be. Null when the flow is not waiting for one.
  final CnctFlowExpects? expects;
}

/// An earlier message this one replies to, as the server snapshotted it.
class CnctChatQuote {
  const CnctChatQuote({this.messageId, this.mine = false, this.excerpt, this.attachmentKind});

  static CnctChatQuote? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final json = _mapOf(raw);
    return CnctChatQuote(
      messageId: _nonEmpty(json['messageId']),
      mine: json['mine'] as bool? ?? false,
      excerpt: _nonEmpty(json['excerpt']),
      attachmentKind:
          json['attachmentKind'] == null ? null : CnctAttachmentKind.parse(json['attachmentKind']),
    );
  }

  /// The quoted message's id, when it is still in the thread to scroll to.
  final String? messageId;

  /// True when the quoted message was the visitor's own.
  final bool mine;

  /// Its first words. Null for a file with no words.
  final String? excerpt;

  /// What kind of file it was, when it was one.
  final CnctAttachmentKind? attachmentKind;
}

// ── Messages ──────────────────────────────────────────────────────────────────────────────────────

/// One message in the transcript.
class CnctChatMessage {
  const CnctChatMessage({
    required this.id,
    required this.speaker,
    required this.type,
    required this.rawType,
    required this.body,
    required this.createdAt,
    this.data,
    this.clientKey,
    this.sender,
    this.flow,
    this.suggestions = const [],
    this.replyTo,
    this.attachments = const [],
    this.replyId,
    this.pending = false,
    this.failed = false,
  });

  factory CnctChatMessage.fromJson(Map<String, dynamic> json) {
    final raw = '${json['type'] ?? 'TEXT'}';
    return CnctChatMessage(
      id: json['id'] as String? ?? '',
      speaker: CnctSpeaker.parse(json['speaker']),
      type: CnctMessageType.parse(raw),
      rawType: raw,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal() ?? DateTime.now(),
      data: json['data'] is Map ? _mapOf(json['data']) : null,
      clientKey: json['clientKey'] as String?,
      sender: json['sender'] is Map ? CnctChatSender.fromJson(_mapOf(json['sender'])) : null,
      flow: CnctChatFlow.tryFrom(json['flow']),
      suggestions: (json['suggestions'] as List<Object?>? ?? const [])
          .whereType<String>()
          .where((suggestion) => suggestion.trim().isNotEmpty)
          .take(3)
          .toList(growable: false),
      replyTo: CnctChatQuote.tryFrom(json['replyTo']),
      attachments:
          _listOf(json['attachments']).map(CnctChatAttachment.fromJson).toList(growable: false),
    );
  }

  /// A bubble drawn the moment somebody pressed send, before the server has it. Replaced in place
  /// by the stored row, matched on [clientKey].
  factory CnctChatMessage.optimistic({
    required String clientKey,
    required String body,
    List<CnctChatAttachment> attachments = const [],
    String? replyId,
  }) =>
      CnctChatMessage(
        id: 'pending_$clientKey',
        speaker: CnctSpeaker.caller,
        type: CnctMessageType.text,
        rawType: 'TEXT',
        body: body,
        createdAt: DateTime.now(),
        clientKey: clientKey,
        attachments: attachments,
        replyId: replyId,
        pending: true,
      );

  final String id;
  final CnctSpeaker speaker;

  /// What to render this as. Unrecognised card types arrive as [CnctMessageType.other]; [body] is
  /// always safe to show.
  final CnctMessageType type;

  /// The type exactly as the server named it, for the cards this SDK version has not met.
  final String rawType;

  /// **Always reads correctly on its own**, card or not. This is the field a `default` branch shows.
  final String body;
  final DateTime createdAt;

  /// A card's fields, allowlisted by the server. Null on ordinary text.
  final Map<String, dynamic>? data;

  /// The visitor's own idempotency key, handed back so an optimistic bubble can be retired. Only
  /// ever present on the visitor's own messages — an operator's key is none of a visitor's business.
  final String? clientKey;

  /// Who wrote it, for the face and first name beside a reply. Null for the visitor's own messages
  /// and the platform's lines, and for a reply the business signs as itself.
  final CnctChatSender? sender;

  /// The assistant's structured message, when this is one.
  final CnctChatFlow? flow;

  /// Up to three short replies the assistant offers, to show as chips. Tapping one sends it.
  final List<String> suggestions;

  /// The earlier message this one quotes.
  final CnctChatQuote? replyTo;

  final List<CnctChatAttachment> attachments;

  /// The flow choice this message answers. Only on the visitor's own messages while they are in
  /// flight — the server keeps it only if the conversation was offered that choice.
  final String? replyId;

  /// In flight. Draw it, greyed.
  final bool pending;

  /// The send failed. Offer a retry button wired to `CnctChatClient.retry(message.clientKey!)` —
  /// retrying cannot double-post.
  final bool failed;

  /// The ticket card, when this is one. Null otherwise.
  CnctTicketCard? get ticket =>
      type == CnctMessageType.ticketUpdate ? CnctTicketCard.tryFrom(data) : null;

  /// The booking card, when this is one. Null otherwise.
  CnctBookingCard? get booking =>
      type == CnctMessageType.bookingUpdate ? CnctBookingCard.tryFrom(data) : null;

  /// True when [flow] carries its own words, so a UI should draw those rather than [body].
  bool get drawsAsFlow => flow?.text != null;

  /// The words a person reads: a flow's own text where it has one, otherwise [body].
  String get words => drawsAsFlow ? flow!.text! : body;

  /// True for the visitor's own words.
  bool get isMine => speaker == CnctSpeaker.caller;

  CnctChatMessage copyWith({bool? pending, bool? failed}) => CnctChatMessage(
        id: id,
        speaker: speaker,
        type: type,
        rawType: rawType,
        body: body,
        createdAt: createdAt,
        data: data,
        clientKey: clientKey,
        sender: sender,
        flow: flow,
        suggestions: suggestions,
        replyTo: replyTo,
        attachments: attachments,
        replyId: replyId,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );

  @override
  String toString() => 'CnctChatMessage(${speaker.name}, $rawType, "$body")';
}

// ── Signing in ────────────────────────────────────────────────────────────────────────────────────

/// One of the business's own users, signed in with a hash only the business's server can make.
///
/// [userHash] is `HMAC-SHA256(userId, the inbox's identity secret)` in lowercase hex, **computed on
/// the business's own server**. The secret never goes in an app: an app holding it can sign in as
/// anybody, and every customer's conversations would be one decompiled binary away.
class CnctChatIdentity {
  const CnctChatIdentity({
    required this.userId,
    required this.userHash,
    this.name,
    this.email,
    this.phone,
  });

  final String userId;
  final String userHash;
  final String? name;
  final String? email;
  final String? phone;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userHash': userHash,
        if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
        if (email != null && email!.trim().isNotEmpty) 'email': email!.trim(),
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
      };
}

// ── Decoding ──────────────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _mapOf(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

/// Only the entries that are objects. A list with a stray null or a string in it is decoded around,
/// not refused — responses are allowlisted on the server and decoded leniently here.
List<Map<String, dynamic>> _listOf(Object? value) => value is List
    ? value.whereType<Map<Object?, Object?>>().map(_mapOf).toList(growable: false)
    : const [];

String? _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
