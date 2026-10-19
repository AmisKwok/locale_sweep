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

    testWidgets(
      'horizontal overflow with softWrap false and no maxLines is reported',
      (tester) async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 50,
                child: Text(
                  'Benachrichtigungseinstellungen',
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ),
          ),
        );

        final issues = TruncationDetector.detect(tester, 'en');
        expect(issues, hasLength(1));
        expect(issues.single.overflowMode, 'fade');
      },
    );
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
}
