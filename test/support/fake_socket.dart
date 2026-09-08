import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A WebSocket that never touches a network.
///
/// [sent] is every frame the client wrote, in order; [push] delivers one to it; [serverClose] ends
/// the connection with a code, which is how the 1008 path gets tested without a server that refuses
/// a token.
// ignore_for_file: close_sinks

class FakeSocket extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  FakeSocket();

  final inbound = StreamController<dynamic>();
  final List<String> sent = [];
  int? closed;
  String? reason;

  void push(Object frame) => inbound.add(frame);

  Future<void> serverClose([int code = 1000, String? why]) async {
    closed = code;
    reason = why;
    if (!inbound.isClosed) await inbound.close();
  }

  @override
  Stream<dynamic> get stream => inbound.stream;

  @override
  late final WebSocketSink sink = _FakeSink(this);

  @override
  int? get closeCode => closed;

  @override
  String? get closeReason => reason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._socket);

  final FakeSocket _socket;
  final _done = Completer<void>();

  @override
  void add(dynamic event) => _socket.sent.add('$event');

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _socket.closed = closeCode;
    _socket.reason = closeReason;
    if (!_socket.inbound.isClosed) await _socket.inbound.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
