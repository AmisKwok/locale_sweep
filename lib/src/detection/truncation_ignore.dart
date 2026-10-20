import 'dart:io';

import 'package:flutter/widgets.dart';

import 'truncation_issue.dart';

/// Predicate used to exclude a detected [TruncationIssue] from the report.
///
/// Return `true` to drop the issue (it is treated as an intentional
/// truncation). The [Element] is the widget that created the underlying
/// [RenderParagraph], resolved from `RenderParagraph.debugCreator` (a
/// [DebugCreator]) and only populated in debug/asserts builds (i.e.
/// `flutter test`). Predicates that rely on it
/// (e.g. [TruncationIgnores.byWidgetType] / [TruncationIgnores.byKey]) walk up
/// the ancestor chain, and simply won't match when it is `null`.
typedef TruncationIgnore =
    bool Function(TruncationIssue issue, Element? element);

/// Convenience builders for the most common ignore rules, so users don't have
/// to hand-roll [TruncationIgnore] predicates.
class TruncationIgnores {
  /// Walks up from the paragraph's creating element to find any [Element]
  /// whose widget has the exact [type]. This matches the user's own wrapping
  /// widget (e.g. a `ListCell`), not just the framework `RichText` that
  /// directly owns the [RenderParagraph].
  ///
  /// Note: Flutter forbids `dart:mirrors`, so subtype matching against a
  /// [Type] variable isn't available — match on the exact runtime type.
  static TruncationIgnore byWidgetType(Type type) => (_, Element? el) {
    if (el == null) return false;
    if (el.widget.runtimeType == type) return true;
    var found = false;
    el.visitAncestorElements((a) {
      if (a.widget.runtimeType == type) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  };

  /// Walks up from the paragraph's creating element to find any [Element]
  /// whose widget has [key]. Matches a wrapping widget even though the
  /// [RenderParagraph] itself is owned by a framework `RichText`.
  static TruncationIgnore byKey(Key key) => (_, Element? el) {
    if (el == null) return false;
    if (el.widget.key == key) return true;
    var found = false;
    el.visitAncestorElements((a) {
      if (a.widget.key == key) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  };

  /// Ignore only when `maxLines` is set and `<= [maxLines]`.
  static TruncationIgnore byMaxLines(int maxLines) =>
      (issue, _) => issue.maxLines != null && issue.maxLines! <= maxLines;

  /// Ignore when the truncated [issue.text] matches [pattern].
  static TruncationIgnore byText(Pattern pattern) =>
      (issue, _) => pattern.allMatches(issue.text).isNotEmpty;

  /// Combine multiple rules: ignore when ANY matches.
  static TruncationIgnore any(List<TruncationIgnore> rules) =>
      (issue, el) => rules.any((r) => r(issue, el));

  /// Build a matcher from a parsed declarative YAML rule map (see the
  /// `truncation_ignore` schema in `locale_sweep.yaml`).
  ///
  /// A rule matches an issue only when **all** of its specified fields match
  /// (so a rule with both `max_lines` and `text_regex` is an AND). Supported
  /// keys:
  ///   * `max_lines` (int): `issue.maxLines != null && issue.maxLines! <= n`
  ///   * `overflow` (String): equals `issue.overflowMode`
  ///     (one of `ellipsis`/`clip`/`fade`/`visible`)
  ///   * `text_regex` (String): matches `issue.text`
  ///
  /// Invalid rules never silently ignore everything: an unknown key, a rule
  /// with no recognized keys, a wrong-typed value, or an uncompilable
  /// `text_regex` produces a warning on stderr and the rule is skipped (it
  /// matches nothing), so a typo cannot hide every truncation.
  static TruncationIgnore fromConfig(Map<String, dynamic> rule) {
    const knownKeys = {'max_lines', 'overflow', 'text_regex'};

    for (final key in rule.keys) {
      if (!knownKeys.contains(key)) {
        stderr.writeln(
          'Warning: unknown key "$key" in truncation_ignore rule; '
          'valid keys are ${knownKeys.join(', ')}. Rule: $rule',
        );
      }
    }

    if (rule.keys.every((k) => !knownKeys.contains(k))) {
      stderr.writeln(
        'Warning: truncation_ignore rule has no recognized keys and was '
        'skipped (such a rule would otherwise ignore every truncation). '
        'Rule: $rule',
      );
      return (_, _) => false;
    }

    int? maxLines;
    if (rule.containsKey('max_lines')) {
      final value = rule['max_lines'];
      if (value is! int) {
        stderr.writeln(
          'Warning: "max_lines" in truncation_ignore must be an int, '
          'skipping rule. Rule: $rule',
        );
        return (_, _) => false;
      }
      maxLines = value;
    }

    String? overflow;
    if (rule.containsKey('overflow')) {
      final value = rule['overflow'];
      if (value is! String) {
        stderr.writeln(
          'Warning: "overflow" in truncation_ignore must be a string, '
          'skipping rule. Rule: $rule',
        );
        return (_, _) => false;
      }
      overflow = value;
    }

    RegExp? textRegex;
    if (rule.containsKey('text_regex')) {
      final value = rule['text_regex'];
      if (value is! String) {
        stderr.writeln(
          'Warning: "text_regex" in truncation_ignore must be a string, '
          'skipping rule. Rule: $rule',
        );
        return (_, _) => false;
      }
      try {
        textRegex = RegExp(value);
      } on FormatException catch (e) {
        stderr.writeln(
          'Warning: invalid "text_regex" "$value" in truncation_ignore ($e), '
          'skipping rule. Rule: $rule',
        );
        return (_, _) => false;
      }
    }

    return (TruncationIssue issue, _) {
      if (maxLines != null &&
          (issue.maxLines == null || issue.maxLines! > maxLines)) {
        return false;
      }
      if (overflow != null && issue.overflowMode != overflow) return false;
      if (textRegex != null && !textRegex.hasMatch(issue.text)) return false;
      return true; // all specified fields matched
    };
  }
}
