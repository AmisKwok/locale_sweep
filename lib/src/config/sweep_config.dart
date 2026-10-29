import 'dart:io';

import 'package:yaml/yaml.dart';

import 'viewport_preset.dart';

/// Configuration for a sweep run, loadable from `locale_sweep.yaml`.
class SweepConfig {
  /// BCP-47 locale codes to test (e.g. `['en', 'de', 'ar']`).
  final List<String> locales;

  /// Text scale factors to test (e.g. `[1.0, 2.0]`).
  final List<double> textScales;

  /// Viewport sizes to render at.
  final List<ViewportPreset> viewports;

  /// Directory for golden screenshots.
  final String screenshotDir;

  /// Directory for generated reports.
  final String reportDir;

  /// Path to ARB files for static translation analysis.
  final String? arbDir;

  /// Whether to test both light and dark mode for each variant.
  final bool darkMode;

  /// Maximum allowed pixel-diff percentage (0.0–100.0) for golden comparisons.
  /// Screenshots within this tolerance pass even when pixels differ.
  final double tolerance;

  /// The base locale for ARB analysis (keys in this locale are the reference).
  /// Defaults to `'en'`.
  final String baseLocale;

  /// ARB keys that are intentionally identical across locales.
  ///
  /// Only the `untranslated` check is exempted; missing keys and placeholder
  /// mismatches for these keys are still reported.
  final List<String> untranslatedAllowlist;

  /// Raw declarative ignore rules parsed from `locale_sweep.yaml`
  /// (`truncation_ignore:`). Each entry is a map with optional keys
  /// `max_lines`, `overflow`, `text_regex` (see [TruncationIgnores.fromConfig]).
  /// Kept as raw maps here so [SweepConfig] stays free of the Flutter widget
  /// dependency; predicates are built lazily by the runner.
  final List<Map<String, dynamic>>? truncationIgnoreRaw;

  /// Whether to report rendered text that matches no ARB message.
  ///
  /// Requires [arbDir].
  final bool hardcodedText;

  /// Regular expressions for rendered text that is intentionally not
  /// translated (brand names, user data). Used when [hardcodedText] is on.
  final List<String> hardcodedTextAllowlist;

  const SweepConfig({
    this.locales = const ['en', 'de', 'ar', 'ja'],
    this.textScales = const [1.0, 2.0],
    this.viewports = const [ViewportPreset.phone],
    this.darkMode = false,
    this.tolerance = 0.0,
    this.screenshotDir = '.locale_sweep/screenshots',
    this.reportDir = '.locale_sweep/reports',
    this.arbDir,
    this.baseLocale = 'en',
    this.untranslatedAllowlist = const [],
    this.truncationIgnoreRaw,
    this.hardcodedText = false,
    this.hardcodedTextAllowlist = const [],
  });

  static const _knownKeys = {
    'locales',
    'text_scales',
    'viewports',
    'dark_mode',
    'tolerance',
    'screenshot_dir',
    'report_dir',
    'arb_dir',
    'base_locale',
    'untranslated_allowlist',
    'hardcoded_text',
    'hardcoded_text_allowlist',
    'truncation_ignore',
  };

