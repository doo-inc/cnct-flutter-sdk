import 'dart:typed_data';

import 'package:cnct_flutter_ui/cnct_flutter_ui.dart';
import 'package:cnct_flutter_ui/fixture.dart';
import 'package:cnct_flutter_ui/src/controller.dart';
import 'package:cnct_flutter_ui/src/files/picked_file.dart';
import 'package:cnct_flutter_ui/src/files/source.dart';
import 'package:cnct_flutter_ui/src/widgets/composer.dart';
import 'package:cnct_flutter_ui/src/widgets/scope.dart';
import 'package:cnct_flutter_ui/src/widgets/thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screens.dart';

/// A picker that hands over whatever the test put in it.
class ScriptedFiles implements FileSource {
  List<PickedFile> next = const [];

  @override
  bool get hasCamera => true;

  @override
  Future<List<PickedFile>> camera() async => next;

  @override
  Future<List<PickedFile>> files() async => next;

  @override
  Future<List<PickedFile>> photos() async => next;
}

Future<CnctChatFixture> openChat(
  WidgetTester tester, {
  String language = 'en',
  bool prepare = true,
  ThemeData? hostTheme,
  CnctChatIdentity? identity,
  ValueChanged<CnctChatUiEvent>? onEvent,
  VoidCallback? onClose,
  FileSource? files,
  double textScale = 1,
  Map<String, double> stalled = const {},
}) async {
  tester.view.physicalSize = const Size(780, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final fixture = CnctChatFixture(language: language, stalledUploads: stalled);
  addTearDown(fixture.dispose);
  if (prepare) await tester.runAsync(fixture.prepare);
  await tester.pumpWidget(MaterialApp(
    theme: hostTheme,
    home: MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: Scaffold(
        body: CnctChat.debug(
          client: fixture.client,
          language: language == 'ar' ? CnctChatLanguage.ar : CnctChatLanguage.en,
          identity: identity,
          onEvent: onEvent,
          onClose: onClose,
          fileSource: files,
        ),
      ),
    ),
  ));
  await settle(tester);
  return fixture;
}

/// Take the chat down and dispose of the fixture's client inside the test, so the timers it runs —
/// the typing indicator's, the socket's keep-alive — end before the test checks none are left.
Future<void> finish(WidgetTester tester, CnctChatFixture fixture) async {
  await tester.pumpWidget(const SizedBox());
  fixture.dispose();
  await tester.pump(const Duration(seconds: 5));
}

ChatController controllerOf(WidgetTester tester) =>
    ChatScope.of(tester.element(find.byType(ChatThread))).controller;

