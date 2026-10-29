import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Static analyzer for ARB (Application Resource Bundle) translation files.
///
/// Detects missing keys and placeholder mismatches by comparing target locale
/// ARB files against the base locale.
class ArbAnalyzer {
  /// Analyzes ARB files in [arbDir] for missing keys and placeholder issues.
  ///
  /// Keys listed in [untranslatedAllowlist] are exempt from the
  /// `untranslated` check (for values that are intentionally identical across
  /// locales, such as app names or language self-names). Missing keys and
  /// placeholder mismatches are still reported for those keys.
  /// Message values keyed by locale, then ARB key. Metadata is skipped.
  static Map<String, Map<String, String>> loadMessages(String arbDir) {
    final dir = Directory(arbDir);
    if (!dir.existsSync()) return {};
    return {
      for (final MapEntry(key: locale, value: arb) in _loadArbFiles(
        dir,
      ).files.entries)
        locale: {
          for (final MapEntry(:key, :value) in arb.entries)
            if (!key.startsWith('@') && value is String) key: value,
        },
    };
  }

  /// Reads every `*.arb` file in [dir], keyed by the locale in its file name.
  ///
  /// Files that cannot be read are reported through [ArbFileLoading.errors]
  /// instead of being replaced with an empty map: an unreadable base ARB used
  /// to yield an empty key set, which silently passed every other check.
  static ArbFileLoading _loadArbFiles(Directory dir) {
    final arbFiles = <String, Map<String, dynamic>>{};
    final errors = <String, String>{};
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.arb')) continue;
      final name = p.basenameWithoutExtension(file.path);
      final locale = _extractLocale(name);
      if (locale == null) {
        stderr.writeln(
          'Warning: skipped ARB file "${p.basename(file.path)}" — the file '
          'name carries no locale tag (expected e.g. app_en.arb, '
          'app_zh_Hans.arb or app_es_419.arb).',
        );
        continue;
      }
      try {
        arbFiles[locale] =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (e) {
        errors[locale] = e.toString();
        stderr.writeln(
          'Warning: failed to parse ARB file "${p.basename(file.path)}": $e',
        );
      }
    }
    return ArbFileLoading(files: arbFiles, errors: errors);
  }

