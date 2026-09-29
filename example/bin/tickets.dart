// Raise a ticket, then answer the customer who comes back about it — on an account-wide API key.
//
// **This credential belongs on a server.** The account needs ticketing and at least one ticket
// type. Run it with a sandbox key (`kaer_sk_test_…`) and the ticket is kept in the sandbox: nobody
// works it, and the business never sees it.
import 'dart:io';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';

Future<void> main() async {
  // Optional: without it the SDK goes to CNCT production, https://app.doo.ooo.
  final baseUrl = Platform.environment['CNCT_BASE_URL'];
  final apiKey = Platform.environment['CNCT_API_KEY'];
  if (apiKey == null) {
    stderr.writeln('Set CNCT_API_KEY.');
    exit(64);
  }
  final phone = Platform.environment['CNCT_CUSTOMER_PHONE'] ?? '+97312345678';

  final cnct = baseUrl == null ? Cnct() : Cnct.host(baseUrl);
  final agent = cnct.agent(CnctApiKey(apiKey));

  try {
    // 1. What kinds of work this business hands over, and what the first one needs.
    final types = await agent.tickets.types();
    if (types.isEmpty) {
      stdout.writeln(types.refusal ?? 'No ticket types are set up on this account.');
      return;
    }
    final type = await agent.tickets.type(types.items.first.ticketTypeId);
    final fields = {
      for (final field in type.askFor.where((field) => field.isRequired))
        field.key: field.mustBeOneOf.isNotEmpty ? field.mustBeOneOf.first : 'example',
    };

    // 2. Raise one. The idempotency key makes a retry return this ticket rather than a second.
    final raised = await agent.tickets.create(
      ticketTypeId: type.ticketTypeId,
      title: 'Example from the SDK',
      reasonUnresolved: 'Needs somebody on site',
      customerPhone: phone,
      fields: fields,
      idempotencyKey: 'sdk-example-${DateTime.now().toIso8601String().substring(0, 10)}',
    );
    stdout.writeln('Raised #${raised.ticketNumber}${raised.sandbox ? ' (sandbox)' : ''}');

    // 3. Later: "any news?" Find it by their number, then read it as they may see it.
    final open = await agent.tickets.forCustomer(phone);
    stdout.writeln('They have ${open.length} open.');
    final ticket = await agent.tickets.get(phone, raised.ticketNumber);
    stdout.writeln('#${ticket.ticketNumber} is ${ticket.status}');
    for (final line in ticket.history) {
      stdout.writeln('  ${line.on}  ${line.what}');
    }

    // 4. They add something. It goes on the ticket, not into a second one.
    final added = await agent.tickets.addTo(
      customerPhone: phone,
      ticketNumber: ticket.ticketNumber,
      note: 'It is worse this morning',
    );
    stdout.writeln(added.resumed ? 'Passed on, and it is moving again.' : 'Passed on.');
  } on CnctException catch (error) {
    // A tool that declines answers in a sentence rather than a status code.
    if (error.code != CnctErrorCode.toolRefused) rethrow;
    stdout.writeln('Refused: ${error.message}');
  } finally {
    agent.close();
  }
}
