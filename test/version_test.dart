import 'dart:io';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:test/test.dart';

String versionIn(String pubspec) =>
    RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File(pubspec).readAsStringSync())![1]!;

void main() {
  test('the version the SDK reports is the version in pubspec.yaml', () {
    expect(CnctConfig.sdkVersion, versionIn('pubspec.yaml'));
    expect(CnctConfig().userAgent, 'cnct-flutter-sdk/${versionIn('pubspec.yaml')}');
  });

  test('the chat UI ships at the same version as the client it is built on', () {
    expect(versionIn('cnct_flutter_ui/pubspec.yaml'), versionIn('pubspec.yaml'));
  });
}
