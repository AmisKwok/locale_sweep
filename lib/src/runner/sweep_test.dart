import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../config/sweep_config.dart';
import '../config/viewport_preset.dart';
import '../detection/arb_analyzer.dart';
import '../detection/golden_diff.dart';
import '../detection/hardcoded_text_detector.dart';
import '../detection/overflow_detector.dart';
import '../detection/pseudo_localizer.dart';
import '../detection/truncation_detector.dart';
import '../report/sweep_result.dart';
import 'sweep_variant.dart';

/// Default directory where sweep results are written for CLI consumption.
const sweepResultsDir = '.locale_sweep/results';

final _allResults = <SweepResult>[];

/// Returns all results recorded by [sweepTest] in this test isolate.
///
/// **Note:** Each test file runs in its own isolate, so this list only
/// contains results from the current file. For cross-file aggregation,
/// use the JSON files written to [sweepResultsDir] instead.
List<SweepResult> get sweepResults => List.unmodifiable(_allResults);

/// Clears all recorded sweep results.
void clearSweepResults() => _allResults.clear();

/// Callback for interactions to run after the widget is pumped.
typedef SweepBody = Future<void> Function(WidgetTester tester);

/// Callback that also receives the current [SweepVariant] for locale-aware interactions.
typedef SweepVariantBody =
    Future<void> Function(WidgetTester tester, SweepVariant variant);

