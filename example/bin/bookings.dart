// The calendar, on an account-wide API key.
//
// **This credential belongs on a server.** It is deliberately read from the environment here rather
// than written into the file, because a key in a source file is a key in a repository.
import 'dart:io';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';

Future<void> main(List<String> arguments) async {
  final baseUrl = Platform.environment['CNCT_BASE_URL'];
  final apiKey = Platform.environment['CNCT_API_KEY'];
  if (baseUrl == null || apiKey == null) {
    stderr.writeln('Set CNCT_BASE_URL and CNCT_API_KEY.');
    exit(64);
  }

  final agent = Cnct.host(baseUrl).agent(CnctApiKey(apiKey));

  // What this account may do, and the rules it works under. Also the cheapest check that a key works.
  final catalogue = await agent.catalogue();
  stdout.writeln('This key opens: ${catalogue.tools.map((tool) => tool.name).join(', ')}');
  stdout.writeln('The clock is ${catalogue.rules.timezone}.');

  final services = await agent.bookings.services();
  for (final service in services.items) {
    stdout.writeln('  ${service.name} — ${service.minutes ?? catalogue.rules.slotMinutes} min');
  }
  if (services.isEmpty) stdout.writeln('  ${services.note ?? 'No named services.'}');

  final date = arguments.isNotEmpty
      ? arguments.first
      : DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10);

  final day = await agent.bookings.checkAvailability(date: date, partySize: 2);
  if (day.isEmpty) {
    // An empty day is an answer with a reason. "Nothing is free" and "no table seats six" send a
    // customer to different places, so the sentence is worth reading rather than discarding.
    stdout.writeln('$date: ${day.note ?? 'nothing free'}');
    agent.close();
    return;
  }

  stdout.writeln('$date is free at: ${day.free.map((slot) => slot.time).join(', ')}');

  final phone = Platform.environment['CNCT_CUSTOMER_PHONE'];
  if (phone == null) {
    stdout.writeln('Set CNCT_CUSTOMER_PHONE to actually book the first slot.');
    agent.close();
    return;
  }

  final booking = await agent.bookings.create(
    // Exactly as given. Rebuilding this from a parsed DateTime is how a booking lands on a time
    // nobody offered.
    startsAt: day.free.first.startsAt,
    customerPhone: phone,
    partySize: 2,
    name: 'Example',
    // False, because "Example" is not the owner of that phone number. Getting this wrong renames
    // somebody's contact record after whoever the booking was for.
    nameIsTheCaller: false,
  );
  stdout.writeln('Booked ${booking.bookingId} for ${booking.when}.');

  final theirs = await agent.bookings.forCustomer(phone);
  for (final existing in theirs.items) {
    stdout.writeln('  ${existing.bookingId}: ${existing.when}');
  }

  agent.close();
}
