import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

Widget _constrainedText(
  String text, {
  required int maxLines,
  required TextOverflow overflow,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 50,
        child: Text(text, maxLines: maxLines, overflow: overflow),
      ),
    ),
  );
}

class _CellWidget extends StatelessWidget {
  const _CellWidget({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 50,
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

TruncationIssue _issue({
  String text = 'hello',
  String overflowMode = 'ellipsis',
  int? maxLines,
}) => TruncationIssue(
  text: text,
  locale: 'en',
  overflowMode: overflowMode,
  availableWidth: 10,
  desiredWidth: 100,
  maxLines: maxLines,
);

void main() {
  group('TruncationIgnore', () {
    testWidgets('baseline: overflowing ellipsis is detected (no ignore)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _constrainedText(
          'A very long string that will be truncated',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en');
      expect(issues, hasLength(1));
    });

    testWidgets('byMaxLines ignores when maxLines <= n', (tester) async {
      await tester.pumpWidget(
        _constrainedText(
          'A very long string that will be truncated',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', [
        TruncationIgnores.byMaxLines(1),
      ]);
      expect(issues, isEmpty);
    });

    testWidgets('byMaxLines still reports when maxLines > n', (tester) async {
      await tester.pumpWidget(
        _constrainedText(
          'A very long string that will be truncated',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', [
        TruncationIgnores.byMaxLines(1),
      ]);
      expect(issues, hasLength(1));
    });

    testWidgets('byText ignores by regex match', (tester) async {
      await tester.pumpWidget(
        _constrainedText(
          'RCP-1234567890 some very long text here overflowing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', [
        TruncationIgnores.byText(RegExp(r'^RCP-')),
      ]);
      expect(issues, isEmpty);
    });

    testWidgets('byWidgetType ignores only the matching widget type', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              const _CellWidget(
                text: 'A very long string that overflows in a cell',
              ),
              _constrainedText(
                'Another long string that also overflows here',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', [
        TruncationIgnores.byWidgetType(_CellWidget),
      ]);
      expect(issues, hasLength(1));
      expect(issues.first.text, contains('Another'));
    });

    testWidgets('byKey ignores by key, wrong key still reported', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              _CellWidget(
                key: Key('brand'),
                text: 'RCP-1234567890 long text overflow',
              ),
              _CellWidget(
                key: Key('other'),
                text: 'INV-1234567890 long text overflow',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', [
        TruncationIgnores.byKey(const Key('brand')),
      ]);
      expect(issues, hasLength(1));
      expect(issues.first.text, contains('INV-'));
    });

    testWidgets('any combines rules; ignore when any matches', (tester) async {
      await tester.pumpWidget(
        _constrainedText(
          'INV-1234567890 long text overflow',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', [
        TruncationIgnores.any([
          TruncationIgnores.byMaxLines(1), // does not match (maxLines 2)
          TruncationIgnores.byText(RegExp(r'^INV-')), // matches
        ]),
      ]);
      expect(issues, isEmpty);
    });

    testWidgets('issue-only predicate works without debugCreator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _constrainedText(
          'A very long string that overflows',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', [
        (issue, _) => issue.maxLines != null,
      ]);
      expect(issues, isEmpty);
    });

    test('fromConfig matches only when all specified fields match', () {
      final rules = [
        {'max_lines': 2},
        {'text_regex': r'^(RCP-|INV-)'},
        {'overflow': 'ellipsis'},
      ];
      final ignore = TruncationIgnores.any(
        rules.map(TruncationIgnores.fromConfig).toList(),
      );

      expect(ignore(_issue(maxLines: 1), null), isTrue); // max_lines
      expect(ignore(_issue(text: 'RCP-9'), null), isTrue); // text_regex
      expect(
        ignore(_issue(overflowMode: 'ellipsis'), null),
        isTrue,
      ); // overflow
      expect(
        ignore(_issue(text: 'hello', maxLines: 5, overflowMode: 'clip'), null),
        isFalse,
      );
    });

    test(
      'fromConfig skips a rule with no recognized keys (does not ignore all)',
      () {
        final ignore = TruncationIgnores.fromConfig({'overflw': 'ellipsis'});
        expect(ignore(_issue(maxLines: 1), null), isFalse);
      },
    );

    test('fromConfig skips an empty rule (does not ignore all)', () {
      final ignore = TruncationIgnores.fromConfig({});
      expect(ignore(_issue(maxLines: 1), null), isFalse);
    });

    test('fromConfig skips a rule with a wrong-typed value', () {
      final ignore = TruncationIgnores.fromConfig({'max_lines': 'two'});
      expect(ignore(_issue(maxLines: 1), null), isFalse);
    });

    test(
      'fromConfig skips a rule with an invalid text_regex without throwing',
      () {
        final ignore = TruncationIgnores.fromConfig({'text_regex': '(['});
        expect(() => ignore(_issue(text: 'anything'), null), returnsNormally);
        expect(ignore(_issue(text: 'anything'), null), isFalse);
      },
    );

    test(
      'fromConfig skips a rule with an unknown key (a typo must not widen it)',
      () {
        // A misspelled `text_regexp` next to `max_lines` used to leave
        // `max_lines` in force, silently ignoring every short truncation.
        final ignore = TruncationIgnores.fromConfig({
          'max_lines': 2,
          'text_regexp': r'^RCP-',
        });
        expect(ignore(_issue(maxLines: 1, text: 'anything'), null), isFalse);
      },
    );

    test('fromConfig skips a rule with an unsupported overflow value', () {
      final ignore = TruncationIgnores.fromConfig({'overflow': 'ellipses'});
      expect(ignore(_issue(overflowMode: 'ellipsis'), null), isFalse);
    });

    test('fromConfig accepts every supported overflow value', () {
      for (final mode in ['ellipsis', 'clip', 'fade', 'visible']) {
        final ignore = TruncationIgnores.fromConfig({'overflow': mode});
        expect(ignore(_issue(overflowMode: mode), null), isTrue, reason: mode);
      }
    });

    test('SweepConfig.load parses truncation_ignore from YAML', () {
      final dir = Directory.systemTemp.createTempSync('lsweep_cfg_');
      final file = File('${dir.path}/locale_sweep.yaml');
      file.writeAsStringSync('''
truncation_ignore:
  - max_lines: 2
  - text_regex: "^(RCP-|INV-)"
  - overflow: ellipsis
''');
      final config = SweepConfig.load(file.path);
      expect(config.truncationIgnoreRaw, isNotNull);
      expect(config.truncationIgnoreRaw, hasLength(3));
      expect(config.truncationIgnoreRaw!.first['max_lines'], 2);
      expect(config.truncationIgnoreRaw!.last['overflow'], 'ellipsis');
      dir.deleteSync(recursive: true);
    });

    testWidgets('YAML rules are applied through detect', (tester) async {
      // Sync I/O: async file ops never complete under testWidgets' fake clock.
      final dir = Directory.systemTemp.createTempSync('lsweep_yaml_');
      final file = File('${dir.path}/locale_sweep.yaml');
      file.writeAsStringSync('''
truncation_ignore:
  - max_lines: 2
''');
      final config = SweepConfig.load(file.path);
      final ignores = [
        ...?config.truncationIgnoreRaw?.map(TruncationIgnores.fromConfig),
      ];

      await tester.pumpWidget(
        _constrainedText(
          'A very long string that overflows',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpAndSettle();

      final issues = TruncationDetector.detect(tester, 'en', ignores);
      expect(issues, isEmpty);
      dir.deleteSync(recursive: true);
    });
  });
}
