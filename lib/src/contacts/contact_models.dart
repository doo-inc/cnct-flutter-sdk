/// A tag on a contact — the business's own vocabulary for the people in its directory.
///
/// Distinct from a label, which describes a conversation. The two pools were split deliberately, so
/// a tag id is never a label id.
class CnctTag {
  const CnctTag(
      {required this.id, required this.name, required this.colour, required this.contactCount});

  factory CnctTag.fromJson(Map<String, dynamic> json) => CnctTag(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        colour: json['color'] as String? ?? json['colour'] as String?,
        contactCount: (json['contactCount'] as num?)?.toInt(),
      );

  final String id;
  final String name;

  /// As the console stores it, usually a hex string. Null where the account never set one.
  final String? colour;

  /// How many contacts carry it. Only present on the tag list.
  final int? contactCount;
}

/// A person in the account's directory.
///
/// **Three identities, any one of which is enough to be a person here**: a phone number, an email
/// address, and `identifier` — the client's own id for somebody. Each is unique per account and each
/// is optional; a contact with a name and nothing else could never be found again, so the platform
/// refuses to create one.
class CnctContact {
  const CnctContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.email,
    required this.identifier,
    required this.company,
    required this.notes,
    required this.blocked,
    required this.optedOutAt,
    required this.tags,
    required this.customAttributes,
    required this.createdAt,
    required this.updatedAt,
    required this.raw,
  });

  factory CnctContact.fromJson(Map<String, dynamic> json) {
    final tags = ((json['tags'] as List<Object?>?) ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((assignment) {
      final tag = assignment['tag'];
      return CnctTag.fromJson(
        tag is Map ? tag.cast<String, dynamic>() : assignment.cast<String, dynamic>(),
      );
    }).toList(growable: false);
    return CnctContact(
      id: json['id'] as String? ?? '',
      name: json['name'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      email: json['email'] as String?,
      identifier: json['identifier'] as String?,
      company: json['company'] as String?,
      notes: json['notes'] as String?,
      blocked: json['blocked'] as bool? ?? false,
      optedOutAt: DateTime.tryParse('${json['optedOutAt']}')?.toLocal(),
      tags: tags,
      customAttributes:
          (json['customAttributes'] as Map<Object?, Object?>?)?.cast<String, dynamic>() ?? const {},
      createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal(),
      updatedAt: DateTime.tryParse('${json['updatedAt']}')?.toLocal(),
      raw: json,
    );
  }

  final String id;
  final String? name;

  /// In full international form, as the platform normalises it.
  final String? phoneNumber;
  final String? email;

  /// The client's own id for this person. The one identity a business controls, and therefore the
  /// only one that cannot be a coincidence.
  final String? identifier;

  final String? company;
  final String? notes;

  /// True when this person's inbound messages are being dropped. Their history stays readable —
  /// being blocked changes what happens next, not what already happened.
  final bool blocked;

  /// When they said stop. Campaigns skip anybody with this set, and so should you.
  final DateTime? optedOutAt;

  final List<CnctTag> tags;

  /// The fields this account invented, keyed by the custom attribute's key.
  final Map<String, dynamic> customAttributes;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The record as it arrived, for the columns this SDK version does not model. Reading a field from
  /// here is always safe; relying on one is a bet that the platform keeps it.
  final Map<String, dynamic> raw;

  /// What to put on a row when the name is missing, which for a person who has only ever rung is
  /// the ordinary case.
  String get displayName => name?.trim().isNotEmpty == true
      ? name!.trim()
      : (phoneNumber ?? email ?? identifier ?? 'Unknown');
}

/// One page of the directory.
class CnctContactPage {
  const CnctContactPage({required this.contacts, required this.total, required this.nextCursor});

  factory CnctContactPage.fromJson(Map<String, dynamic> json) => CnctContactPage(
        contacts: ((json['contacts'] as List<Object?>?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((item) => CnctContact.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
        nextCursor: json['nextCursor'] as String?,
      );

  final List<CnctContact> contacts;

  /// Everything the filters match, not just this page — so a pager can say where in it you are.
  final int total;

  /// Pass to the next call. **Null is the end**, and it is the only reliable one: a short page never
  /// issues a cursor, so a list cannot spin on a final request that returns nothing.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
