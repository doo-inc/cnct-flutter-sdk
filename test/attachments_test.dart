import 'dart:convert';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_server.dart';

Map<String, dynamic> storedFile({
  String id = 'att_1',
  String mimeType = 'image/jpeg',
  String filename = 'photo.jpg',
  int bytes = 1024,
}) =>
    {
      'attachment': {
        'id': id,
        'kind': mimeType.startsWith('image/') ? 'IMAGE' : 'DOCUMENT',
        'mimeType': mimeType,
        'filename': filename,
        'bytes': bytes,
      },
    };

void main() {
  group('the checks before an upload', () {
    test('a file over 50 MB is refused before anything is sent', () {
      final refusal = CnctAttachmentRules.check(
        filename: 'film.mp4',
        mimeType: 'video/mp4',
        bytes: CnctAttachmentRules.maxBytes + 1,
      );
      expect(refusal?.code, CnctErrorCode.tooLarge);
      expect(
        CnctAttachmentRules.check(
            filename: 'film.mp4', mimeType: 'video/mp4', bytes: CnctAttachmentRules.maxBytes),
        isNull,
      );
    });

    test('the eleventh file on a message is refused, not the whole message', () {
      expect(
        CnctAttachmentRules.check(
            filename: 'a.pdf', mimeType: 'application/pdf', bytes: 10, alreadyAttached: 9),
        isNull,
      );
      expect(
        CnctAttachmentRules.check(
                filename: 'a.pdf', mimeType: 'application/pdf', bytes: 10, alreadyAttached: 10)
            ?.code,
        CnctErrorCode.tooManyFiles,
      );
    });

    test('a type the platform does not take is refused, whatever its case or parameters', () {
      expect(
        CnctAttachmentRules.check(filename: 'x.zip', mimeType: 'application/zip', bytes: 10)?.code,
        CnctErrorCode.unsupportedType,
      );
      expect(CnctAttachmentRules.accepts('TEXT/PLAIN; charset=utf-8'), isTrue);
      expect(
          CnctAttachmentRules.accepts(
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
          isTrue);
    });

    test('HEIC is recognised by type or by name, and refused with a reason to convert', () {
      expect(CnctAttachmentRules.isHeic('image/heic'), isTrue);
      expect(CnctAttachmentRules.isHeic('image/heif'), isTrue);
      expect(CnctAttachmentRules.isHeic('application/octet-stream', 'IMG_0001.HEIC'), isTrue);
      expect(CnctAttachmentRules.isHeic('image/jpeg', 'IMG_0001.jpg'), isFalse);
      final refusal =
          CnctAttachmentRules.check(filename: 'IMG_0001.HEIC', mimeType: 'image/heic', bytes: 10);
      expect(refusal?.code, CnctErrorCode.unsupportedType);
      expect(refusal?.message, contains('JPEG'));
    });

    test('a name with no type still finds one, HEIC included', () {
      expect(CnctAttachmentRules.mimeTypeFor('invoice.PDF'), 'application/pdf');
      expect(CnctAttachmentRules.mimeTypeFor('IMG_0001.heic'), 'image/heic');
      expect(CnctAttachmentRules.mimeTypeFor('notes'), 'application/octet-stream');
    });

    test('a refused file never reaches the network', () async {
      final server = FakeServer();
      final chat = server.client();
      await chat.start(displayName: 'Layla');
      server.seen.clear();

      final upload = chat.upload(
          CnctUploadFile.bytes([1, 2, 3], filename: 'IMG_0001.HEIC', mimeType: 'image/heic'));

      await expectLater(
          upload.result,
          throwsA(
              isA<CnctException>().having((e) => e.code, 'code', CnctErrorCode.unsupportedType)));
      expect(server.seen, isEmpty);
      chat.dispose();
    });
  });

  group('uploading', () {
    test('is one multipart part named file, with its name and type, on the visitor token',
        () async {
      late http.Request seen;
      final server = FakeServer(routes: {
        'POST /api/chat/public/attachments': (request) {
          seen = request;
          return json(storedFile(), 201);
        },
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');

      final upload = chat.upload(CnctUploadFile.bytes(utf8.encode('jpeg bytes'),
          filename: 'photo.jpg', mimeType: 'image/jpeg'));
      final attachment = await upload.result;

      expect(attachment.id, 'att_1');
      expect(attachment.kind, CnctAttachmentKind.image);
      expect(seen.headers['content-type'], startsWith('multipart/form-data; boundary='));
      expect(seen.headers['x-chat-token'], 'visitor-token-1');
      expect(seen.headers.containsKey('authorization'), isFalse);
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('name="file"; filename="photo.jpg"'));
      expect(body.toLowerCase(), contains('content-type: image/jpeg'));
      expect(body, contains('jpeg bytes'));
      // One part, and only one: the platform takes a file per request.
      expect(RegExp('content-disposition', caseSensitive: false).allMatches(body), hasLength(1));
      chat.dispose();
    });

    test('reports progress per file, rising to 1', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/attachments': (_) => json(storedFile(bytes: 300000), 201),
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');

      final seen = <double>[];
      final upload = chat.upload(
        CnctUploadFile.bytes(List.filled(300000, 7),
            filename: 'big.pdf', mimeType: 'application/pdf'),
        onProgress: seen.add,
      );
      await upload.result;

      // Sent in pieces, so the ring moves rather than jumping from nothing to done.
      expect(seen.length, greaterThan(3));
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
      expect(seen.last, 1);
      expect(upload.progress, 1);
      chat.dispose();
    });

    test('a stream is uploaded without being held whole, and declares its length', () async {
      late http.Request seen;
      final server = FakeServer(routes: {
        'POST /api/chat/public/attachments': (request) {
          seen = request;
          return json(storedFile(mimeType: 'video/mp4', filename: 'clip.mp4'), 201);
        },
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');

      final upload = chat.upload(CnctUploadFile.stream(
        Stream.fromIterable([List.filled(1000, 1), List.filled(1000, 2)]),
        length: 2000,
        filename: 'clip.mp4',
        mimeType: 'video/mp4',
      ));
      await upload.result;
      expect(seen.contentLength, greaterThan(2000));
      chat.dispose();
    });

    test('each refusal arrives under the code worth branching on, with the server sentence',
        () async {
      Future<CnctException> refusalFor(int status) async {
        final server = FakeServer(routes: {
          'POST /api/chat/public/attachments': (_) =>
              json({'error': 'A sentence for a person.'}, status),
        });
        final chat = server.client();
        await chat.start(displayName: 'Layla');
        try {
          await chat
              .upload(CnctUploadFile.bytes([1], filename: 'a.pdf', mimeType: 'application/pdf'))
              .result;
        } on CnctException catch (error) {
          chat.dispose();
          return error;
        }
        throw StateError('expected a refusal');
      }

      expect((await refusalFor(403)).code, CnctErrorCode.attachmentsOff);
      expect((await refusalFor(503)).code, CnctErrorCode.attachmentsOff);
      expect((await refusalFor(409)).code, CnctErrorCode.conversationClosed);
      expect((await refusalFor(413)).code, CnctErrorCode.tooLarge);
      expect((await refusalFor(422)).code, CnctErrorCode.unsupportedType);
      expect((await refusalFor(422)).message, 'A sentence for a person.');
      // A 403 here is the inbox's setting, never a bad token: nobody is sent back to sign in.
      expect((await refusalFor(403)).isUnauthenticated, isFalse);
    });

    test('a 409 means the conversation ended underneath', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/attachments': (_) => json({'error': 'It has ended.'}, 409),
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');
      await expectLater(
        chat
            .upload(CnctUploadFile.bytes([1], filename: 'a.pdf', mimeType: 'application/pdf'))
            .result,
        throwsA(isA<CnctException>()),
      );
      expect(chat.state.status, CnctChatStatus.ended);
      expect(chat.state.conversation?.isClosed, isTrue);
      chat.dispose();
    });

    test('needs a session, and says so', () async {
      final chat = FakeServer().client();
      await expectLater(
        chat
            .upload(CnctUploadFile.bytes([1], filename: 'a.pdf', mimeType: 'application/pdf'))
            .result,
        throwsA(isA<CnctException>().having((e) => e.code, 'code', CnctErrorCode.noSession)),
      );
      chat.dispose();
    });

    test('cancel fails the result at once and stops the request', () async {
      var reached = false;
      final server = FakeServer(routes: {
        'POST /api/chat/public/attachments': (_) {
          reached = true;
          return json(storedFile(), 201);
        },
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');

      final upload = chat.upload(CnctUploadFile.bytes(List.filled(200000, 1),
          filename: 'big.pdf', mimeType: 'application/pdf'));
      upload.cancel();

      await expectLater(upload.result,
          throwsA(isA<CnctException>().having((e) => e.code, 'code', CnctErrorCode.cancelled)));
      expect(upload.isCancelled, isTrue);
      await pumpEventQueue();
      // The body failed at its next piece, so the server never got a whole file to store.
      expect(reached, isFalse);
      chat.dispose();
    });
  });

  group('sending files', () {
    test('the message carries the uploaded ids as attachmentIds', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/attachments': (_) => json(storedFile(), 201),
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');
      final attachment = await chat
          .upload(CnctUploadFile.bytes([1, 2], filename: 'photo.jpg', mimeType: 'image/jpeg'))
          .result;

      await chat.send('', attachments: [attachment]);

      final body = server.bodyOf(server.to('POST', '/api/chat/public/messages').single);
      expect(body['attachmentIds'], ['att_1']);
      // Files alone are a message: the body may be empty when there is something attached.
      expect(body['body'], '');
      chat.dispose();
    });

    test('more than ten files on one message is refused locally', () async {
      final chat = FakeServer().client();
      await chat.start(displayName: 'Layla');
      final files = List.generate(
        11,
        (i) => CnctChatAttachment(
            id: 'att_$i',
            kind: CnctAttachmentKind.document,
            mimeType: 'text/plain',
            filename: null,
            bytes: 1),
      );
      await expectLater(
        chat.send('', attachments: files),
        throwsA(isA<CnctException>().having((e) => e.code, 'code', CnctErrorCode.tooManyFiles)),
      );
      chat.dispose();
    });

    test('a file sent from bytes is not downloaded again to be shown', () async {
      final server = FakeServer(routes: {
        'POST /api/chat/public/attachments': (_) => json(storedFile(), 201),
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');
      final attachment = await chat
          .upload(CnctUploadFile.bytes([9, 8, 7], filename: 'photo.jpg', mimeType: 'image/jpeg'))
          .result;
      server.seen.clear();

      expect(await chat.downloadAttachment(attachment.id), [9, 8, 7]);
      expect(server.seen, isEmpty);
      chat.dispose();
    });
  });

  group('receiving files', () {
    test('downloads with the token header, once per id', () async {
      final server = FakeServer(routes: {
        'GET /api/chat/public/attachments/att_9': (_) => http.Response.bytes([1, 2, 3], 200),
      });
      final chat = server.client();
      await chat.start(displayName: 'Layla');
      server.seen.clear();

      final first = chat.downloadAttachment('att_9');
      final second = chat.downloadAttachment('att_9');
      expect(await first, [1, 2, 3]);
      expect(await second, [1, 2, 3]);
      expect(await chat.downloadAttachment('att_9'), [1, 2, 3]);

      final requests = server.to('GET', '/api/chat/public/attachments/att_9').toList();
      expect(requests, hasLength(1));
      expect(requests.single.headers['x-chat-token'], 'visitor-token-1');
      expect(requests.single.url.query, isEmpty);
      chat.dispose();
    });
  });
}
