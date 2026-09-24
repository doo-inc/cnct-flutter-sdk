import 'exception.dart';

/// The CNCT hosts this SDK knows about by name.
///
/// **CNCT runs at `app.doo.ooo`, and that is the default.** Until 0.2.0 the only deployment was a
/// development box, so the host was required and had no default — a default then would have meant
/// shipping to production against a dev box by forgetting to set something. There is a production
/// host now, so leaving [CnctConfig.baseUrl] out means production, and anything else — a proxy on
/// your own domain, a local server — is still one `baseUrl` away.
///
/// Whether what you do is real is decided by the key, not the host: a sandbox key (`kaer_sk_test_…`)
/// talks to the same production host and writes nothing real. See [CnctApiKey].
abstract final class CnctHosts {
  /// Production. What [CnctConfig.baseUrl] is when you leave it out.
  static final Uri production = Uri.parse('https://app.doo.ooo');

  /// The development box this used to name no longer answers — CNCT runs at `app.doo.ooo`. Kept so
  /// code that referenced it still compiles, and pointed at production so it still works.
  @Deprecated('Use CnctHosts.production, or leave baseUrl out.')
  static final Uri development = production;
}

/// Where this SDK points and how it behaves on the wire.
///
/// One object, passed to every client, and the only thing that has to change to move an app between
/// a developer's laptop, a staging host and production. [copyWith] exists so that swap can happen at
/// runtime — an in-app environment picker, a remote config value, a `--dart-define` — without
/// rebuilding anything else.
///
/// ```dart
/// const staging = CnctConfig(baseUrl: 'https://staging.example.com');
/// final live = staging.copyWith(baseUrl: Uri.parse('https://api.example.com'));
/// ```
class CnctConfig {
  CnctConfig({
    Object? baseUrl,
    this.connectTimeout = const Duration(seconds: 20),
    this.sendTimeout = const Duration(seconds: 15),
    this.headers = const {},
    this.userAgent = 'cnct-flutter-sdk/$sdkVersion',
    this.logger,
  }) : baseUrl = _normalise(baseUrl ?? CnctHosts.production);

  /// The version this SDK reports in its `User-Agent`. Kept in step with `pubspec.yaml`.
  static const sdkVersion = '0.1.0';

  /// The CNCT host, with an optional path prefix. Defaults to [CnctHosts.production],
  /// `https://app.doo.ooo`.
  ///
  /// A prefix is honoured rather than stripped: a client fronting CNCT at
  /// `https://theirdomain.com/support` is a legitimate arrangement, and every path this SDK builds
  /// is appended to whatever is here. Accepts a [String] or a [Uri] — a string is the common case
  /// and demanding `Uri.parse` at every call site buys nothing.
  final Uri baseUrl;

  /// How long to wait for an HTTP response before giving up with [CnctErrorCode.timeout].
  final Duration connectTimeout;

  /// How long to wait for a chat message to be acknowledged before rejecting it. Rejecting is safe:
  /// every message carries an idempotency key, so a retry cannot double-post.
  final Duration sendTimeout;

  /// Sent on every request. For a proxy that wants its own header, a tracing id, or a tenant
  /// selector in front of CNCT. Never put a CNCT credential here — the clients set those
  /// themselves, on the header each one actually uses.
  final Map<String, String> headers;

  /// Identifies this SDK in the platform's request logs. Worth overriding with your own app's name
  /// and version: when a client asks why their integration is being rate-limited, this is the field
  /// that answers it.
  final String userAgent;

  /// Where this SDK says what it is doing. Null is silence, which is the default — an SDK that
  /// prints to a customer's console uninvited is a bug report.
  final void Function(CnctLogLevel level, String message, [Object? error])? logger;

  /// The WebSocket origin, derived rather than configured.
  ///
  /// Two URLs to keep in step is one URL that gets forgotten, and the forgotten one is always the
  /// socket — it fails later, in a way that looks like a network problem rather than a
  /// misconfiguration. `https` becomes `wss`, `http` becomes `ws`, and the path prefix travels.
  Uri get socketBaseUrl => baseUrl.replace(scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws');

  /// A copy with some things changed. This is how you swap hosts at runtime.
  CnctConfig copyWith({
    Object? baseUrl,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Map<String, String>? headers,
    String? userAgent,
    void Function(CnctLogLevel level, String message, [Object? error])? logger,
  }) =>
      CnctConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        connectTimeout: connectTimeout ?? this.connectTimeout,
        sendTimeout: sendTimeout ?? this.sendTimeout,
        headers: headers ?? this.headers,
        userAgent: userAgent ?? this.userAgent,
        logger: logger ?? this.logger,
      );

  /// Build a request URL under [baseUrl], preserving any path prefix it carries.
  Uri resolve(String path, [Map<String, dynamic>? query]) {
    final prefix = baseUrl.path.replaceAll(RegExp(r'/+$'), '');
    final cleaned = <String, dynamic>{};
    query?.forEach((key, value) {
      if (value == null) return;
      if (value is Iterable) {
        final parts = value.map((item) => '$item').where((item) => item.isNotEmpty).toList();
        if (parts.isNotEmpty) cleaned[key] = parts;
        return;
      }
      final text = '$value';
      if (text.isNotEmpty) cleaned[key] = text;
    });
    return baseUrl.replace(
      path: '$prefix${path.startsWith('/') ? path : '/$path'}',
      queryParameters: cleaned.isEmpty ? null : cleaned,
    );
  }

  static Uri _normalise(Object value) {
    // An empty string is not "left out": it is a variable somebody meant to set.
    if (value is String && value.trim().isEmpty) {
      throw CnctException(
        'baseUrl is empty. Leave it out to use CNCT production (${CnctHosts.production}), or pass '
        'your own host.',
        code: CnctErrorCode.invalid,
      );
    }
    final uri = switch (value) {
      Uri() => value,
      String() => Uri.parse(value.trim()),
      _ => throw CnctException(
          'baseUrl must be a String or a Uri, not ${value.runtimeType}.',
          code: CnctErrorCode.invalid,
        ),
    };
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw CnctException(
        'baseUrl must be an absolute http(s) URL — got "$uri".',
        code: CnctErrorCode.invalid,
      );
    }
    // Trailing slashes are stripped once, here, so that every path built from this is built the
    // same way and a host written with one behaves identically to a host written without.
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''), query: null, fragment: null);
  }

  @override
  String toString() => 'CnctConfig(baseUrl: $baseUrl)';
}

/// How loud a log line is.
enum CnctLogLevel { debug, info, warning, error }
