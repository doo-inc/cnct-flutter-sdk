import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'config.dart';
import 'exception.dart';

/// The one place this SDK talks HTTP.
///
/// Every module goes through it, so the error vocabulary, the timeout, the headers and the JSON
/// handling are decided once. A module that built its own request would be a module that maps a 429
/// to something slightly different, and an integrator branching on [CnctErrorCode] would be right
/// about one of them.
class CnctTransport {
  CnctTransport({
    required this.config,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final CnctConfig config;
  final http.Client _http;
  final bool _ownsClient;

  /// Close the underlying client, but only if we made it. A client handed in belongs to the caller —
  /// closing somebody else's connection pool because our object went away is a bug that shows up as
  /// unrelated requests failing.
  void close() {
    if (_ownsClient) _http.close();
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query, Map<String, String>? headers}) =>
      _send('GET', path, query: query, headers: headers);

  Future<dynamic> post(String path,
          {Object? body, Map<String, dynamic>? query, Map<String, String>? headers}) =>
      _send('POST', path, body: body, query: query, headers: headers);

  Future<dynamic> patch(String path, {Object? body, Map<String, String>? headers}) =>
      _send('PATCH', path, body: body, headers: headers);

  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      _send('DELETE', path, headers: headers);

  /// The raw bytes of something — an attachment, an export. Same auth and same error mapping as the
  /// JSON paths, because a 401 on a file download is the same event as a 401 anywhere else.
  Future<List<int>> bytes(String path, {Map<String, String>? headers}) async {
    final request = http.Request('GET', config.resolve(path))..headers.addAll(_headers(headers));
    final response = await _run(request);
    if (response.statusCode >= 400) {
      throw _failure(response.statusCode, response.body);
    }
    return response.bodyBytes;
  }

  /// One file, as `multipart/form-data` with a single part named [field], reporting how much has
  /// gone as it goes.
  ///
  /// Progress is counted as the body is pulled by the HTTP client rather than as it is read, so it
  /// follows the network: the counting stream is consumed with back-pressure, and a slow connection
  /// shows as a slow ring rather than one that leaps to full and then waits.
  ///
  /// **The timeout starts once the last byte is out.** A 50 MB video over a phone's data takes as
  /// long as it takes; what [CnctConfig.connectTimeout] guards is the wait for an answer after that.
  ///
  /// [isCancelled] is asked before every piece; once it answers true the body stream fails, which
  /// aborts the request with any `http.Client`, and this throws [CnctErrorCode.cancelled].
  Future<dynamic> postMultipart(
    String path, {
    required String field,
    required Stream<List<int>> content,
    required int length,
    required String filename,
    required String mimeType,
    Map<String, String>? headers,
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final url = config.resolve(path);
    MediaType type;
    try {
      type = MediaType.parse(mimeType);
    } on FormatException {
      type = MediaType('application', 'octet-stream');
    }
    final form = http.MultipartRequest('POST', url)
      ..files
          .add(http.MultipartFile(field, content, length, filename: filename, contentType: type));
    final body = form.finalize();
    final total = form.contentLength;

    var sent = 0;
    Stream<List<int>> counted() async* {
      await for (final piece in body) {
        if (isCancelled?.call() ?? false) {
          throw CnctException('The upload was cancelled.', code: CnctErrorCode.cancelled);
        }
        sent += piece.length;
        onProgress?.call(sent, total);
        yield piece;
      }
    }

    final request = http.StreamedRequest('POST', url)
      ..headers.addAll(_headers(headers))
      ..headers['content-type'] = form.headers['content-type']!
      ..contentLength = total;
    final bodyDone = request.sink.addStream(counted()).whenComplete(request.sink.close);

    final http.Response response;
    try {
      final responding = _http.send(request);
      // Whichever comes first: the body finishing, or the server answering early — a refusal before
      // the whole file has arrived, say.
      await Future.any<Object?>([bodyDone, responding]);
      final streamed = await responding.timeout(config.connectTimeout);
      response = await http.Response.fromStream(streamed).timeout(config.connectTimeout);
    } on CnctException {
      rethrow;
    } on TimeoutException {
      throw CnctException(
        'The upload was not answered within ${config.connectTimeout.inSeconds}s.',
        code: CnctErrorCode.timeout,
      );
    } catch (error) {
      if (isCancelled?.call() ?? false) {
        throw CnctException('The upload was cancelled.', code: CnctErrorCode.cancelled);
      }
      throw CnctException(
        'Could not reach ${config.baseUrl.host}: $error',
        code: CnctErrorCode.offline,
      );
    }
    // The body stream may still be winding down after an early answer; its outcome is the
    // response's now, not its own.
    bodyDone.ignore();
    config.logger?.call(CnctLogLevel.debug, 'POST $path (file) → ${response.statusCode}');

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      if (response.statusCode >= 400) throw _failure(response.statusCode, response.body);
      throw CnctException(
        'The server answered an upload with something that is not JSON.',
        code: CnctErrorCode.badResponse,
        status: response.statusCode,
      );
    }
    if (response.statusCode >= 400) throw _failure(response.statusCode, response.body, decoded);
    return decoded;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, config.resolve(path, query));
    request.headers.addAll(_headers(headers));
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final response = await _run(request);
    config.logger?.call(
      CnctLogLevel.debug,
      '$method $path → ${response.statusCode}',
    );

    if (response.statusCode == 204 || response.body.isEmpty) {
      return response.statusCode >= 400 ? throw _failure(response.statusCode, '') : null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      if (response.statusCode >= 400) throw _failure(response.statusCode, response.body);
      throw CnctException(
        'The server answered with something that is not JSON. Check that baseUrl points at a CNCT '
        'host and not at a login page or a proxy error.',
        code: CnctErrorCode.badResponse,
        status: response.statusCode,
      );
    }

    if (response.statusCode >= 400) throw _failure(response.statusCode, response.body, decoded);
    return decoded;
  }

