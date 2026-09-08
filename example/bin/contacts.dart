// The contact directory, on an operator's login.
//
// A person's credential, eight hours long. Right for a back-office tool run by staff; wrong for
// anything a customer holds.
import 'dart:io';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';

Future<void> main(List<String> arguments) async {
  final baseUrl = Platform.environment['CNCT_BASE_URL'];
  final email = Platform.environment['CNCT_EMAIL'];
  final password = Platform.environment['CNCT_PASSWORD'];
  if (baseUrl == null || email == null || password == null) {
    stderr.writeln('Set CNCT_BASE_URL, CNCT_EMAIL and CNCT_PASSWORD.');
    exit(64);
  }

  final cnct = Cnct.host(baseUrl);
  final auth = cnct.auth;

  CnctOperatorSession session;
  try {
    final result = await auth.login(
      email: email,
      password: password,
      organizationSlug: Platform.environment['CNCT_ORG_SLUG'],
    );
    if (result.challenge != null) {
      // An ordinary path rather than an error: the account has a second factor switched on.
      stdout.write('${result.challenge!.method} code: ');
      final code = stdin.readLineSync()?.trim() ?? '';
      session = await auth.verifyMfa(mfaToken: result.challenge!.mfaToken, code: code);
    } else {
      session = result.session!;
    }
  } on CnctChooseOrganization catch (choice) {
    // They have a seat in more than one account and have to say which.
    stderr.writeln('Set CNCT_ORG_SLUG to one of: '
        '${choice.organizations.map((organization) => organization.slug).join(', ')}');
    auth.close();
    exit(64);
  }

  stdout.writeln('Signed in to ${session.organizationName} as ${session.email} (${session.role}).');
  auth.close();

  final contacts = cnct.contacts(session.credentials);

  final page = await contacts.list(query: arguments.isNotEmpty ? arguments.first : null, limit: 20);
  stdout.writeln('${page.contacts.length} of ${page.total}:');
  for (final contact in page.contacts) {
    final tags = contact.tags.map((tag) => tag.name).join(', ');
    stdout.writeln('  ${contact.displayName}${tags.isEmpty ? '' : '  [$tags]'}');
  }
  // Null is the end of the list, and the only reliable one — a short page never issues a cursor.
  if (page.hasMore) stdout.writeln('  … more, from cursor ${page.nextCursor}');

  contacts.close();
}
