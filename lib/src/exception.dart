/// Everything in this SDK that can fail, fails with one of these.
///
/// The [code] is the part worth branching on. It is stable across versions and, where the failure
/// came from the server, it is the server's own code verbatim — the same string a JavaScript
/// integrator sees for the same event, because two SDKs inventing two vocabularies for one error is
/// how a support answer stops being portable between them.
class CnctException implements Exception {
  CnctException(this.message, {this.code = 'error', this.status, this.details});

  /// For a human. Never parse this — parse [code].
  final String message;

  /// Stable. See [CnctErrorCode] for the ones this SDK promises to keep.
  final String code;

  /// The HTTP status, when the failure arrived as a response rather than as a socket frame or a
  /// dead network.
  final int? status;

  /// The server's whole error body, where it answered with one.
  ///
  /// Worth reading: a refused contact carries the record it collided with, a login that needs an
  /// account carries the list to choose from, and a validation refusal carries the fields under
  /// `error` as `{fieldErrors, formErrors}`.
  final Object? details;

  /// True when retrying later is reasonable: the network was down, the socket dropped mid-send, or
  /// the server asked us to slow down. A 4xx that is not a rate limit is not in here — retrying a
  /// request the server understood and refused just refuses again.
  bool get isRetryable =>
      code == CnctErrorCode.offline ||
      code == CnctErrorCode.timeout ||
      code == CnctErrorCode.rateLimited ||
      code == CnctErrorCode.serverError;

  /// True when the credential is the problem: it expired, it was revoked, or it never resolved.
  /// A chat client clears its stored session token when it sees this; anything else should ask for
  /// a fresh credential rather than retrying.
  bool get isUnauthenticated => code == CnctErrorCode.unauthenticated;

  @override
  String toString() => 'CnctException($code${status != null ? ' $status' : ''}): $message';
}

/// The codes this SDK will not rename.
///
/// The first block is the server's — `src/routes/chat-public.ts` and the visitor socket send these
/// by name and they are documented as stable in the platform's own web SDK. The second block is
/// this client's, for the failures that never reach a server.
abstract final class CnctErrorCode {
  // ── The server's ──────────────────────────────────────────────────────────────────────────────
  /// The request was malformed or failed validation. [CnctException.details] carries the fields.
  static const invalid = 'invalid';

  /// Too many requests. Slow down; the limits are published in the README.
  static const rateLimited = 'rate_limited';

  /// The message body was over the four-thousand-character limit.
  static const tooLarge = 'too_large';

  /// The conversation has ended. Start a new one; it cannot be reopened from this side.
  static const conversationClosed = 'conversation_closed';

  /// The request collided with something that already exists or has already moved on: a contact
  /// with that number, a slot somebody else took, an operator who belongs to more than one account.
  /// Never a reason to retry unchanged — the answer will be the same.
  static const conflict = 'conflict';

  /// The session token now points at a different conversation than the one being written to.
  static const conversationChanged = 'conversation_changed';

  /// The credential did not resolve, or no longer does.
  static const unauthenticated = 'unauthenticated';

  /// Something broke on the far side.
  static const serverError = 'server_error';

  // ── This client's ─────────────────────────────────────────────────────────────────────────────
  /// The network could not be reached at all, or a socket dropped before a frame was acknowledged.
  /// Distinct from a 4xx on purpose: one is worth retrying and the other is not.
  static const offline = 'offline';

  /// A send was not acknowledged inside the configured window. Retrying is safe — see
  /// `CnctChatClient.retry`.
  static const timeout = 'timeout';

  /// A method that needs a live session was called before `start()` or `resume()`.
  static const noSession = 'no_session';

  /// Nothing to send: the body was empty or whitespace.
  static const empty = 'empty';

  /// A local lookup found nothing — a `clientKey` with no message behind it, say.
  static const notFound = 'not_found';

  /// The server answered, and answered with an error this SDK has no more specific name for.
  static const requestFailed = 'request_failed';

  /// The response was not the shape this SDK expects. Almost always a base URL pointing at
  /// something that is not a CNCT host.
  static const badResponse = 'bad_response';

  /// A module was used without the credential it needs.
  static const missingCredential = 'missing_credential';

  /// A tool declined, in a sentence rather than a status code. The account's operations surface
  /// answers `200` with an `error` key when it will not do something — the slot went, the number is
  /// not on file, no ticket types are configured — and this is that, raised.
  static const toolRefused = 'tool_refused';
}
