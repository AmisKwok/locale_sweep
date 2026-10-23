import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'arb_message_matcher.dart';
import 'hardcoded_text_issue.dart';
import 'pseudo_localizer.dart';

export 'hardcoded_text_issue.dart';

/// Finds rendered text that does not come from the ARB files.
///
/// Each visible string is matched against the messages of the rendered
/// locale, its language (`pt` for `pt_BR`) and the base locale, mirroring how
/// Flutter falls back to missing translations. Text without letters, icon
/// glyphs and strings matching [allowlist] are ignored.
class HardcodedTextDetector {
  final Map<String, Map<String, String>> _messages;
  final String _baseLocale;
  final List<RegExp> _allowlist;
  final _matchers = <String, ArbMessageMatcher>{};

  HardcodedTextDetector({
    required Map<String, Map<String, String>> messages,
    required String baseLocale,
    List<String> allowlist = const [],
  }) : _messages = messages,
       _baseLocale = _normalize(baseLocale),
       _allowlist = _compile(allowlist);

  /// Detects hardcoded text in the current widget tree.
  ///
  /// [locale] labels the issues; [renderLocale] selects the ARB messages.
  List<HardcodedTextIssue> detect(
    WidgetTester tester, {
    required String locale,
    required String renderLocale,
  }) {
    final root = tester.binding.rootElement?.renderObject;
    if (root == null) return const [];
    final matcher = _matcherFor(_normalize(renderLocale));
    final seen = <String>{};
    final issues = <HardcodedTextIssue>[];

    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        final text = object.text.toPlainText(includePlaceholders: false).trim();
        if (isCandidate(text) &&
            !matcher.matches(text) &&
            !_allowlist.any((p) => p.hasMatch(text)) &&
            seen.add(text)) {
          issues.add(HardcodedTextIssue(text: text, locale: locale));
        }
      }
      object.visitChildren(visit);
    }

    root.visitChildren(visit);
    return issues;
  }

  /// Whether [text] is user-facing copy that should come from translations.
  static bool isCandidate(String text) => PseudoLocalizer.shouldTransform(text);

  ArbMessageMatcher _matcherFor(String locale) =>
      _matchers.putIfAbsent(locale, () {
        final chain = {locale, locale.split('_').first, _baseLocale};
        return ArbMessageMatcher.fromMessages([
          for (final l in chain) ...?_messages[l]?.values,
        ]);
      });

  static String _normalize(String locale) => locale.replaceAll('-', '_');

  static List<RegExp> _compile(List<String> patterns) => [
    for (final pattern in patterns) ?_tryCompile(pattern),
  ];

  static RegExp? _tryCompile(String pattern) {
    try {
      return RegExp(pattern, unicode: true);
    } on FormatException catch (e) {
      stderr.writeln(
        'Warning: invalid hardcoded_text_allowlist pattern "$pattern" '
        '($e), skipping it.',
      );
      return null;
    }
  }
}
