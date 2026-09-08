import '../config.dart';
import '../credentials.dart';
import '../exception.dart';
import '../transport.dart';
import 'contact_models.dart';

/// Thrown when a contact cannot be created because one of its identities already belongs to
/// somebody.
///
/// The platform asks before it writes precisely so this can name who it collided with — a
/// unique-violation carries the constraint, not the row. Offer to open [existingId] rather than
/// sending somebody to the search box to look for a person they were just told is there.
class CnctContactConflict extends CnctException {
  CnctContactConflict(super.message, {required this.existingId, required this.existingName})
      : super(code: CnctErrorCode.conflict, status: 409);

  final String? existingId;
  final String? existingName;
}

/// The account's contact directory.
///
/// Needs a [CnctOperatorToken] — a person's console session. There is no contacts surface on the
/// API-key credential today, so an unattended integration cannot reach this: that is the platform's
/// boundary rather than this SDK's, and it is worth knowing before you design around it.
///
/// ```dart
/// final auth = CnctOperatorAuth(config: config);
/// final result = await auth.login(email: '…', password: '…');
/// final contacts = CnctContactsClient(config: config, credentials: result.session!.credentials);
///
/// var page = await contacts.list(query: 'layla');
/// while (page.hasMore) {
///   page = await contacts.list(query: 'layla', cursor: page.nextCursor);
/// }
/// ```
class CnctContactsClient {
  CnctContactsClient({
    required CnctConfig config,
    required CnctOperatorToken credentials,
    CnctTransport? transport,
  })  : _transport = transport ?? CnctTransport(config: config),
        _headers = credentials.headers;

  final CnctTransport _transport;
  final Map<String, String> _headers;

  void close() => _transport.close();

  /// One page of the directory, most recently touched first.
  ///
  /// Paged by cursor rather than by offset, and that is not a style choice: every inbound message
  /// touches the contact it belongs to, so the order is being rewritten while somebody scrolls it.
  /// Under an offset that is page two silently re-showing half of page one.
  ///
  /// [attributes] narrows by the account's own fields, as `key:value` pairs.
  Future<CnctContactPage> list({
    String? query,
    List<String>? tagIds,
    List<String>? attributes,
    int limit = 100,
    String? cursor,
  }) async {
    final json = await _transport.get('/api/contacts',
        query: {
          if (query != null && query.isNotEmpty) 'q': query,
          if (tagIds != null && tagIds.isNotEmpty) 'tagId': tagIds.join(','),
          if (attributes != null && attributes.isNotEmpty) 'attr': attributes,
          'take': limit,
          if (cursor != null) 'cursor': cursor,
        },
        headers: _headers);
    return CnctContactPage.fromJson(_map(json));
  }

  /// Every page, as one stream. Stops when the platform stops issuing cursors.
  ///
  /// Convenient, and worth being deliberate about: an account with twenty-five thousand contacts
  /// will happily hand you all of them. Take what you need.
  Stream<CnctContact> listAll({
    String? query,
    List<String>? tagIds,
    List<String>? attributes,
    int pageSize = 100,
  }) async* {
    String? cursor;
    do {
      final page = await list(
        query: query,
        tagIds: tagIds,
        attributes: attributes,
        limit: pageSize,
        cursor: cursor,
      );
      yield* Stream.fromIterable(page.contacts);
      cursor = page.nextCursor;
    } while (cursor != null);
  }

  /// One person, with the history the console shows beside them in [CnctContact.raw].
  Future<CnctContact> get(String contactId) async {
    final json =
        await _transport.get('/api/contacts/${Uri.encodeComponent(contactId)}', headers: _headers);
    return CnctContact.fromJson(_map(json));
  }