  static ArbReport analyze({
    required String arbDir,
    List<String> locales = const ['en', 'de', 'ar', 'ja'],
    String baseLocale = 'en',
    List<String> untranslatedAllowlist = const [],
  }) {
    final dir = Directory(arbDir);
    if (!dir.existsSync()) {
      return ArbReport(
        issues: [
          ArbIssue(
            type: ArbIssueType.missingFile,
            locale: baseLocale,
            detail: 'ARB directory not found: $arbDir',
          ),
        ],
      );
    }

    final loading = _loadArbFiles(dir);
    final arbFiles = loading.files;
    final issues = <ArbIssue>[];

    // Report unreadable files up front: analyzing an empty key set would
    // report "everything is fine" for a locale whose JSON is broken.
    for (final MapEntry(key: locale, value: error) in loading.errors.entries) {
      issues.add(
        ArbIssue(
          type: ArbIssueType.parseError,
          locale: locale,
          detail: 'Failed to parse ARB file for "$locale": $error',
        ),
      );
    }

    final baseArb = arbFiles[baseLocale];
    if (baseArb == null) {
      // An unparseable base file is already reported as a parseError above;
      // calling it "missing" would send users looking for the wrong problem.
      if (loading.errors.containsKey(baseLocale)) {
        return ArbReport(issues: issues);
      }
      return ArbReport(
        issues: [
          ...issues,
          ArbIssue(
            type: ArbIssueType.missingFile,
            locale: baseLocale,
            detail: 'Base ARB file for "$baseLocale" not found in $arbDir',
          ),
        ],
      );
    }

    final baseKeys = baseArb.keys
        .where((k) => !k.startsWith('@') && !k.startsWith('@@'))
        .toSet();
    final basePlaceholders = <String, Set<String>>{};
    for (final key in baseKeys) {
      final meta = baseArb['@$key'];
      final declared = meta is Map && meta['placeholders'] is Map
          ? (meta['placeholders'] as Map).keys.cast<String>().toSet()
          : <String>{};
      final value = baseArb[key];
      // `@key.placeholders` metadata is optional. Without it, fall back to the
      // placeholders that actually appear in the base message so hand-written
      // ARB files are still checked instead of being skipped entirely.
      basePlaceholders[key] = {
        ...declared,
        if (value is String) ...placeholdersIn(value),
      };
    }

    for (final locale in locales) {
      if (locale == baseLocale) continue;

      final arb = arbFiles[locale];
      if (arb == null) {
        // An unparseable file is reported as a parseError; reporting every
        // base key as "missing" on top of it would only add false positives.
        if (loading.errors.containsKey(locale)) continue;
        issues.add(
          ArbIssue(
            type: ArbIssueType.missingFile,
            locale: locale,
            detail: 'No ARB file for locale "$locale"',
          ),
        );
        continue;
      }

      final targetKeys = arb.keys
          .where((k) => !k.startsWith('@') && !k.startsWith('@@'))
          .toSet();

      for (final key in baseKeys) {
        if (!targetKeys.contains(key)) {
          issues.add(
            ArbIssue(
              type: ArbIssueType.missingKey,
              locale: locale,
              key: key,
              detail: 'Key "$key" missing in $locale (present in $baseLocale)',
            ),
          );
          continue;
        }

        final value = arb[key];
        final baseValue = baseArb[key];

        if (value is String &&
            baseValue is String &&
            value == baseValue &&
            !untranslatedAllowlist.contains(key)) {
          issues.add(
            ArbIssue(
              type: ArbIssueType.untranslated,
              locale: locale,
              key: key,
              detail:
                  'Key "$key" in $locale is identical to $baseLocale (possibly untranslated)',
            ),
          );
        }

        final expectedPlaceholders = basePlaceholders[key];
        if (expectedPlaceholders != null && expectedPlaceholders.isNotEmpty) {
          if (value is String) {
            final actual = placeholdersIn(value);
            for (final ph in _sorted(expectedPlaceholders.difference(actual))) {
              issues.add(
                ArbIssue(
                  type: ArbIssueType.placeholderMismatch,
                  locale: locale,
                  key: key,
                  detail:
                      'Placeholder {$ph} missing in $locale value for "$key"',
                ),
              );
            }
            // A placeholder that only exists in the target is either a typo
            // or an argument the base locale does not pass — it renders as a
            // literal `{nmae}` instead of a value.
            for (final ph in _sorted(actual.difference(expectedPlaceholders))) {
              issues.add(
                ArbIssue(
                  type: ArbIssueType.placeholderMismatch,
                  locale: locale,
                  key: key,
                  detail:
                      'Placeholder {$ph} in $locale value for "$key" is not '
                      'declared in $baseLocale',
                ),
              );
            }
          }
        }
      }
    }

    return ArbReport(issues: issues);
  }

  /// Matches a placeholder opening in any valid ICU form: `{name}`,
  /// `{name, plural, ...}`, `{name, select, ...}`, etc.
  static final RegExp _placeholderPattern = RegExp(
    r'\{([A-Za-z_][A-Za-z0-9_.-]*)[,}]',
  );

  /// The placeholder names referenced by [value].
  ///
  /// Extracting the names (instead of interpolating them into a [RegExp])
  /// keeps placeholders that contain regex metacharacters — `{user.name}`,
  /// `{a+b}` — from being misread as patterns.
  ///
  /// A brace that directly follows a word character opens an ICU branch
  /// (`good{Super}`), so it is not a placeholder.
  static Set<String> placeholdersIn(String value) {
    final found = <String>{};
    for (final match in _placeholderPattern.allMatches(value)) {
      if (match.start > 0 && _isWordChar(value.codeUnitAt(match.start - 1))) {
        continue;
      }
      found.add(match.group(1)!);
    }
    return found;
  }

