/// Who said it.
enum CnctSpeaker {
  /// The visitor — the person using your app.
  caller,

  /// The assistant.
  ai,

  /// A human on the business's side. Never named: the platform publishes that somebody is with you,
  /// never who, and this SDK cannot show you what it is not sent.
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

  static CnctAttachmentKind parse(Object? raw) => switch ('$raw') {
        'IMAGE' => CnctAttachmentKind.image,
        'VIDEO' => CnctAttachmentKind.video,
        'AUDIO' => CnctAttachmentKind.audio,
        'DOCUMENT' => CnctAttachmentKind.document,
        'STICKER' => CnctAttachmentKind.sticker,
        _ => CnctAttachmentKind.other,
      };
}

/// What the inbox says before anybody has typed. Readable without a session — it is the front door.
class CnctChatInbox {
  const CnctChatInbox({
    required this.business,
    required this.inbox,
    required this.isActive,
    required this.greeting,
    required this.requirePhone,
  });

  factory CnctChatInbox.fromJson(Map<String, dynamic> json) => CnctChatInbox(
        business: json['business'] as String? ?? '',
        inbox: json['inbox'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
        greeting: json['greeting'] as String? ?? '',
        requirePhone: json['requirePhone'] as bool? ?? false,
      );

  /// The business's name, for your header.
  final String business;

  /// This inbox's name.
  final String inbox;

  /// **False means do not open the composer.** The inbox is switched off; a session start will be
  /// refused. Say so rather than letting somebody type into something that will not accept it.
  final bool isActive;

  /// What to show before the first message.
  final String greeting;

  /// True when this inbox wants a phone number before the conversation starts. Ask for it in your
  /// pre-chat step and pass it to `start(phone: …)` — it is what joins this visitor to the contact
  /// record the business already has.
  final bool requirePhone;
}

/// The state of the visitor's own conversation.
class CnctChatConversation {
  const CnctChatConversation({
    required this.status,
    required this.startedAt,
    required this.withPerson,
  });

  factory CnctChatConversation.fromJson(Map<String, dynamic> json) => CnctChatConversation(
        status: CnctConversationStatus.parse(json['status']),
        startedAt: DateTime.tryParse('${json['startedAt']}')?.toLocal() ?? DateTime.now(),
        withPerson: json['withPerson'] as bool? ?? false,
      );

  final CnctConversationStatus status;
  final DateTime startedAt;

  /// True when somebody — an operator or the assistant — is on this thread. **Never who.** The
  /// platform does not publish a colleague's name to a customer, so "Sara is typing" is not
  /// something this SDK can offer and not something it will pretend to.
  final bool withPerson;
}

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

/// A file sent with a message. Only files the platform actually holds are published, so anything in
/// this list can be fetched.
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
}

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
    this.attachments = const [],
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
      data: (json['data'] as Map<Object?, Object?>?)?.cast<String, dynamic>(),
      clientKey: json['clientKey'] as String?,
      attachments: ((json['attachments'] as List<Object?>?) ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((item) => CnctChatAttachment.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  /// A bubble drawn the moment somebody pressed send, before the server has it. Replaced in place
  /// by the stored row, matched on [clientKey].
  factory CnctChatMessage.optimistic({required String clientKey, required String body}) =>
      CnctChatMessage(
        id: 'pending_$clientKey',
        speaker: CnctSpeaker.caller,
        type: CnctMessageType.text,
        rawType: 'TEXT',
        body: body,
        createdAt: DateTime.now(),
        clientKey: clientKey,
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

  final List<CnctChatAttachment> attachments;

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

  CnctChatMessage copyWith({bool? pending, bool? failed}) => CnctChatMessage(
        id: id,
        speaker: speaker,
        type: type,
        rawType: rawType,
        body: body,
        createdAt: createdAt,
        data: data,
        clientKey: clientKey,
        attachments: attachments,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );

  @override
  String toString() => 'CnctChatMessage(${speaker.name}, $rawType, "$body")';
}

/// The visitor, as the platform knows them. A display name and nothing else: this SDK is not told
/// which contact record they resolved to, and a customer-facing app has no use for one.
class CnctChatVisitor {
  const CnctChatVisitor({required this.displayName});

  factory CnctChatVisitor.fromJson(Map<String, dynamic> json) =>
      CnctChatVisitor(displayName: json['displayName'] as String? ?? '');

  final String displayName;
}
