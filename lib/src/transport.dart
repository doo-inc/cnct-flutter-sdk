import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
      // The whole body, always. A refusal often carries more than a sentence — the contact you
      // collided with, the accounts you have a seat in, the fields that failed validation — and a
      // transport that keeps only the message throws that away at the one moment it is useful.
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
