/// Regression tests for the local patches documented in `PATCHES.md`.
///
/// Run from this package directory:
///
/// ```sh
/// fvm flutter pub get
/// fvm flutter test
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

const _variant = SweepVariant(
  locale: 'en',
  textScale: 1.0,
  viewport: ViewportPreset.phone,
);

SweepResult _result({
  bool passed = true,
  List<OverflowError> overflows = const [],
  List<TruncationIssue> truncations = const [],
}) {
  return SweepResult(
    flowName: 'flow',
    variant: _variant,
    passed: passed,
    overflows: overflows,
    truncations: truncations,
  );
}

TruncationIssue _truncation() => const TruncationIssue(
  text: 'a truncated label',
  locale: 'en',
  overflowMode: 'ellipsis',
  availableWidth: 100,
  desiredWidth: 160,
  maxLines: 1,
);

void main() {
  group('truncation detection', () {
    testWidgets('wrapping text without maxLines is not truncation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              child: Text('a very long text that has to wrap across lines'),
            ),
          ),
        ),
      );

      expect(TruncationDetector.detect(tester, 'en'), isEmpty);
    });

    testWidgets('maxLines: 1 with ellipsis is reported', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              child: Text(
                'a very long text that cannot fit on a single line',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );

      final issues = TruncationDetector.detect(tester, 'en');
      expect(issues, hasLength(1));
      expect(issues.single.maxLines, 1);
    });

    testWidgets('horizontal overflow with softWrap false is reported', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 50,
              child: Text(
                'Fading text that is too wide for this container',
                overflow: TextOverflow.fade,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ),
      );

      final issues = TruncationDetector.detect(tester, 'en');
      expect(issues, hasLength(1));
      expect(issues.single.overflowMode, 'fade');
    });
  });

  group('passed semantics', () {
    test('truncations are advisory', () {
      final result = _result(truncations: [_truncation()]);

      expect(result.hasIssues, isTrue);
      expect(result.hasGatingIssues, isFalse);
      expect(result.toJson()['passed'], isTrue);

      final summary = SweepRunSummary(results: [result]);
      expect(summary.passed, 1);
      expect(summary.failed, 0);
      expect(summary.advisories, hasLength(1));
    });

    test('overflows gate the variant', () {
      final result = _result(
        passed: false,
        overflows: const [OverflowError(message: 'overflowed')],
      );

      expect(result.hasGatingIssues, isTrue);
      expect(result.toJson()['passed'], isFalse);
      expect(SweepRunSummary(results: [result]).failed, 1);
    });
  });

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
      File('${dir.path}/app_zh.arb').writeAsStringSync(
        jsonEncode({'appName': 'App', 'brand': 'Same'}),
      );
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

  group('builderWithVariant', () {
    test('requires exactly one builder', () {
      expect(() => sweepTest('neither'), throwsArgumentError);
      expect(
        () => sweepTest(
          'both',
          builder: () => const SizedBox.shrink(),
          builderWithVariant: (variant) => const SizedBox.shrink(),
        ),
        throwsArgumentError,
      );
    });

    SweepVariant? seen;

    sweepTest(
      'variant-builder',
      builderWithVariant: (variant) {
        seen = variant;
        return const SizedBox.shrink();
      },
      locales: const ['en'],
      textScales: const [1.0],
      viewports: const [ViewportPreset.phone],
      captureScreenshots: false,
    );

    tearDownAll(() {
      final file = File('.locale_sweep/results/variant-builder.json');
      if (file.existsSync()) file.deleteSync();
    });

    test('receives the current variant', () {
      expect(seen?.locale, 'en');
      expect(seen?.textScale, 1.0);
    });
  });
}
