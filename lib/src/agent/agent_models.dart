/// One of the operations the account's credential may perform, as the platform advertises it.
///
/// The catalogue is filtered per account — a client without ticketing is not shown four tools that
/// would refuse — so read it rather than assuming. A catalogue is a promise, and something that has
/// read one will try to keep it.
class CnctTool {
  const CnctTool({required this.name, required this.description, required this.parameters});

  factory CnctTool.fromJson(Map<String, dynamic> json) => CnctTool(
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        parameters: (json['parameters'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ??
            (json['inputSchema'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ??
            const {},
      );

  final String name;
  final String description;

  /// JSON Schema for the arguments.
  final Map<String, dynamic> parameters;
}

/// The booking rules this account works under: its clock, its week, its services and what it will
/// let a caller ask for.
///
/// Worth fetching once at startup and showing: the hours are the difference between an app that
/// offers a time and one that offers a time the business will accept.
class CnctBookingRules {
  const CnctBookingRules({
    required this.timezone,
    required this.capacity,
    required this.slotMinutes,
    required this.services,
    required this.resources,
    required this.raw,
  });

  factory CnctBookingRules.fromJson(Map<String, dynamic> json) => CnctBookingRules(
        timezone: json['timezone'] as String? ?? 'UTC',
        capacity: (json['capacity'] as num?)?.toInt() ?? 0,
        slotMinutes: (json['slotMinutes'] as num?)?.toInt() ?? 0,
        services: ((json['services'] as List<Object?>?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((item) => CnctService.fromRules(item.cast<String, dynamic>()))
            .toList(growable: false),
        resources: ((json['resources'] as List<Object?>?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((item) => CnctBookableResource.fromRules(item.cast<String, dynamic>()))
            .toList(growable: false),
        raw: json,
      );

  /// The business's clock. Every human-readable time this API returns is already in it.
  final String timezone;
  final int capacity;

  /// The step between offered start times.
  final int slotMinutes;
  final List<CnctService> services;
  final List<CnctBookableResource> resources;

  /// Everything, unmodelled — `hours`, `locations`, `policy`. Exposed raw rather than pinned to a
  /// shape this SDK would have to break to widen: the parts above are the ones an app renders, and
  /// the rest is here when you need it.
  final Map<String, dynamic> raw;
}

/// Something the business can be booked for.
class CnctService {
  const CnctService({
    required this.serviceId,
    required this.name,
    required this.minutes,
    required this.description,
  });

  factory CnctService.fromJson(Map<String, dynamic> json) => CnctService(
        serviceId: json['serviceId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        minutes: (json['minutes'] as num?)?.toInt(),
        description: json['description'] as String?,
      );

  /// The same thing under the keys `GET /api/booking-tools` uses for it.
  factory CnctService.fromRules(Map<String, dynamic> json) => CnctService(
        serviceId: json['id'] as String? ?? json['serviceId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        minutes: (json['durationMinutes'] as num?)?.toInt() ?? (json['minutes'] as num?)?.toInt(),
        description: json['description'] as String?,
      );

  final String serviceId;
  final String name;

  /// How long it takes. Null where the business books generically.
  final int? minutes;
  final String? description;
}

/// A named person or table that can be asked for.
///
/// An empty list is a real answer rather than a missing one: a business that assigns whoever is free
/// has switched named preference off deliberately, and an app must not offer a choice it has been
/// told not to offer.
class CnctBookableResource {
  const CnctBookableResource({
    required this.resourceId,
    required this.name,
    required this.kind,
    required this.seats,
  });

  factory CnctBookableResource.fromJson(Map<String, dynamic> json) => CnctBookableResource(
        resourceId: json['resourceId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String?,
        seats: (json['seats'] as num?)?.toInt(),
      );

  factory CnctBookableResource.fromRules(Map<String, dynamic> json) => CnctBookableResource(
        resourceId: json['id'] as String? ?? json['resourceId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: (json['kind'] as String?)?.toLowerCase(),
        seats: (json['seats'] as num?)?.toInt(),
      );

  final String resourceId;
  final String name;

  /// `person`, `table`, `room`… lower-cased by the platform.
  final String? kind;
  final int? seats;
}

/// A free time.
class CnctSlot {
  const CnctSlot({required this.time, required this.startsAt, required this.resourceName});

  factory CnctSlot.fromJson(Map<String, dynamic> json) => CnctSlot(
        time: json['time'] as String? ?? '',
        startsAt: '${json['startsAt'] ?? ''}',
        resourceName: json['with'] as String?,
      );

  /// The label to show — already in the business's clock, e.g. "19:30".
  final String time;

  /// **Pass this back exactly as given.** It is the token `book` matches a slot on; reformatting it,
  /// or rebuilding it from a parsed `DateTime`, is how a booking lands on a time that was never
  /// offered. [startsAtUtc] is for display arithmetic only.
  final String startsAt;

  /// Who or what is free then. Only present when a specific person or table was asked for.
  final String? resourceName;

  /// The instant, parsed. Convenient for sorting and grouping; never send it back — send [startsAt].
  DateTime? get startsAtUtc => DateTime.tryParse(startsAt);
}

/// What a day looks like.
class CnctAvailability {
  const CnctAvailability({required this.date, required this.free, required this.note});

  factory CnctAvailability.fromJson(Map<String, dynamic> json) => CnctAvailability(
        date: json['date'] as String? ?? '',
        free: ((json['free'] as List<Object?>?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((item) => CnctSlot.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false),
        note: json['note'] as String?,
      );

  final String date;

  /// Empty means closed or full. [note] says which, and it is worth showing: "nothing is free" and
  /// "no table seats six" send a customer to different places.
  final List<CnctSlot> free;
  final String? note;

  bool get isEmpty => free.isEmpty;
}

/// A booking that now exists.
class CnctBookingConfirmation {
  const CnctBookingConfirmation({
    required this.bookingId,
    required this.when,
    required this.name,
    required this.partySize,
    required this.resourceName,
    this.sandbox = false,
  });

  factory CnctBookingConfirmation.fromJson(Map<String, dynamic> json) => CnctBookingConfirmation(
        bookingId: json['bookingId'] as String? ?? '',
        when: json['when'] as String? ?? '',
        name: json['name'] as String?,
        partySize: (json['partySize'] as num?)?.toInt(),
        resourceName: json['with'] as String?,
        sandbox: json['sandbox'] as bool? ?? false,
      );

  /// True when a sandbox key made it: it is kept so it can be found, moved and cancelled, but it
  /// holds no slot, nobody was told, and the business will never see it.
  final bool sandbox;

  final String bookingId;

  /// In the business's clock and its words — "Tuesday 12 August at 19:30". Ready to read back.
  final String when;

  /// The name the booking is under, which is not always the customer's.
  final String? name;
  final int? partySize;

  /// The person or table allocated, where the business names them.
  final String? resourceName;
}

/// One of a customer's upcoming bookings.
class CnctBookingSummary {
  const CnctBookingSummary({
    required this.bookingId,
    required this.when,
    required this.name,
    required this.partySize,
  });

  factory CnctBookingSummary.fromJson(Map<String, dynamic> json) => CnctBookingSummary(
        bookingId: json['bookingId'] as String? ?? '',
        when: json['when'] as String? ?? '',
        name: json['name'] as String?,
        partySize: (json['partySize'] as num?)?.toInt(),
      );

  final String bookingId;
  final String when;
  final String? name;
  final int? partySize;
}

/// A kind of work the business hands over.
class CnctTicketType {
  const CnctTicketType({required this.ticketTypeId, required this.name, required this.description});

  factory CnctTicketType.fromJson(Map<String, dynamic> json) => CnctTicketType(
        ticketTypeId: json['ticketTypeId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
      );

  final String ticketTypeId;
  final String name;
  final String? description;
}

/// One field a ticket type still needs.
class CnctTicketField {
  const CnctTicketField({
    required this.key,
    required this.isRequired,
    required this.question,
    required this.mustBeOneOf,
  });

  factory CnctTicketField.fromJson(Map<String, dynamic> json) => CnctTicketField(
        key: json['key'] as String? ?? '',
        isRequired: json['required'] as bool? ?? false,
        question: json['question'] as String? ?? '',
        mustBeOneOf: ((json['mustBeOneOf'] as List<Object?>?) ?? const [])
            .map((item) => '$item')
            .toList(growable: false),
      );

  /// Use this exact key in `fields` when raising the ticket. Never invent one.
  final String key;
  final bool isRequired;

  /// Already phrased as a question, so it can go straight on a form label.
  final String question;

  /// When non-empty, the only accepted values.
  final List<String> mustBeOneOf;
}

/// What one ticket type needs before it can be raised.
class CnctTicketTypeDetail {
  const CnctTicketTypeDetail({
    required this.ticketTypeId,
    required this.name,
    required this.alreadyKnown,
    required this.askFor,
  });

  factory CnctTicketTypeDetail.fromJson(Map<String, dynamic> json) => CnctTicketTypeDetail(
        ticketTypeId: json['ticketTypeId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        alreadyKnown:
            (json['alreadyKnown'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? const {},
        askFor: ((json['askFor'] as List<Object?>?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((item) => CnctTicketField.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false),
      );

  final String ticketTypeId;
  final String name;

  /// What the platform already has for this customer. Do not ask for these again.
  final Map<String, dynamic> alreadyKnown;

  /// What is still missing. The subtraction is done on the server, so this list is exactly the
  /// questions worth putting in front of somebody.
  final List<CnctTicketField> askFor;
}

/// A ticket that now exists.
class CnctRaisedTicket {
  const CnctRaisedTicket({required this.ticketNumber, required this.note, this.sandbox = false});

  factory CnctRaisedTicket.fromJson(Map<String, dynamic> json) => CnctRaisedTicket(
        ticketNumber: (json['ticketNumber'] as num?)?.toInt() ?? 0,
        note: json['note'] as String?,
        sandbox: json['sandbox'] as bool? ?? false,
      );

  /// What a customer quotes back. A sandbox has its own numbering, from 1.
  final int ticketNumber;
  final String? note;

  /// True when a sandbox key raised it: it is in no queue and nobody will work it.
  final bool sandbox;
}

/// One of a customer's tickets.
class CnctTicketSummary {
  const CnctTicketSummary({
    required this.ticketNumber,
    required this.title,
    required this.status,
    required this.raised,
  });

  factory CnctTicketSummary.fromJson(Map<String, dynamic> json) => CnctTicketSummary(
        ticketNumber: (json['ticketNumber'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? '',
        raised: json['raised'] as String?,
      );

  final int ticketNumber;
  final String title;
  final String status;

  /// The date it was raised, `YYYY-MM-DD`.
  final String? raised;
}

/// One line of a ticket's story, in words a customer can be told. Never who did it.
class CnctTicketMilestone {
  const CnctTicketMilestone({required this.on, required this.what});

  factory CnctTicketMilestone.fromJson(Map<String, dynamic> json) => CnctTicketMilestone(
        on: json['on'] as String? ?? '',
        what: json['what'] as String? ?? '',
      );

  /// `YYYY-MM-DD`.
  final String on;

  /// "Raised", "Being worked on", "Waiting on the customer", "The customer added: …".
  final String what;
}

/// One of a ticket type's own fields, as it was filled in, labelled by its display name.
class CnctTicketDetailField {
  const CnctTicketDetailField({required this.name, required this.value});

  factory CnctTicketDetailField.fromJson(Map<String, dynamic> json) => CnctTicketDetailField(
        name: json['name'] as String? ?? '',
        value: json['value'],
      );

  final String name;
  final Object? value;
}

/// One of a customer's tickets, as the customer may see it.
///
/// What is missing is deliberate: no person's name anywhere, no team, and none of the notes a
/// business writes for its own staff. It is safe to show to the customer it belongs to — and only
/// to them.
class CnctTicketDetail {
  const CnctTicketDetail({
    required this.ticketNumber,
    required this.title,
    required this.kind,
    required this.status,
    required this.waitingOnCustomer,
    required this.raised,
    required this.resolved,
    required this.closed,
    required this.customerRequest,
    required this.desiredOutcome,
    required this.details,
    required this.history,
    required this.note,
  });

  factory CnctTicketDetail.fromJson(Map<String, dynamic> json) => CnctTicketDetail(
        ticketNumber: (json['ticketNumber'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        kind: json['kind'] as String?,
        status: json['status'] as String? ?? '',
        waitingOnCustomer: json['waitingOnCustomer'] as bool? ?? false,
        raised: json['raised'] as String?,
        resolved: json['resolved'] as String?,
        closed: json['closed'] as String?,
        customerRequest: json['customerRequest'] as String?,
        desiredOutcome: json['desiredOutcome'] as String?,
        details: ((json['details'] as List<Object?>?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((item) => CnctTicketDetailField.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false),
        history: ((json['history'] as List<Object?>?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((item) => CnctTicketMilestone.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false),
        note: json['note'] as String?,
      );

  final int ticketNumber;
  final String title;

  /// The kind of work, by the business's own name for it.
  final String? kind;

  /// `OPEN`, `IN_PROGRESS`, `WAITING`, `RESOLVED`, `CLOSED` or `CANCELLED`.
  final String status;

  /// True when the business is waiting on the customer — for an answer, a photo, a time. Ask them
  /// what is needed and pass it on with [CnctTickets.addTo], which starts the ticket moving again.
  final bool waitingOnCustomer;

  /// `YYYY-MM-DD`.
  final String? raised;
  final String? resolved;
  final String? closed;
  final String? customerRequest;
  final String? desiredOutcome;

  /// The ticket type's own fields, labelled by their display names.
  final List<CnctTicketDetailField> details;
  final List<CnctTicketMilestone> history;

  /// How to talk about it — worth following, it is written for exactly that.
  final String? note;
}

/// What happened to a follow-up passed on with [CnctTickets.addTo].
class CnctTicketFollowUp {
  const CnctTicketFollowUp({required this.ticketNumber, required this.resumed, required this.note});

  factory CnctTicketFollowUp.fromJson(Map<String, dynamic> json) => CnctTicketFollowUp(
        ticketNumber: (json['ticketNumber'] as num?)?.toInt() ?? 0,
        resumed: json['resumed'] as bool? ?? false,
        note: json['note'] as String?,
      );

  final int ticketNumber;

  /// True when the ticket was waiting on the customer and is now being worked on again.
  final bool resumed;
  final String? note;
}

/// A list, plus what the platform said about it.
///
/// The note is not decoration: an empty list of people means "this business assigns whoever is
/// free — never offer a choice", and an empty list of times means the day is closed, or full, or
/// that no table seats six. Dropping the sentence loses the difference.
class CnctListing<T> {
  const CnctListing({required this.items, required this.note, this.refusal});

  final List<T> items;
  final String? note;

  /// Present when the platform refused rather than answered — no ticket types configured, say. The
  /// list will be empty.
  final String? refusal;

  bool get isEmpty => items.isEmpty;
  int get length => items.length;
}
