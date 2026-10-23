import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

const _messages = {
  'en': {
    'title': 'Settings',
    'greeting': 'Hello, {name}',
    'items': '{count, plural, =0{No items} one{# item} other{# items}}',
    'mood': '{mood, select, happy{Feeling great} other{Feeling okay}}',
    'onlyBase': 'Only in English',
  },
  'de': {
    'title': 'Einstellungen',
    'greeting': 'Hallo, {name}',
    'items': '{count, plural, =0{Keine} one{# Element} other{# Elemente}}',
    'mood': '{mood, select, happy{Super} other{Okay}}',
  },
};

Widget _texts(List<String> texts) => Directionality(
  textDirection: TextDirection.ltr,
  child: Column(children: [for (final t in texts) Text(t)]),
);

List<String> _detect(
  WidgetTester tester, {
  String locale = 'en',
  List<String> allowlist = const [],
}) =>
    HardcodedTextDetector(
          messages: _messages,
          baseLocale: 'en',
          allowlist: allowlist,
        )
        .detect(tester, locale: locale, renderLocale: locale)
        .map((i) => i.text)
        .toList();

void main() {
  group('ArbMessageMatcher', () {
    final matcher = ArbMessageMatcher.fromMessages(_messages['en']!.values);

    test('matches literal messages exactly', () {
      expect(matcher.matches('Settings'), isTrue);
      expect(matcher.matches('  Settings '), isTrue);
      expect(matcher.matches('Settings page'), isFalse);
    });

    test('placeholders match any text', () {
      expect(matcher.matches('Hello, Piyush'), isTrue);
      expect(matcher.matches('Goodbye, Piyush'), isFalse);
    });

    test('plural branches match, with # as the count', () {
      expect(matcher.matches('No items'), isTrue);
      expect(matcher.matches('1 item'), isTrue);
      expect(matcher.matches('42 items'), isTrue);
      expect(matcher.matches('42 things'), isFalse);
    });

    test('select branches match', () {
      expect(matcher.matches('Feeling great'), isTrue);
      expect(matcher.matches('Feeling okay'), isTrue);
      expect(matcher.matches('Feeling bad'), isFalse);
    });

    test('nested arguments inside branches', () {
      final m = ArbMessageMatcher.fromMessages([
        '{count, plural, one{{name} has # cat} other{{name} has # cats}}',
      ]);
      expect(m.matches('Ana has 3 cats'), isTrue);
      expect(m.matches('Ana has 1 cat'), isTrue);
      expect(m.matches('Ana has dogs'), isFalse);
    });

    test('formatted arguments match any text', () {
      final m = ArbMessageMatcher.fromMessages(['Due {date, date, short}']);
      expect(m.matches('Due 1/2/26'), isTrue);
    });

    test('regex characters in messages are literal', () {
      final m = ArbMessageMatcher.fromMessages(['Price (USD): {amount}?']);
      expect(m.matches('Price (USD): 42?'), isTrue);
      expect(m.matches('Price USD: 42'), isFalse);
    });

    test('malformed messages fall back to an exact match', () {
      expect(ArbMessageMatcher.toPattern('Broken {name'), isNull);
      expect(ArbMessageMatcher.toPattern('Stray } brace'), isNull);
      expect(ArbMessageMatcher.toPattern('{n, plural, }'), isNull);
      final m = ArbMessageMatcher.fromMessages(['Broken {name']);
      expect(m.matches('Broken {name'), isTrue);
    });
  });

  group('HardcodedTextDetector', () {
    testWidgets('reports only text missing from the ARB messages', (
      tester,
    ) async {
      await tester.pumpWidget(
        _texts(['Settings', 'Hello, Piyush', '3 items', 'Buy now']),
      );
      expect(_detect(tester), ['Buy now']);
    });

    testWidgets('uses the rendered locale and falls back to the base', (
      tester,
    ) async {
      await tester.pumpWidget(
        _texts(['Einstellungen', '2 Elemente', 'Only in English', 'Settings']),
      );
      // Base-locale strings are accepted too, because Flutter shows them for
      // keys a translation is missing.
      expect(_detect(tester, locale: 'de'), isEmpty);
    });

    testWidgets('regional locales fall back to their language', (tester) async {
      await tester.pumpWidget(_texts(['Einstellungen', 'Jetzt kaufen']));
      expect(_detect(tester, locale: 'de-AT'), ['Jetzt kaufen']);
    });

    testWidgets('ignores numbers, punctuation and icons', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Text('42'),
              Text('12:30'),
              Text('—'),
              Icon(Icons.settings),
            ],
          ),
        ),
      );
      expect(_detect(tester), isEmpty);
    });

    testWidgets('allowlist patterns are skipped', (tester) async {
      await tester.pumpWidget(_texts(['TaskFlow', 'Piyush Kumar', 'Buy now']));
      expect(_detect(tester, allowlist: ['^TaskFlow\$', 'Kumar']), ['Buy now']);
    });

    testWidgets('reports each string once per variant', (tester) async {
      await tester.pumpWidget(_texts(['Buy now', 'Buy now']));
      expect(_detect(tester), ['Buy now']);
    });

    testWidgets('invalid allowlist patterns are skipped, not fatal', (
      tester,
    ) async {
      await tester.pumpWidget(_texts(['Buy now']));
      expect(_detect(tester, allowlist: ['(unclosed']), ['Buy now']);
    });
  });

  group('sweepTest hardcoded text detection', () {
    final arbDir = Directory.systemTemp.createTempSync('lsweep_hardcoded_');
    for (final MapEntry(key: locale, value: messages) in _messages.entries) {
      File(
        '${arbDir.path}/app_$locale.arb',
      ).writeAsStringSync(jsonEncode({...messages}..remove('onlyBase')));
    }

    sweepTest(
      'hardcoded_flow',
      builder: () => Builder(
        builder: (context) {
          final german =
              Localizations.maybeLocaleOf(context)?.languageCode == 'de' ||
              WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
                  'de';
          return Column(
            children: [
              Text(german ? 'Einstellungen' : 'Settings'),
              const Text('Buy now'),
            ],
          );
        },
      ),
      locales: ['en', 'de', pseudoLocale],
      textScales: [1.0],
      viewports: [ViewportPreset.phone],
      arbDir: arbDir.path,
      detectHardcodedText: true,
      captureScreenshots: false,
    );

    tearDownAll(() {
      arbDir.deleteSync(recursive: true);
      final results = {
        for (final r in sweepResults.where(
          (r) => r.flowName == 'hardcoded_flow',
        ))
          r.variant.locale: r,
      };
      expect(results.keys, unorderedEquals(['en', 'de', pseudoLocale]));
      for (final r in results.values) {
        expect(r.hardcodedTexts.map((h) => h.text), ['Buy now']);
        expect(r.hardcodedTexts.single.locale, r.variant.locale);
        expect(r.hasGatingIssues, isFalse, reason: 'hardcoded is advisory');
        expect(r.hasAdvisories, isTrue);
      }
    });
  });

  test('detection without an ARB directory is a configuration error', () {
    expect(
      () => sweepTest(
        'no_arb',
        builder: () => const SizedBox(),
        config: const SweepConfig(),
        detectHardcodedText: true,
      ),
      throwsArgumentError,
    );
  });

  group('results, CLI and reports', () {
    const variant = SweepVariant(
      locale: 'de',
      textScale: 1.0,
      viewport: ViewportPreset.phone,
    );
    const result = SweepResult(
      flowName: 'home',
      variant: variant,
      passed: true,
      hardcodedTexts: [HardcodedTextIssue(text: 'Buy now', locale: 'de')],
    );

    ParsedReport report(List<SweepResult> results) => ParsedReport(
      markdown: '',
      json: '',
      html: '',
      summary: '',
      total: results.length,
      passed: results.length,
      failed: 0,
      results: results,
    );

    test('JSON round trip keeps hardcoded texts and the render locale', () {
      const pseudo = SweepResult(
        flowName: 'home',
        variant: SweepVariant(
          locale: pseudoLocale,
          textScale: 1.0,
          viewport: ViewportPreset.phone,
          renderLocale: 'ar',
        ),
        passed: true,
        hardcodedTexts: [HardcodedTextIssue(text: 'Buy', locale: 'pseudo')],
      );
      final restored = SweepResult.fromJson(
        jsonDecode(jsonEncode(pseudo.toJson())) as Map<String, dynamic>,
      );
      expect(restored.hardcodedTexts.single.text, 'Buy');
      expect(restored.variant.renderLocale, 'ar');
      expect(restored.variant.isRtl, isTrue);
      expect(restored.toJson()['passed'], isTrue);
    });

    test('older result files without hardcoded texts still load', () {
      final json = result.toJson()..remove('hardcodedTexts');
      expect(SweepResult.fromJson(json).hardcodedTexts, isEmpty);
    });

    test('--fail-on hardcoded and all fail; other categories do not', () {
      expect(shouldFail(report([result]), {'hardcoded'}), isTrue);
      expect(shouldFail(report([result]), {'all'}), isTrue);
      expect(shouldFail(report([result]), {'truncation'}), isFalse);
      expect(shouldFail(report([result]), {'none'}), isFalse);
    });

    test(
      'Markdown lists hardcoded text and adds the column only when used',
      () {
        final withFindings = ReportGenerator.generateMarkdown(
          SweepRunSummary(results: [result]),
        );
        expect(withFindings, contains('1 hardcoded text(s) recorded'));
        expect(withFindings, contains('## Advisory Findings'));
        expect(withFindings, contains('Hardcoded text: "Buy now"'));
        expect(withFindings, contains('| Hardcoded |'));

        const clean = SweepResult(
          flowName: 'home',
          variant: variant,
          passed: false,
          overflows: [OverflowError(message: 'overflowed by 4px', pixels: 4)],
        );
        final without = ReportGenerator.generateMarkdown(
          SweepRunSummary(results: [clean]),
        );
        expect(without, isNot(contains('Hardcoded')));
      },
    );

    test('HTML and JSON report hardcoded counts', () {
      final summary = SweepRunSummary(results: [result]);
      expect(ReportGenerator.generateHtml(summary), contains('Hardcoded'));
      final json =
          jsonDecode(ReportGenerator.generateJson(summary))
              as Map<String, dynamic>;
      expect(json['hardcodedTexts'], 1);
    });

    test('YAML config enables detection with an allowlist', () {
      final dir = Directory.systemTemp.createTempSync('lsweep_cfg_');
      final file = File('${dir.path}/locale_sweep.yaml')
        ..writeAsStringSync('''
hardcoded_text: true
hardcoded_text_allowlist:
  - "^TaskFlow\$"
''');
      final cfg = SweepConfig.load(file.path);
      dir.deleteSync(recursive: true);
      expect(cfg.hardcodedText, isTrue);
      expect(cfg.hardcodedTextAllowlist, [r'^TaskFlow$']);
      expect(const SweepConfig().hardcodedText, isFalse);
    });
  });
}
