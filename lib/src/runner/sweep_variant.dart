import '../config/viewport_preset.dart';

/// Locale code that renders the base locale with pseudo-localized text.
///
/// Add it to `locales` to stress-test layouts with longer, accented strings
/// before real translations exist.
const pseudoLocale = 'pseudo';

/// A single combination of locale, text scale, viewport, and brightness to test.
class SweepVariant {
  /// BCP-47 locale code.
  final String locale;

  /// Text scale factor (1.0 = default, 2.0 = large accessibility).
  final double textScale;

  /// Viewport dimensions.
  final ViewportPreset viewport;

  /// Whether to use dark mode.
  final bool isDark;

  final String? _renderLocale;

  const SweepVariant({
    required this.locale,
    required this.textScale,
    required this.viewport,
    this.isDark = false,
    String? renderLocale,
  }) : _renderLocale = renderLocale;

  /// Whether this variant pseudo-localizes the rendered text.
  bool get isPseudo => locale == pseudoLocale;

  /// The locale the app is rendered in. For [pseudoLocale] variants this is
  /// the base locale; otherwise it equals [locale].
  String get renderLocale => _renderLocale ?? locale;

  static const _rtlLocales = {
    'ar',
    'he',
    'fa',
    'ur',
    'ku',
    'ps',
    'yi',
    'dv',
    'sd',
    'ug',
  };

  /// Whether this locale uses right-to-left text direction.
  bool get isRtl => _rtlLocales.contains(renderLocale.split('_').first);

  String get label {
    final parts = <String>[locale];
    if (isDark) parts.add('dark');
    if (textScale != 1.0) parts.add('${textScale}x');
    parts.add(viewport.name);
    return parts.join('_');
  }

  String get displayLabel {
    final parts = <String>[locale.toUpperCase()];
    if (isRtl) parts.add('RTL');
    if (isDark) parts.add('Dark');
    if (textScale != 1.0) parts.add('${textScale}x scale');
    parts.add(viewport.name);
    return parts.join(' · ');
  }

  /// Returns the golden file path for this variant and flow.
  String screenshotPath(String flowName) =>
      '${flowName}_$label.png'.replaceAll(' ', '_');
}