  static bool _isWordChar(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || // A-Z
      (unit >= 0x61 && unit <= 0x7A) || // a-z
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      unit == 0x5F; // _

  static List<String> _sorted(Iterable<String> values) =>
      values.toList()..sort();

  /// Extracts the locale tag from an ARB file name.
  ///
  /// Accepts the shapes `flutter gen-l10n` produces: `app_en`, `app_en_US`,
  /// `app_zh_Hans`, `app_zh_Hans_CN`, `app_es_419`, plus hyphenated
  /// (`app_en-US`) and unprefixed (`en`) names. Returns `null` when the name
  /// has no locale tag.
  static String? _extractLocale(String filename) {
    final parts = filename.split(RegExp(r'[-_]'));
    for (var i = 0; i < parts.length; i++) {
      final candidate = parts.sublist(i).join('_');
      if (_isLocaleTag(candidate)) return candidate;
    }
    return null;
  }

  /// Whether [tag] is a language(+script/region) tag such as `en`, `zh_Hans`,
  /// `zh_Hans_CN`, `es_419` or `fil`.
  static bool _isLocaleTag(String tag) {
    final parts = tag.split('_');
    if (parts.isEmpty || parts.length > 3) return false;
    if (!RegExp(r'^[a-z]{2,3}$').hasMatch(parts.first)) return false;
    for (final part in parts.skip(1)) {
      // Script (`Hans`), region (`US`, `419` for UN M.49) — see BCP-47.
      if (RegExp(r'^[A-Z][a-z]{3}$').hasMatch(part)) continue;
      if (RegExp(r'^[A-Z]{2}$').hasMatch(part)) continue;
      if (RegExp(r'^[0-9]{3}$').hasMatch(part)) continue;
      return false;
    }
    return true;
  }
}

/// The ARB files found in a directory, plus the ones that failed to parse.
class ArbFileLoading {
  /// Parsed ARB files keyed by locale.
  final Map<String, Map<String, dynamic>> files;

  /// Parse errors keyed by locale, for files that could not be read.
  final Map<String, String> errors;

  const ArbFileLoading({required this.files, this.errors = const {}});
}

/// Result of an ARB analysis containing all detected issues.
class ArbReport {
  /// All issues found across all analyzed locales.
  final List<ArbIssue> issues;

  /// Creates an ARB report.
  const ArbReport({this.issues = const []});

  /// Whether any issues were detected.
  bool get hasIssues => issues.isNotEmpty;

  /// Returns issues for a specific [locale].
  List<ArbIssue> issuesForLocale(String locale) =>
      issues.where((i) => i.locale == locale).toList();

  /// Groups issues by locale.
  Map<String, List<ArbIssue>> get byLocale {
    final map = <String, List<ArbIssue>>{};
    for (final issue in issues) {
      map.putIfAbsent(issue.locale, () => []).add(issue);
    }
    return map;
  }
}

/// The type of issue found during ARB analysis.
enum ArbIssueType {
  /// An expected ARB file was not found.
  missingFile,

  /// An ARB file exists but could not be read (invalid JSON).
  parseError,

  /// A key present in the base locale is missing in the target locale.
  missingKey,

  /// A placeholder (e.g. `{count}`) is in the base but missing in the target.
  placeholderMismatch,

  /// A key's value is identical to the base locale (possibly untranslated).
  untranslated,
}

/// A single issue found during ARB analysis.
class ArbIssue {
  /// The category of this issue.
  final ArbIssueType type;

  /// The locale where this issue was found.
  final String locale;

  /// The ARB key involved, if applicable.
  final String? key;

  /// Human-readable description of the issue.
  final String detail;

  const ArbIssue({
    required this.type,
    required this.locale,
    this.key,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'locale': locale,
    'key': key,
    'detail': detail,
  };

  factory ArbIssue.fromJson(Map<String, dynamic> json) => ArbIssue(
    type: ArbIssueType.values.byName(json['type'] as String),
    locale: json['locale'] as String,
    key: json['key'] as String?,
    detail: json['detail'] as String,
  );

  @override
  String toString() => detail;
}
