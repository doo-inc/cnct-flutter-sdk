// A whole conversation, in a terminal.
//
// Shows the chat credential end to end: boot the inbox, start as a visitor, listen to state, send
// something, and read what comes back. No Flutter, no widgets — this is the SDK's actual surface.
import 'dart:io';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';

Future<void> main() async {
  final baseUrl = Platform.environment['CNCT_BASE_URL'];
  final publicKey = Platform.environment['CNCT_PUBLIC_KEY'];
  if (baseUrl == null || publicKey == null) {
    stderr.writeln('Set CNCT_BASE_URL and CNCT_PUBLIC_KEY.');
    exit(64);
  }

  final chat = Cnct.host(baseUrl).chat(CnctChatPublicKey(publicKey));

  // A terminal has no localStorage, and this example does not want a session to outlive it anyway.
  // An app would pass a persistent store here — see flutter_app/lib/token_store.dart.
  chat.events.listen((event) {
    switch (event) {
      case CnctChatConnected():
        stdout.writeln('· connected');
      case CnctChatDisconnected():
        stdout.writeln('· dropped, reconnecting');
      case CnctChatMessageReceived(:final message) when message.speaker != CnctSpeaker.caller:
        stdout.writeln('${message.speaker.name}: ${message.body}');
      case CnctChatClosed():
        stdout.writeln('· the conversation was closed');
      case CnctChatErrored(:final error):
        stderr.writeln('· ${error.code}: ${error.message}');
      default:
        break;
    }
  });

  final inbox = await chat.boot();
  stdout.writeln('${inbox.business} — ${inbox.inbox}');
  if (!inbox.isActive) {
    stdout.writeln('This inbox is switched off, so there is nothing to type into.');
    chat.dispose();
    return;
  }
  stdout.writeln(inbox.greeting);

  stdout.write('Your name: ');
  final name = stdin.readLineSync()?.trim();
  // `requirePhone` is the inbox asking for a number before anybody types. Passing one is also what
  // joins this conversation to the contact record the business already has.
  String? phone;
  if (inbox.requirePhone) {
    stdout.write('Your phone number (+973…): ');
    phone = stdin.readLineSync()?.trim();
  }

  await chat.start(displayName: name?.isNotEmpty == true ? name : 'Visitor', phone: phone);
  stdout.writeln('· type a message, or "bye" to end');

  while (true) {
    stdout.write('> ');
    final line = stdin.readLineSync();
    if (line == null || line.trim().toLowerCase() == 'bye') break;
    if (line.trim().isEmpty) continue;
    try {
      await chat.send(line);
    } on CnctException catch (error) {
      // The bubble is still in state, marked failed. A UI would draw a retry button here.
      stderr.writeln('· not sent (${error.code}). Retrying once…');
      final failed = chat.state.failed;
      if (failed.isNotEmpty && error.isRetryable) {
        try {
          await chat.retry(failed.last.clientKey!);
        } on CnctException catch (again) {
          stderr.writeln('· still not sent: ${again.message}');
        }
      }
    }
  }

  await chat.end();
  chat.dispose();
}