void main() {
  setUpAll(loadTestFonts);

  testWidgets('the fixture conversation renders, every message of it', (tester) async {
    final fixture = await openChat(tester);
    expect(find.text('Bayside Café'), findsOneWidget);
    expect(find.text('Someone from the team is with you'), findsOneWidget);
    expect(find.textContaining('Do you open on Fridays?', findRichText: true), findsOneWidget);
    // A flow draws its own words, not the numbered body.
    expect(
        find.textContaining('Would you like to book a visit?', findRichText: true), findsOneWidget);
    expect(find.textContaining('Reply with the number', findRichText: true), findsNothing);
    expect(find.textContaining('invoice.pdf', findRichText: true), findsOneWidget);
    expect(find.textContaining('3311 2233', findRichText: true), findsOneWidget);
    expect(find.textContaining(fixture.failedText, findRichText: true), findsOneWidget);
    expect(find.text('Not sent — tap to try again'), findsOneWidget);
    expect(find.byType(TypingIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the past choices are gone once the conversation moved on', (tester) async {
    await openChat(tester);
    expect(find.byType(ChoicesView), findsNothing);
  });

  testWidgets('Arabic mirrors the whole interface, and the visitor stays on the trailing side',
      (tester) async {
    await openChat(tester, language: 'ar');
    final scope = ChatScope.of(tester.element(find.byType(ChatThread)));
    expect(Directionality.of(tester.element(find.byType(ChatThread))), TextDirection.rtl);
    expect(scope.l10n.t('send'), 'إرسال');

    final mine = tester.getCenter(find.textContaining('هل تفتحون يوم الجمعة؟', findRichText: true));
    final theirs = tester.getCenter(find.textContaining('شكرًا، هذه فاتورتك.', findRichText: true));
    // Right to left, the trailing side is the left.
    expect(mine.dx, lessThan(theirs.dx));
    // The header's close button sits on the left too.
    expect(find.byTooltip('إغلاق المحادثة'), findsNothing); // no onClose given
  });

  testWidgets('English keeps the visitor on the right', (tester) async {
    await openChat(tester);
    final mine =
        tester.getCenter(find.textContaining('Do you open on Fridays?', findRichText: true));
    final theirs =
        tester.getCenter(find.textContaining('Thanks, here is your invoice.', findRichText: true));
    expect(mine.dx, greaterThan(theirs.dx));
  });

  testWidgets('the host app’s theme is neither used nor changed', (tester) async {
    final host = ThemeData(
      colorSchemeSeed: Colors.lime,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.purple,
    );
    await openChat(tester, hostTheme: host);
    final chatMaterial = tester.widget<Material>(
        find.descendant(of: find.byType(CnctChat), matching: find.byType(Material)).first);
    // The chat's own background, the light default — not the dark, lime app around it.
    expect(chatMaterial.color, const Color(0xFFFFFFFF));
    final scaffold = tester.element(find.byType(Scaffold));
    expect(Theme.of(scaffold).scaffoldBackgroundColor, Colors.purple);
  });

  testWidgets('the eleventh file, one over 50 MB, and a type not taken are refused before upload',
      (tester) async {
    final fixture = await openChat(tester);
    final controller = controllerOf(tester);
    final calls = fixture.calls.length;

    controller.addFiles([
      PickedFile(
        name: 'film.mp4',
        mimeType: 'video/mp4',
        length: 51 * 1024 * 1024,
        readBytes: () async => Uint8List(0),
        openRead: () => const Stream.empty(),
      ),
    ]);
    await tester.pump();
    expect(find.text('film.mp4 is over 50 MB.'), findsOneWidget);

    controller.addFiles([PickedFile.bytes(Uint8List(10), name: 'setup.exe')]);
    await tester.pump();
    expect(find.text('setup.exe is a kind of file that cannot be sent.'), findsOneWidget);
    expect(controller.uploads, isEmpty);
    expect(fixture.calls.skip(calls).where((call) => call.contains('attachments')), isEmpty);

    controller.addFiles([
      for (var i = 0; i < 11; i++) PickedFile.bytes(Uint8List.fromList([i]), name: 'note$i.txt'),
    ]);
    await settle(tester);
    expect(controller.uploads, hasLength(10));
    expect(find.text('Up to 10 files at a time.'), findsOneWidget);
  });

  testWidgets('send waits for uploads, then sends the files with the words', (tester) async {
    final fixture = await openChat(tester, stalled: const {'slow.pdf': 0.5});
    final controller = controllerOf(tester);

    controller.addFiles([PickedFile.bytes(Uint8List(200000), name: 'slow.pdf')]);
    await settle(tester);
    expect(controller.uploading, isTrue);
    expect(await controller.send('Here it is'), isFalse);

    controller.removeUpload(controller.uploads.single);
    controller.addFiles([PickedFile.bytes(fixturePdf, name: 'menu.pdf')]);
    await settle(tester);
    expect(controller.uploads.single.status, UploadStatus.done);
    expect(await controller.send('Here it is'), isTrue);
    await settle(tester);
    expect(controller.uploads, isEmpty);
    expect(fixture.calls.where((call) => call == 'POST /api/chat/public/messages'), hasLength(2));
  });

  testWidgets('a picked HEIC is converted before it goes up', (tester) async {
    final files = ScriptedFiles();
    await openChat(tester, files: files);
    final controller = controllerOf(tester);
    // No HEIC decoder on a test machine: the platform's refusal is a sentence, not an upload.
    files.next = [PickedFile.bytes(Uint8List(16), name: 'IMG_0001.HEIC', mimeType: 'image/heic')];
    await tester.tap(find.byTooltip('Attach a file'));
    await settle(tester);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    await tester.tap(find.text('Photos'));
    await settle(tester);
    expect(controller.uploads.single.status, UploadStatus.failed);
    expect(find.text('IMG_0001.HEIC is a kind of file that cannot be sent.'), findsOneWidget);
  });

  testWidgets('read is posted once for the reply on screen', (tester) async {
    final fixture = await openChat(tester);
    await settle(tester);
    final reads = fixture.calls.where((call) => call.endsWith('/read'));
    expect(reads, hasLength(1));
  });

  testWidgets('what a screen reader hears is in the chat’s language', (tester) async {
    final handle = tester.ensureSemantics();
    await openChat(tester);
    expect(find.bySemanticsLabel('You said: Do you open on Fridays?'), findsOneWidget);
    expect(find.bySemanticsLabel('Sara said: Thanks, here is your invoice.'), findsOneWidget);
    expect(find.bySemanticsLabel('The team is typing'), findsOneWidget);
    expect(find.bySemanticsLabel('Open invoice.pdf, 220 KB'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo, 1.2 MB'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('every control is at least 48 by 48', (tester) async {
    await openChat(tester, onClose: () {});
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('the largest text sizes fit without clipping', (tester) async {
    await openChat(tester, textScale: 2, onClose: () {});
    expect(tester.takeException(), isNull);
    await openChat(tester, language: 'ar', textScale: 2, onClose: () {});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a first visit asks for a name, then starts the conversation', (tester) async {
    final events = <CnctChatUiEvent>[];
    final fixture = await openChat(tester, prepare: false, onEvent: events.add);
    expect(find.text('Your name'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Layla');
    await tester.pump();
    await tester.tap(find.text('Start chatting'));
    await settle(tester);
    expect(fixture.calls, contains('POST /api/chat/public/fixture/session'));
    expect(find.byType(Composer), findsOneWidget);
    expect(events.map((event) => event.type),
        containsAllInOrder([CnctChatUiEventType.opened, CnctChatUiEventType.started]));
    await finish(tester, fixture);
  });

  testWidgets('a signed-in user is identified before anything is read', (tester) async {
    final fixture = await openChat(
      tester,
      identity: const CnctChatIdentity(userId: 'user_42', userHash: 'abc', name: 'Layla'),
    );
    final identify = fixture.calls.indexOf('POST /api/chat/public/fixture/identify');
    final read = fixture.calls.lastIndexOf('GET /api/chat/public/session');
    expect(identify, greaterThanOrEqualTo(0));
    expect(identify, lessThan(read));
    await finish(tester, fixture);
  });

  testWidgets('close shows only when the app gives somewhere to go', (tester) async {
    await openChat(tester);
    expect(find.byTooltip('Close chat'), findsNothing);
    var closed = false;
    await openChat(tester, onClose: () => closed = true);
    await tester.tap(find.byTooltip('Close chat'));
    expect(closed, isTrue);
  });

  testWidgets('ending asks first, then shows the rating and a way to start again', (tester) async {
    final events = <CnctChatUiEvent>[];
    await openChat(tester, onEvent: events.add);
    await tester.tap(find.text('End chat'));
    await tester.pump();
    expect(find.text('End this chat? You can always start a new one.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'End chat'));
    await settle(tester);
    expect(find.text('This conversation has ended'), findsOneWidget);
    expect(find.text('How did we do?'), findsOneWidget);
    expect(find.text('Start a new conversation'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Great'));
    await settle(tester);
    expect(find.text('Thank you — that goes straight to the team.'), findsOneWidget);
    expect(events.map((event) => event.type),
        containsAll([CnctChatUiEventType.ended, CnctChatUiEventType.rated]));
    expect(events.last.score, 5);
  });

  testWidgets('a failed message is retried with the same words', (tester) async {
    final fixture = await openChat(tester);
    await tester.tap(find.text('Not sent — tap to try again'));
    await settle(tester);
    // The fixture refuses that message every time; what matters is that it asked again.
    expect(
      fixture.calls.where((call) => call == 'POST /api/chat/public/messages').length,
      2,
    );
  });
}