/// Generates `locales × textScales × viewports (× brightness)` test cases for [flowName].
///
/// Each combination is run as a separate `testWidgets`, wrapped in
/// [Directionality] and [MediaQuery] to simulate the target environment.
///
/// Set [darkMode] to `true` to test both light and dark for every variant.
/// Pass [lightTheme] / [darkTheme] to wrap the widget in a [Theme] so
/// `Theme.of(context)` works inside the builder — if omitted, default
/// Material themes are used when [darkMode] is enabled.
///
/// Pass [localizationsDelegates] to wrap the widget in a [Localizations]
/// ancestor so `AppLocalizations.of(context)` works for individual screen
/// tests. When provided, the variant's locale is set on the [Localizations]
/// widget and default Material/Widgets/Cupertino delegates are included
/// automatically.
///
/// Overflow errors are captured and fail the variant after the result
/// is recorded (so screenshots exist before failure).
///
/// Pass exactly one of [builder] or [builderWithVariant]. The latter receives
/// the current [SweepVariant], so the builder can hand the variant's
/// [SweepVariant.renderLocale] (or text scale, or viewport) directly to the
/// widget under test instead of relying on platform locale resolution.
///
/// When [captureScreenshots] is true, set [compareScreenshots] to false to
/// write PNGs for reports without asserting against golden baselines. This is
/// useful when screenshots are for diagnosis only and pixel diffs would be
/// noisy (for example, under Flutter's Ahem test font).
///
/// Include [pseudoLocale] in [locales] to render the base locale with
/// expanded, accented text, so layouts can be checked before translations
/// exist.
///
/// Set [detectHardcodedText] (or `hardcoded_text: true`) to report rendered
/// text that matches no ARB message in [arbDir]. Strings matching a pattern in
/// [hardcodedTextAllowlist] are ignored.
void sweepTest(
  String flowName, {
  Widget Function()? builder,
  Widget Function(SweepVariant variant)? builderWithVariant,
  SweepBody? body,
  SweepVariantBody? variantBody,
  SweepConfig? config,
  List<String>? locales,
  List<double>? textScales,
  List<ViewportPreset>? viewports,
  bool? darkMode,
  ThemeData? lightTheme,
  ThemeData? darkTheme,
  String? arbDir,
  String? baseLocale,
  List<String>? untranslatedAllowlist,
  bool captureScreenshots = true,
  bool compareScreenshots = true,
  String? screenshotDir,
  bool Function(SweepVariant variant)? skip,
  double? tolerance,
  String diffOutputDir = '.locale_sweep/diffs',
  Future<void> Function()? setUp,
  List<LocalizationsDelegate<dynamic>>? localizationsDelegates,
  List<TruncationIgnore>? ignoreTruncation,
  bool? detectHardcodedText,
  List<String>? hardcodedTextAllowlist,
}) {
  if ((builder == null) == (builderWithVariant == null)) {
    throw ArgumentError(
      'sweepTest("$flowName") requires exactly one of '
      'builder or builderWithVariant.',
    );
  }

  final cfg = config ?? SweepConfig.load();
  final effectiveLocales = locales ?? cfg.locales;
  final effectiveScales = textScales ?? cfg.textScales;
  final effectiveViewports = viewports ?? cfg.viewports;
  final effectiveDarkMode = darkMode ?? cfg.darkMode;
  final effectiveArbDir = arbDir ?? cfg.arbDir;
  final effectiveTolerance = tolerance ?? cfg.tolerance;
  final effectiveBaseLocale = baseLocale ?? cfg.baseLocale;
  final effectiveUntranslatedAllowlist =
      untranslatedAllowlist ?? cfg.untranslatedAllowlist;
  final effectiveScreenshotDir = screenshotDir ?? cfg.screenshotDir;
  final managedRun = Platform.environment['LOCALE_SWEEP_MANAGED_RUN'] == 'true';
  final resultsPath =
      Platform.environment['LOCALE_SWEEP_RESULTS_DIR'] ?? sweepResultsDir;
  if (effectiveLocales.isEmpty ||
      effectiveLocales.any((l) => l.trim().isEmpty) ||
      effectiveScales.isEmpty ||
      effectiveScales.any((s) => !s.isFinite || s <= 0) ||
      effectiveViewports.isEmpty ||
      effectiveViewports.any(
        (v) =>
            !v.width.isFinite ||
            !v.height.isFinite ||
            v.width <= 0 ||
            v.height <= 0,
      ) ||
      !effectiveTolerance.isFinite ||
      effectiveTolerance < 0 ||
      effectiveTolerance > 100) {
    throw ArgumentError(
      'Invalid sweep matrix or tolerance for "$flowName". '
      'Use nonempty locales, positive scales and viewports, and tolerance 0–100.',
    );
  }

  final darkModes = [false, if (effectiveDarkMode) true];

  final resolvedLightTheme = effectiveDarkMode
      ? (lightTheme ?? ThemeData.light())
      : lightTheme;
  final resolvedDarkTheme = effectiveDarkMode
      ? (darkTheme ?? ThemeData.dark())
      : darkTheme;

  final variants = <SweepVariant>[];
  for (final locale in effectiveLocales) {
    for (final scale in effectiveScales) {
      for (final vp in effectiveViewports) {
        for (final isDark in darkModes) {
          variants.add(
            SweepVariant(
              locale: locale,
              textScale: scale,
              viewport: vp,
              isDark: isDark,
              renderLocale: locale == pseudoLocale ? effectiveBaseLocale : null,
            ),
          );
        }
      }
    }
  }

  final effectiveDetectHardcoded = detectHardcodedText ?? cfg.hardcodedText;
  if (effectiveDetectHardcoded && effectiveArbDir == null) {
    throw ArgumentError(
      'Hardcoded text detection for "$flowName" needs arbDir (or arb_dir in '
      'locale_sweep.yaml) to know which strings are translated.',
    );
  }
  final hardcodedDetector = effectiveDetectHardcoded
      ? HardcodedTextDetector(
          messages: ArbAnalyzer.loadMessages(effectiveArbDir!),
          baseLocale: effectiveBaseLocale,
          allowlist: hardcodedTextAllowlist ?? cfg.hardcodedTextAllowlist,
        )
      : null;

  ArbReport? arbReport;
  if (effectiveArbDir != null) {
    arbReport = ArbAnalyzer.analyze(
      arbDir: effectiveArbDir,
      locales: effectiveLocales.where((l) => l != pseudoLocale).toList(),
      baseLocale: effectiveBaseLocale,
      untranslatedAllowlist: effectiveUntranslatedAllowlist,
    );
  }

  final flowResults = <SweepResult>[];
  File? resultFile;

  void writeResults() {
    final dir = Directory(resultsPath)..createSync(recursive: true);
    // Each flow registration gets its own file during managed runs, including
    // identical flow names in different test isolates.
    resultFile ??= managedRun
        ? File('${dir.createTempSync('flow_').path}/results.json')
        : File('${dir.path}/${Uri.encodeComponent(flowName)}.json');
    resultFile!.writeAsStringSync(
      jsonEncode(flowResults.map((r) => r.toJson()).toList()),
    );
  }

  group('sweep: $flowName', () {
    if (setUp != null) {
      setUpAll(setUp);
    }

    tearDownAll(writeResults);

    // Build the ignore predicates once so that invalid-rule warnings are
    // printed a single time instead of once per variant.
    final effectiveIgnores = <TruncationIgnore>[
      ...?cfg.truncationIgnoreRaw?.map(TruncationIgnores.fromConfig),
      ...?ignoreTruncation,
    ];

    for (final variant in variants) {
      final shouldSkip = skip != null && skip(variant);
      testWidgets('$flowName [${variant.displayLabel}]', skip: shouldSkip, (
        tester,
      ) async {
        final stopwatch = Stopwatch()..start();
        final overflowDetector = OverflowDetector();
        String? screenshotPath;
        String? errorMessage;
        SweepFailureKind? failureKind;
        Object? caughtError;
        StackTrace? caughtStack;
        var passed = true;
        final arbIssues = <ArbIssue>[];
        var truncations = <TruncationIssue>[];
        var hardcodedTexts = <HardcodedTextIssue>[];
        DiffResult? diffResult;

        if (arbReport != null) {
          arbIssues.addAll(
            arbReport.issues.where(
              (i) =>
                  i.locale == variant.locale || i.locale == effectiveBaseLocale,
            ),
          );
        }

        overflowDetector.install();

        try {
          _configureTestEnvironment(tester, variant);

          final themeData = variant.isDark
              ? resolvedDarkTheme
              : resolvedLightTheme;

          Widget child = builderWithVariant != null
              ? builderWithVariant(variant)
              : builder!();
          if (themeData != null) {
            child = Theme(data: themeData, child: child);
          }

          if (localizationsDelegates != null) {
            final allDelegates = <LocalizationsDelegate<dynamic>>[
              ...localizationsDelegates,
              _FallbackMaterialLocalizationsDelegate(),
              _FallbackWidgetsLocalizationsDelegate(),
            ];
            child = Localizations(
              locale: parseLocale(variant.renderLocale),
              delegates: allDelegates,
              child: child,
            );
          }

          final widget = Directionality(
            textDirection: variant.isRtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(variant.viewport.width, variant.viewport.height),
                textScaler: TextScaler.linear(variant.textScale),
                platformBrightness: variant.isDark
                    ? Brightness.dark
                    : Brightness.light,
              ),
              child: child,
            ),
          );

          await tester.pumpWidget(widget);
          await tester.pumpAndSettle();

          if (variantBody != null) {
            await variantBody(tester, variant);
            await tester.pumpAndSettle();
          } else if (body != null) {
            await body(tester);
            await tester.pumpAndSettle();
          }

          if (hardcodedDetector != null) {
            hardcodedTexts = hardcodedDetector.detect(
              tester,
              locale: variant.locale,
              renderLocale: variant.renderLocale,
            );
          }

          if (variant.isPseudo) await PseudoLocalizer.apply(tester);

          truncations = TruncationDetector.detect(
            tester,
            variant.locale,
            effectiveIgnores,
          );

          final frameworkError = tester.takeException();
          if (frameworkError != null) throw frameworkError;

          if (captureScreenshots) {
            final goldenKey =
                '$effectiveScreenshotDir/${variant.screenshotPath(flowName)}';
            // Golden keys resolve relative to the test file's directory.
            // Store the package-relative location so reports can link to the
            // file that was actually written.
            screenshotPath = _resolveScreenshotPath(goldenKey);

            if (!compareScreenshots) {
              await _writeScreenshot(tester, screenshotPath);
            } else {
              SweepGoldenComparator? sweepComparator;
              final originalComparator = goldenFileComparator;
              if (effectiveTolerance > 0) {
                sweepComparator = SweepGoldenComparator(
                  delegate: originalComparator,
                  tolerance: effectiveTolerance,
                  diffOutputDir: diffOutputDir,
                );
                goldenFileComparator = sweepComparator;
              }

              try {
                await expectLater(
                  find.byType(Directionality).first,
                  matchesGoldenFile(goldenKey),
                );
              } on TestFailure {
                failureKind = SweepFailureKind.golden;
                rethrow;
              } finally {
                if (sweepComparator != null) {
                  goldenFileComparator = originalComparator;
                  diffResult = sweepComparator.lastDiffResult;
                }
              }
            }
          }
        } catch (e, stack) {
          passed = false;
          errorMessage = e.toString();
          failureKind ??= SweepFailureKind.test;
          caughtError = e;
          caughtStack = stack;
        } finally {
          overflowDetector.uninstall();
          stopwatch.stop();
        }

        if (overflowDetector.errors.isNotEmpty || arbIssues.isNotEmpty) {
          passed = false;
        }

        final result = SweepResult(
          flowName: flowName,
          variant: variant,
          passed: passed,
          overflows: List.of(overflowDetector.errors),
          arbIssues: arbIssues,
          truncations: truncations,
          hardcodedTexts: hardcodedTexts,
          screenshotPath: screenshotPath,
          errorMessage: errorMessage,
          failureKind: failureKind,
          duration: stopwatch.elapsed,
          diff: diffResult,
        );

        _allResults.add(result);
        flowResults.add(result);
        writeResults();

        if (caughtError != null &&
            (failureKind == SweepFailureKind.test || !managedRun)) {
          Error.throwWithStackTrace(caughtError, caughtStack!);
        }
        // The CLI applies --fail-on to recorded QA findings. Flutter's own
        // exit code remains reserved for execution failures in managed runs.
        if (!passed && !managedRun) {
          fail(
            'Sweep failed in $flowName [${variant.displayLabel}]:\n'
            '${[...overflowDetector.errors, ...arbIssues].join('\n')}',
          );
        }
      });
    }
  });
}