  /// Loads configuration from a YAML file, falling back to defaults.
  ///
  /// Warns on stderr about unrecognized keys (likely typos) and type
  /// mismatches so that silent misconfiguration doesn't waste CI runs.
  static SweepConfig load([String? configPath]) {
    final path =
        configPath ??
        Platform.environment['LOCALE_SWEEP_CONFIG'] ??
        'locale_sweep.yaml';
    final file = File(path);
    if (!file.existsSync()) return _applyEnvOverrides(const SweepConfig());

    final content = file.readAsStringSync();
    if (content.trim().isEmpty) return _applyEnvOverrides(const SweepConfig());

    final dynamic parsed;
    try {
      parsed = loadYaml(content);
    } catch (e) {
      stderr.writeln('Warning: Failed to parse $path: $e');
      stderr.writeln('Using default configuration.');
      return _applyEnvOverrides(const SweepConfig());
    }

    if (parsed is! YamlMap) {
      stderr.writeln('Warning: $path is not a YAML map. Using defaults.');
      return _applyEnvOverrides(const SweepConfig());
    }

    final yaml = parsed;

    final unknown = yaml.keys
        .whereType<String>()
        .where((k) => !_knownKeys.contains(k))
        .toList();
    if (unknown.isNotEmpty) {
      stderr.writeln('Warning: Unknown keys in $path: ${unknown.join(', ')}');
      stderr.writeln('Valid keys: ${_knownKeys.join(', ')}');
    }

    _warnIfWrongType(path, yaml, 'locales', 'list');
    _warnIfWrongType(path, yaml, 'text_scales', 'list');
    _warnIfWrongType(path, yaml, 'viewports', 'list');
    _warnIfWrongType(path, yaml, 'dark_mode', 'bool');
    _warnIfWrongType(path, yaml, 'screenshot_dir', 'string');
    _warnIfWrongType(path, yaml, 'report_dir', 'string');
    _warnIfWrongType(path, yaml, 'arb_dir', 'string');
    _warnIfWrongType(path, yaml, 'tolerance', 'num');
    _warnIfWrongType(path, yaml, 'base_locale', 'string');
    _warnIfWrongType(path, yaml, 'untranslated_allowlist', 'list');
    _warnIfWrongType(path, yaml, 'hardcoded_text', 'bool');
    _warnIfWrongType(path, yaml, 'hardcoded_text_allowlist', 'list');
    _warnIfWrongType(path, yaml, 'truncation_ignore', 'list');

    return _applyEnvOverrides(
      SweepConfig(
        // A key whose entries were all dropped would leave an empty matrix,
        // which the runner rejects; fall back to the default instead.
        locales: _orDefault(
          _parseStringList(yaml['locales'], 'locales'),
          const ['en', 'de', 'ar', 'ja'],
        ),
        textScales: _orDefault(
          _parseDoubleList(yaml['text_scales'], 'text_scales'),
          const [1.0, 2.0],
        ),
        viewports: _orDefault(_parseViewports(yaml['viewports']), const [
          ViewportPreset.phone,
        ]),
        darkMode: yaml['dark_mode'] == true,
        tolerance: _parseDouble(yaml['tolerance']) ?? 0.0,
        screenshotDir:
            _parseString(yaml['screenshot_dir']) ?? '.locale_sweep/screenshots',
        reportDir: _parseString(yaml['report_dir']) ?? '.locale_sweep/reports',
        arbDir: _parseString(yaml['arb_dir']),
        baseLocale: _parseString(yaml['base_locale']) ?? 'en',
        untranslatedAllowlist:
            _parseStringList(
              yaml['untranslated_allowlist'],
              'untranslated_allowlist',
            ) ??
            const [],
        truncationIgnoreRaw: _parseIgnoreRules(yaml['truncation_ignore']),
        hardcodedText: yaml['hardcoded_text'] == true,
        hardcodedTextAllowlist:
            _parseStringList(
              yaml['hardcoded_text_allowlist'],
              'hardcoded_text_allowlist',
            ) ??
            const [],
      ),
    );
  }

