import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

void main() {
  group('ARB untranslated allowlist', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('locale_sweep_arb_');
      File('${dir.path}/app_en.arb').writeAsStringSync(
        jsonEncode({
          'appName': 'App {v}',
          '@appName': {
            'placeholders': {'v': <String, dynamic>{}},
          },
          'brand': 'Same',
          'onlyEn': 'Only in English',
        }),
      );
      File(
        '${dir.path}/app_zh.arb',
      ).writeAsStringSync(jsonEncode({'appName': 'App', 'brand': 'Same'}));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('reports untranslated, missing key and placeholder mismatch', () {
      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: const ['zh'],
        baseLocale: 'en',
      );

      expect(
        report.issues.map((i) => i.type),
        containsAll([
          ArbIssueType.untranslated,
          ArbIssueType.missingKey,
          ArbIssueType.placeholderMismatch,
        ]),
      );
    });

    test('allowlist exempts only untranslated issues', () {
      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: const ['zh'],
        baseLocale: 'en',
        untranslatedAllowlist: const ['brand', 'appName', 'onlyEn'],
      );

      final types = report.issues.map((i) => i.type).toList();
      expect(types, isNot(contains(ArbIssueType.untranslated)));
      expect(types, contains(ArbIssueType.missingKey));
      expect(types, contains(ArbIssueType.placeholderMismatch));
    });
  });
}
