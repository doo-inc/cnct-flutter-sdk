import '../config.dart';
import '../credentials.dart';
import '../exception.dart';
import '../transport.dart';
import 'agent_models.dart';

/// The account's own operations — bookings and tickets — against the API key CNCT issued you.
///
/// **This credential is account-wide. Keep it on a server.** Everything here reads and writes on
/// behalf of the whole account, and the customer each call is about is named by phone number rather
/// than inferred from a session. An app that held this key could book for, and cancel, anybody.
/// The intended shape is: your app talks to your backend, your backend holds the key and uses this.
///
/// ```dart
/// final agent = CnctAgentClient(
///   config: CnctConfig(baseUrl: CnctHosts.development),
///   credentials: CnctApiKey(Platform.environment['CNCT_API_KEY']!),
/// );
/// final day = await agent.bookings.checkAvailability(date: '2026-09-12', partySize: 4);
/// if (day.free.isNotEmpty) {
///   await agent.bookings.create(
///     startsAt: day.free.first.startsAt,   // exactly as given
///     customerPhone: '+97312345678',
///     name: 'Layla',
///   );
/// }
/// ```
class CnctAgentClient {
  CnctAgentClient({
    required CnctConfig config,
    required CnctApiKey credentials,
    CnctTransport? transport,
  })  : _transport = transport ?? CnctTransport(config: config),
        _headers = credentials.headers {
    bookings = CnctBookings._(this);
    tickets = CnctTickets._(this);
  }

  final CnctTransport _transport;
  final Map<String, String> _headers;

  /// The calendar.
  late final CnctBookings bookings;

  /// Tickets — the work a business hands to a colleague.
  late final CnctTickets tickets;

  /// Release the HTTP client.
  void close() => _transport.close();

