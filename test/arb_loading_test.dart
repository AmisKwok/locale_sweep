import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

void main() {
  group('ArbAnalyzer loading', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('arb_loading_'));

    tearDown(() => dir.deleteSync(recursive: true));

    void write(String name, String content) =>
        File('${dir.path}/$name').writeAsStringSync(content);

    void writeJson(String name, Map<String, dynamic> content) =>
        write(name, jsonEncode(content));

    test('reports a parseError instead of passing on a broken base ARB', () {
      write('app_en.arb', '{not valid json');
      writeJson('app_de.arb', {'title': 'Titel'});

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      // The base file is unusable, so the run must not report "all good".
      expect(report.hasIssues, isTrue);
      expect(
        report.issues.any(
          (i) => i.type == ArbIssueType.parseError && i.locale == 'en',
        ),
        isTrue,
      );
    });

    test('does not flood missingKey for a locale with a broken ARB', () {
      writeJson('app_en.arb', {'title': 'Title', 'subtitle': 'Subtitle'});
      write('app_de.arb', '{"title": ');

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      expect(
        report.issues.where((i) => i.type == ArbIssueType.missingKey),
        isEmpty,
        reason: 'A broken file is unreadable, not empty',
      );
      expect(
        report.issues.where((i) => i.type == ArbIssueType.parseError),
        hasLength(1),
      );
    });

    test('extracts script, region and numeric region subtags', () {
      writeJson('app_zh_Hans.arb', {'title': '标题'});
      writeJson('app_zh_Hant_CN.arb', {'title': '標題'});
      writeJson('app_es_419.arb', {'title': 'Título'});
      writeJson('app_fil.arb', {'title': 'Pamagat'});
      writeJson('en.arb', {'title': 'Title'});
      writeJson('app_en-US.arb', {'title': 'Title (US)'});

      final messages = ArbAnalyzer.loadMessages(dir.path);

      expect(messages.keys, containsAll(['zh_Hans', 'zh_Hant_CN', 'es_419']));
      expect(messages.keys, containsAll(['fil', 'en']));
    });

    test('reports a placeholder that only exists in the target', () {
      writeJson('app_en.arb', {
        'greeting': 'Hello {name}',
        '@greeting': {
          'placeholders': {
            'name': {'type': 'String'},
          },
        },
      });
      writeJson('app_de.arb', {'greeting': 'Hallo {nmae}'});

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      final mismatches = report.issues
          .where((i) => i.type == ArbIssueType.placeholderMismatch)
          .toList();
      expect(mismatches, hasLength(2));
      expect(mismatches.map((i) => i.detail), contains(contains('{name}')));
      expect(mismatches.map((i) => i.detail), contains(contains('{nmae}')));
    });

    test('falls back to the base message when metadata is missing', () {
      // No `@greeting` metadata — the placeholder check used to be skipped.
      writeJson('app_en.arb', {'greeting': 'Hello {name}'});
      writeJson('app_de.arb', {'greeting': 'Hallo!'});

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      expect(
        report.issues.where((i) => i.type == ArbIssueType.placeholderMismatch),
        hasLength(1),
      );
    });

    test('does not mistake ICU branch bodies for placeholders', () {
      writeJson('app_en.arb', {
        'mood': '{choice, select, good{Great} other{Ok}}',
        '@mood': {
          'placeholders': {
            'choice': {'type': 'String'},
          },
        },
      });
      writeJson('app_de.arb', {
        'mood': '{choice, select, good{Super} other{Okay}}',
      });

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      expect(
        report.issues.where((i) => i.type == ArbIssueType.placeholderMismatch),
        isEmpty,
      );
    });

    test('does not treat spaced ICU branch bodies as placeholders', () {
      // `male {he}` is the spacing used in Flutter's gen-l10n docs.
      writeJson('app_en.arb', {
        'pronoun': '{gender, select, male {he} female {she} other {they}}',
      });
      writeJson('app_de.arb', {
        'pronoun': '{gender, select, male {er} female {sie} other {sie}}',
      });

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      expect(
        report.issues.where((i) => i.type == ArbIssueType.placeholderMismatch),
        isEmpty,
      );
    });

    test('finds arguments nested inside plural branches', () {
      writeJson('app_en.arb', {
        'items': '{count, plural, =0{No items} other{{count} items}}',
      });
      writeJson('app_de.arb', {
        'items': '{count, plural, =0{Keine} other{{count} Artikel}}',
      });

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      expect(
        report.issues.where((i) => i.type == ArbIssueType.placeholderMismatch),
        isEmpty,
      );
    });

    test('still reports a dropped argument inside a spaced branch', () {
      writeJson('app_en.arb', {
        'greeting': '{gender, select, male {Mr {name}} other {{name}}}',
      });
      writeJson('app_de.arb', {
        'greeting': '{gender, select, male {Herr} other {Hallo}}',
      });

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      final mismatches = report.issues
          .where((i) => i.type == ArbIssueType.placeholderMismatch)
          .toList();
      expect(mismatches, hasLength(1));
      expect(mismatches.single.detail, contains('{name}'));
    });

    test('escapes placeholder names that contain regex metacharacters', () {
      writeJson('app_en.arb', {
        'path': 'File {file.name}',
        '@path': {
          'placeholders': {
            'file.name': {'type': 'String'},
          },
        },
      });
      writeJson('app_de.arb', {'path': 'Datei {file.name}'});

      final report = ArbAnalyzer.analyze(
        arbDir: dir.path,
        locales: ['de'],
        baseLocale: 'en',
      );

      expect(
        report.issues.where((i) => i.type == ArbIssueType.placeholderMismatch),
        isEmpty,
        reason: '{file.name} is present in both locales',
      );
    });
  });

  group('ArbMessageMatcher', () {
    test('a truncated ICU message does not match every string', () {
      // Missing its closing brace: a pure-wildcard fallback used to match
      // anything, silently disabling hardcoded detection for that locale.
      final matcher = ArbMessageMatcher.fromMessages([
        '{count, plural, one{# item} other{# items}',
      ]);

      expect(matcher.matches('Unrelated copy'), isFalse);
      expect(matcher.matches('3 items'), isFalse);
    });

    test('argumentNames skips spaced and unspaced branch bodies', () {
      expect(
        ArbMessageMatcher.argumentNames(
          '{gender, select, male {he} female {she} other {they}}',
        ),
        {'gender'},
      );
      expect(
        ArbMessageMatcher.argumentNames(
          '{gender, select, male{he} female{she} other{they}}',
        ),
        {'gender'},
      );
      expect(
        ArbMessageMatcher.argumentNames(
          '{count, plural, =0{No items} other{{count} items}}',
        ),
        {'count'},
      );
    });
  });
}