/// Writes the rendered widget tree to [path] without comparing it to a
/// golden baseline.
Future<void> _writeScreenshot(WidgetTester tester, String path) async {
  final element = tester.element(find.byType(Directionality).first);
  final bytes = await tester.runAsync(() async {
    final image = await _captureImage(element);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  if (bytes == null) {
    throw StateError('Failed to capture screenshot for "$path".');
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes.buffer.asUint8List());
}

/// Captures the nearest repaint boundary above [element].
Future<ui.Image> _captureImage(Element element) {
  var renderObject = element.renderObject!;
  while (!renderObject.isRepaintBoundary) {
    renderObject = renderObject.parent!;
  }
  final layer = renderObject.debugLayer! as OffsetLayer;
  return layer.toImage(renderObject.paintBounds);
}

/// Resolves a golden key to a package-relative path.
///
/// [LocalFileComparator] resolves golden keys relative to the test file's
/// directory, which is not the package root when tests live in a subdirectory
/// (e.g. `test/sweep/`). Reports are written relative to the package root, so
/// record the resolved location instead of the raw golden key.
String _resolveScreenshotPath(String path) {
  if (p.isAbsolute(path)) return path;
  final comparator = goldenFileComparator;
  if (comparator is! LocalFileComparator) return path;
  final resolved = comparator.basedir.resolve(path).toFilePath();
  final relative = p.relative(resolved, from: Directory.current.path);
  return p.posix.joinAll(p.split(relative));
}

/// Parses a BCP-47 locale string into a [Locale].
///
/// Handles: `en`, `en_US`, `zh_Hans`, `zh_Hans_CN`, and hyphenated
/// variants like `pt-BR`.
Locale parseLocale(String code) {
  final parts = code.replaceAll('-', '_').split('_');
  if (parts.length == 1) return Locale(parts[0]);
  if (parts.length == 2) {
    // Could be language_country (en_US) or language_script (zh_Hans)
    if (parts[1].length == 4) {
      // Script code is 4 chars (Hans, Latn, etc.)
      return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
    }
    return Locale(parts[0], parts[1]);
  }
  // language_script_country (zh_Hans_CN)
  return Locale.fromSubtags(
    languageCode: parts[0],
    scriptCode: parts[1],
    countryCode: parts[2],
  );
}

class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<MaterialLocalizations> old,
  ) => false;
}

class _FallbackWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      DefaultWidgetsLocalizations.load(locale);

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<WidgetsLocalizations> old,
  ) => false;
}

void _configureTestEnvironment(WidgetTester tester, SweepVariant variant) {
  final view = tester.view;
  view.physicalSize = Size(variant.viewport.width, variant.viewport.height);
  view.devicePixelRatio = 1.0;

  tester.platformDispatcher.localeTestValue = parseLocale(variant.renderLocale);
  tester.platformDispatcher.textScaleFactorTestValue = variant.textScale;
  tester.platformDispatcher.platformBrightnessTestValue = variant.isDark
      ? ui.Brightness.dark
      : ui.Brightness.light;

  addTearDown(() {
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    tester.platformDispatcher.clearLocaleTestValue();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}