  /// Parses the `truncation_ignore` YAML list into raw rule maps.
  static List<Map<String, dynamic>>? _parseIgnoreRules(dynamic value) {
    if (value is! YamlList) return null;
    return value
        .whereType<YamlMap>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  static void _warnIfWrongType(
    String path,
    YamlMap yaml,
    String key,
    String expected,
  ) {
    final value = yaml[key];
    if (value == null) return;
    final ok = switch (expected) {
      'list' => value is YamlList,
      'string' => value is String,
      'bool' => value is bool,
      'num' => value is num,
      _ => true,
    };
    if (!ok) {
      stderr.writeln(
        'Warning: "$key" in $path should be a $expected, got ${value.runtimeType}.',
      );
    }
  }

  static SweepConfig _applyEnvOverrides(SweepConfig base) {
    final env = Platform.environment;
    return SweepConfig(
      // An unset CI variable is usually expanded to an empty string, which
      // used to produce an empty (and therefore invalid) sweep matrix.
      locales: _csv(env['LOCALE_SWEEP_LOCALES']) ?? base.locales,
      textScales:
          _csvDoubles(env['LOCALE_SWEEP_TEXT_SCALES']) ?? base.textScales,
      viewports: base.viewports,
      darkMode: _envBool(env, 'LOCALE_SWEEP_DARK_MODE') ?? base.darkMode,
      tolerance: _envDouble(env, 'LOCALE_SWEEP_TOLERANCE') ?? base.tolerance,
      screenshotDir: env['LOCALE_SWEEP_SCREENSHOT_DIR'] ?? base.screenshotDir,
      reportDir: env['LOCALE_SWEEP_REPORT_DIR'] ?? base.reportDir,
      arbDir: env['LOCALE_SWEEP_ARB_DIR'] ?? base.arbDir,
      baseLocale: env['LOCALE_SWEEP_BASE_LOCALE'] ?? base.baseLocale,
      untranslatedAllowlist:
          _csv(env['LOCALE_SWEEP_UNTRANSLATED_ALLOWLIST']) ??
          base.untranslatedAllowlist,
      truncationIgnoreRaw: base.truncationIgnoreRaw,
      hardcodedText:
          _envBool(env, 'LOCALE_SWEEP_HARDCODED_TEXT') ?? base.hardcodedText,
      hardcodedTextAllowlist: base.hardcodedTextAllowlist,
    );
  }

  /// Splits a comma-separated environment value, or `null` when it is unset
  /// or blank (an unset CI variable is usually expanded to an empty string).
  static List<String>? _csv(String? raw) {
    if (raw == null) return null;
    final values = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return values.isEmpty ? null : values;
  }

  static List<double>? _csvDoubles(String? raw) {
    final values = _csv(raw)?.map(double.tryParse).whereType<double>().toList();
    return (values == null || values.isEmpty) ? null : values;
  }

  /// Returns [value] unless it is missing or empty, then [fallback].
  static List<T> _orDefault<T>(List<T>? value, List<T> fallback) =>
      (value == null || value.isEmpty) ? fallback : value;

  /// Reads a boolean environment variable, accepting `true`/`1`/`yes`.
  static bool? _envBool(Map<String, String> env, String name) {
    final raw = env[name];
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim().toLowerCase();
    if (const {'true', '1', 'yes'}.contains(value)) return true;
    if (const {'false', '0', 'no'}.contains(value)) return false;
    stderr.writeln(
      'Warning: $name="$raw" is not a boolean; falling back to the '
      'configured value.',
    );
    return null;
  }

  static double? _envDouble(Map<String, String> env, String name) {
    final raw = env[name];
    if (raw == null || raw.trim().isEmpty) return null;
    final value = double.tryParse(raw.trim());
    if (value == null) {
      stderr.writeln(
        'Warning: $name="$raw" is not a number; falling back to the '
        'configured value.',
      );
    }
    return value;
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }

  static String? _parseString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  /// Parses a list of strings, dropping (and reporting) non-string entries.
  ///
  /// A single wrong-typed entry used to throw a `TypeError` out of [load],
  /// which aborted the CLI before any report was written.
  static List<String>? _parseStringList(dynamic value, String key) {
    if (value is! YamlList) return null;
    final parsed = <String>[];
    for (final entry in value) {
      if (entry is! String) {
        stderr.writeln(
          'Warning: dropping non-string entry "$entry" from "$key".',
        );
        continue;
      }
      parsed.add(entry);
    }
    return parsed;
  }

  static List<double>? _parseDoubleList(dynamic value, String key) {
    if (value is! YamlList) return null;
    final parsed = <double>[];
    for (final entry in value) {
      if (entry is! num) {
        stderr.writeln(
          'Warning: dropping non-numeric entry "$entry" from "$key".',
        );
        continue;
      }
      parsed.add(entry.toDouble());
    }
    return parsed;
  }

  static List<ViewportPreset>? _parseViewports(dynamic value) {
    if (value is! YamlList) return null;
    final parsed = <ViewportPreset>[];
    for (final entry in value) {
      if (entry is! YamlMap) {
        stderr.writeln(
          'Warning: dropping viewport "$entry" — every viewport needs '
          'name, width and height.',
        );
        continue;
      }
      final name = entry['name'];
      final width = entry['width'];
      final height = entry['height'];
      if (name is! String || width is! num || height is! num) {
        stderr.writeln(
          'Warning: dropping viewport "$entry" — name must be a string and '
          'width/height must be numbers.',
        );
        continue;
      }
      parsed.add(
        ViewportPreset(
          name: name,
          width: width.toDouble(),
          height: height.toDouble(),
        ),
      );
    }
    return parsed;
  }
}