  /// Add somebody by hand.
  ///
  /// **At least one of [phoneNumber], [email] and [identifier] is required**, and the name is not one
  /// of them. Two people called Ahmed are two people; a directory keyed on what somebody is called
  /// is a directory that merges strangers.
  ///
  /// Throws [CnctContactConflict] when one of those identities is already somebody else's.
  Future<CnctContact> create({
    String? name,
    String? phoneNumber,
    String? email,
    String? identifier,
    String? company,
    String? notes,
    List<String>? tagIds,
  }) async {
    if ((phoneNumber ?? '').trim().isEmpty &&
        (email ?? '').trim().isEmpty &&
        (identifier ?? '').trim().isEmpty) {
      throw CnctException(
        'A contact needs a phone number, an email address or an id to be found by.',
        code: CnctErrorCode.invalid,
      );
    }
    try {
      final json = await _transport.post('/api/contacts',
          body: {
            if (name != null) 'name': name,
            if (phoneNumber != null) 'phoneNumber': phoneNumber,
            if (email != null) 'email': email,
            if (identifier != null) 'identifier': identifier,
            if (company != null) 'company': company,
            if (notes != null) 'notes': notes,
            if (tagIds != null && tagIds.isNotEmpty) 'tagIds': tagIds,
          },
          headers: _headers);
      return CnctContact.fromJson(_map(json));
    } on CnctException catch (error) {
      if (error.status != 409) rethrow;
      final existing = (error.details as Map<Object?, Object?>?)?['contact'];
      throw CnctContactConflict(
        error.message,
        existingId: existing is Map ? existing['id'] as String? : null,
        existingName: existing is Map ? existing['name'] as String? : null,
      );
    }
  }

  /// Change what a person's record says.
  ///
  /// A partial update: omitted fields are left alone, and an empty string clears a field rather than
  /// storing `""`. [customAttributes] is itself a patch — send only the keys that changed, and
  /// `null` to clear one.
  ///
  /// The three identities are deliberately not editable here. Correcting somebody's number is a
  /// merge, not an edit — see [merge].
  Future<CnctContact> update(
    String contactId, {
    String? name,
    String? email,
    String? company,
    String? notes,
    Map<String, Object?>? customAttributes,
  }) async {
    final json = await _transport.patch('/api/contacts/${Uri.encodeComponent(contactId)}',
        body: {
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (company != null) 'company': company,
          if (notes != null) 'notes': notes,
          if (customAttributes != null) 'customAttributes': customAttributes,
        },
        headers: _headers);
    return CnctContact.fromJson(_map(json));
  }

  /// Fold one record into another, keeping [into].
  ///
  /// Never do this speculatively. Identity resolution refuses to merge on its own for a reason: a
  /// shared household number is not proof that two histories belong to one person. This is the
  /// explicit decision, made while looking at both records — and the duplicate is deleted.
  Future<CnctContact> merge({required String contactId, required String into}) async {
    final json = await _transport.post(
      '/api/contacts/${Uri.encodeComponent(contactId)}/merge',
      body: {'into': into},
      headers: _headers,
    );
    final data = _map(json);
    return CnctContact.fromJson(
        (data['contact'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? data);
  }

  /// Put a tag on somebody. Idempotent — the same tag twice is one assignment.
  Future<CnctContact> addTag({required String contactId, required String tagId}) async {
    final json = await _transport.post(
      '/api/contacts/${Uri.encodeComponent(contactId)}/tags',
      body: {'tagId': tagId},
      headers: _headers,
    );
    return CnctContact.fromJson(_map(json));
  }

  /// Take one off.
  Future<CnctContact> removeTag({required String contactId, required String tagId}) async {
    final json = await _transport.delete(
      '/api/contacts/${Uri.encodeComponent(contactId)}/tags/${Uri.encodeComponent(tagId)}',
      headers: _headers,
    );
    return CnctContact.fromJson(_map(json));
  }

  /// The account's tags, with how many people carry each. This is where a tag id comes from — the
  /// list and the create call both take ids, never names.
  Future<List<CnctTag>> tags() async {
    final json = await _transport.get('/api/tags', headers: _headers);
    if (json is! List) {
      throw CnctException(
        'Expected a list of tags and got ${json.runtimeType}.',
        code: CnctErrorCode.badResponse,
      );
    }
    return json
        .whereType<Map<Object?, Object?>>()
        .map((item) => CnctTag.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    throw CnctException(
      'Expected an object from the server and got ${value.runtimeType}.',
      code: CnctErrorCode.badResponse,
    );
  }
}