  /// What this account's credential may actually do, and the rules it must do it within.
  ///
  /// Filtered per account: an account without ticketing is not shown ticket tools. Read this rather
  /// than assuming — it is also the cheapest way to check a key works.
  Future<({List<CnctTool> tools, CnctBookingRules rules})> catalogue() async {
    final json = await _transport.get('/api/booking-tools', headers: _headers);
    final map = _map(json);
    return (
      tools: ((map['tools'] as List<Object?>?) ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((item) => CnctTool.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      rules: CnctBookingRules.fromJson(
          (map['rules'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? const {}),
    );
  }

  /// Call any tool by name, and get back exactly what the platform sent.
  ///
  /// The escape hatch, and a supported one: a tool added to the platform after this SDK was
  /// published is reachable here on the day it ships, without waiting for a release. **It does not
  /// throw on a refusal** — a tool that declines answers `200` with an `error` sentence, and this
  /// hands that back for you to read. Use [callOrThrow] for the other behaviour.
  Future<Map<String, dynamic>> call(String tool, [Map<String, dynamic> args = const {}]) async {
    final json = await _transport.post(
      '/api/booking-tools/${Uri.encodeComponent(tool)}',
      body: args,
      headers: _headers,
    );
    return _map(json);
  }

  /// [call], but a refusal becomes a [CnctException] with [CnctErrorCode.toolRefused].
  Future<Map<String, dynamic>> callOrThrow(String tool,
      [Map<String, dynamic> args = const {}]) async {
    final result = await call(tool, args);
    final refusal = result['error'];
    if (refusal is String) {
      throw CnctException(refusal, code: CnctErrorCode.toolRefused, details: result);
    }
    return result;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    throw CnctException(
      'Expected an object from the server and got ${value.runtimeType}.',
      code: CnctErrorCode.badResponse,
    );
  }
}

/// The calendar, as an account's software sees it.
///
/// Every method that is about a particular person takes [customerPhone] in full international form.
/// That is not a convenience parameter — it *is* the authorization boundary. There is no ambient
/// identity out here, so the number is what decides whose booking may be read and changed, and the
/// platform resolves it itself rather than trusting an id a caller could have guessed.
class CnctBookings {
  CnctBookings._(this._client);

  final CnctAgentClient _client;

  /// What the business can be booked for. An empty list means it books generically.
  Future<CnctListing<CnctService>> services() async {
    final result = await _client.call('list_services');
    return CnctListing(
      items: _items(result, 'services', CnctService.fromJson),
      note: result['note'] as String?,
      refusal: result['error'] as String?,
    );
  }

  /// The people and tables that can be asked for by name.
  ///
  /// **An empty list is an instruction, not an absence.** A business that has switched named
  /// preference off is telling you not to offer a choice of person — the reason accounts turn it off
  /// is that one popular stylist absorbs every request while three others sit idle. [CnctListing.note]
  /// says which case you are in.
  Future<CnctListing<CnctBookableResource>> people() async {
    final result = await _client.call('list_people');
    return CnctListing(
      items: _items(result, 'people', CnctBookableResource.fromJson),
      note: result['note'] as String?,
      refusal: result['error'] as String?,
    );
  }

  /// The free times on a date. **Always call this before offering anybody a time.**
  ///
  /// [date] is `YYYY-MM-DD` in the business's own timezone — the one [CnctBookingRules.timezone]
  /// names, which is not necessarily the device's.
  Future<CnctAvailability> checkAvailability({
    required String date,
    String? serviceId,
    String? resourceId,
    int? partySize,
    String? locationId,
  }) async {
    final result = await _client.callOrThrow('check_availability', {
      'date': date,
      if (serviceId != null) 'serviceId': serviceId,
      if (resourceId != null) 'resourceId': resourceId,
      if (partySize != null) 'partySize': partySize,
      if (locationId != null) 'locationId': locationId,
    });
    return CnctAvailability.fromJson(result);
  }

  /// Take a booking at a time [checkAvailability] reported free.
  ///
  /// Pass [startsAt] exactly as the slot gave it. Rebuilding it from a parsed `DateTime` is how a
  /// booking lands on a time nobody offered.
  ///
  /// [nameIsTheCaller] is small and load-bearing. A booking's name and a customer's name are
  /// different facts about different people: somebody booking a haircut for their daughter gives
  /// their daughter's name, and filing it against the number would rename the contact permanently.
  /// Leave it false unless the name given is the phone number's own owner.
  Future<CnctBookingConfirmation> create({
    required String startsAt,
    required String customerPhone,
    String? serviceId,
    String? resourceId,
    int? partySize,
    String? name,
    bool nameIsTheCaller = false,
    String? notes,
    String? locationId,
  }) async {
    final result = await _client.callOrThrow('create_booking', {
      'startsAt': startsAt,
      'customerPhone': customerPhone,
      if (serviceId != null) 'serviceId': serviceId,
      if (resourceId != null) 'resourceId': resourceId,
      if (partySize != null) 'partySize': partySize,
      if (name != null) 'name': name,
      'nameIsTheCaller': nameIsTheCaller,
      if (notes != null) 'notes': notes,
      if (locationId != null) 'locationId': locationId,
    });
    return CnctBookingConfirmation.fromJson(result);
  }

  /// One customer's upcoming bookings. Call this before changing anything — you need the id, and
  /// the lookup is also what proves the booking is theirs.
  Future<CnctListing<CnctBookingSummary>> forCustomer(String customerPhone) async {
    final result = await _client.call('find_my_booking', {'customerPhone': customerPhone});
    return CnctListing(
      items: _items(result, 'bookings', CnctBookingSummary.fromJson),
      note: result['note'] as String?,
      refusal: result['error'] as String?,
    );
  }

  /// Move one of that customer's bookings to a different free time.
  Future<String> reschedule({
    required String bookingId,
    required String startsAt,
    required String customerPhone,
  }) async {
    final result = await _client.callOrThrow('reschedule_booking', {
      'bookingId': bookingId,
      'startsAt': startsAt,
      'customerPhone': customerPhone,
    });
    return result['when'] as String? ?? '';
  }

  /// Cancel one of that customer's bookings. Returns the time it *was* at, for the sentence you say
  /// back to them.
  Future<String> cancel({required String bookingId, required String customerPhone}) async {
    final result = await _client.callOrThrow('cancel_booking', {
      'bookingId': bookingId,
      'customerPhone': customerPhone,
    });
    return result['was'] as String? ?? '';
  }
}

/// Tickets: the work a business could not finish in the moment and hands to a colleague.
class CnctTickets {
  CnctTickets._(this._client);

  final CnctAgentClient _client;

  /// The kinds of work this business hands over. Start here — the type decides what facts are
  /// needed.
  ///
  /// An empty list with a [CnctListing.refusal] means no ticket types are configured yet, which is
  /// an account setup step rather than a failure of this call.
  Future<CnctListing<CnctTicketType>> types() async {
    final result = await _client.call('list_ticket_types');
    return CnctListing(
      items: _items(result, 'types', CnctTicketType.fromJson),
      note: result['note'] as String?,
      refusal: result['error'] as String?,
    );
  }

  /// What one type still needs before it can be raised.
  ///
  /// The subtraction happens on the server: [CnctTicketTypeDetail.askFor] is already only the
  /// questions worth asking, with what the platform knows about this customer removed. Ask for those
  /// and nothing else.
  Future<CnctTicketTypeDetail> type(String ticketTypeId) async {
    final result = await _client.callOrThrow('get_ticket_type', {'ticketTypeId': ticketTypeId});
    return CnctTicketTypeDetail.fromJson(result);
  }

  /// Raise one.
  ///
  /// [fields] is keyed exactly as [type] named them — never invent a key. [idempotencyKey] is worth
  /// sending: retry with the same value and you get the same ticket back rather than a second one.
  /// Omit it and every call raises a new ticket.
  Future<CnctRaisedTicket> create({
    required String ticketTypeId,
    required String title,
    required String reasonUnresolved,
    String? customerPhone,
    String? customerRequest,
    String? desiredOutcome,
    String? actionsTaken,
    String? recommendedNextAction,
    String? priority,
    Map<String, Object?> fields = const {},
    String? idempotencyKey,
  }) async {
    final result = await _client.callOrThrow('create_ticket', {
      'ticketTypeId': ticketTypeId,
      'title': title,
      'reasonUnresolved': reasonUnresolved,
      if (customerPhone != null) 'customerPhone': customerPhone,
      if (customerRequest != null) 'customerRequest': customerRequest,
      if (desiredOutcome != null) 'desiredOutcome': desiredOutcome,
      if (actionsTaken != null) 'actionsTaken': actionsTaken,
      if (recommendedNextAction != null) 'recommendedNextAction': recommendedNextAction,
      if (priority != null) 'priority': priority,
      if (fields.isNotEmpty) 'fields': fields,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
    return CnctRaisedTicket.fromJson(result);
  }

  /// One customer's open tickets, found by their number. Never describe a ticket to anybody but the
  /// person it belongs to.
  Future<CnctListing<CnctTicketSummary>> forCustomer(String customerPhone) async {
    final result = await _client.call('find_my_tickets', {'customerPhone': customerPhone});
    return CnctListing(
      items: _items(result, 'tickets', CnctTicketSummary.fromJson),
      note: result['note'] as String?,
      refusal: result['error'] as String?,
    );
  }
}

List<T> _items<T>(
  Map<String, dynamic> result,
  String key,
  T Function(Map<String, dynamic>) parse,
) =>
    ((result[key] as List<Object?>?) ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((item) => parse(item.cast<String, dynamic>()))
        .toList(growable: false);