  Future<http.Response> _run(http.Request request) async {
    try {
      final streamed = await _http.send(request).timeout(config.connectTimeout);
      return await http.Response.fromStream(streamed).timeout(config.connectTimeout);
    } on TimeoutException {
      throw CnctException(
        'The request timed out after ${config.connectTimeout.inSeconds}s.',
        code: CnctErrorCode.timeout,
      );
    } on http.ClientException catch (error) {
      // A dead network, a refused connection, DNS. Distinct from an answer, because a UI should
      // retry one and not the other.
      throw CnctException(
        'Could not reach ${config.baseUrl.host}: ${error.message}',
        code: CnctErrorCode.offline,
      );
    } on Exception catch (error) {
      throw CnctException(
        'Could not reach ${config.baseUrl.host}: $error',
        code: CnctErrorCode.offline,
      );
    }
  }

  Map<String, String> _headers(Map<String, String>? extra) => {
        'accept': 'application/json',
        'user-agent': config.userAgent,
        ...config.headers,
        ...?extra,
      };

  /// Turn a failed response into an exception with a code worth branching on.
  ///
  /// The platform answers in three shapes and all three are handled here rather than at the call
  /// sites: `{error: "a sentence"}`, `{error: {fieldErrors, formErrors}}` from a validation refusal,
  /// and `application/problem+json` with its own `code`. Where the body names a code, that code
  /// wins — the server is more specific about its own failures than a status line can be.
  CnctException _failure(int status, String raw, [dynamic decoded]) {
    String message = raw.isEmpty ? 'Request failed with $status.' : raw;
    Object? details;
    String? serverCode;

    if (decoded is Map) {
      // The whole body, always. A refusal often carries more than a sentence — what a tool
      // answered, the fields that failed validation — and a transport that keeps only the message
      // throws that away at the one moment it is useful.
      details = decoded;
      final error = decoded['error'];
      if (error is String) {
        message = error;
      } else if (error != null) {
        message = 'That request was refused.';
      }
      if (decoded['title'] is String) message = decoded['title'] as String;
      if (decoded['code'] is String) serverCode = decoded['code'] as String;
    }

    final code = serverCode ??
        switch (status) {
          400 => CnctErrorCode.invalid,
          401 => CnctErrorCode.unauthenticated,
          403 => CnctErrorCode.unauthenticated,
          404 => CnctErrorCode.notFound,
          409 => CnctErrorCode.conflict,
          413 => CnctErrorCode.tooLarge,
          429 => CnctErrorCode.rateLimited,
          >= 500 => CnctErrorCode.serverError,
          _ => CnctErrorCode.requestFailed,
        };

    return CnctException(message, code: code, status: status, details: details);
  }
}
