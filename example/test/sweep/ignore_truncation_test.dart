import 'package:flutter/material.dart';
import 'package:locale_sweep/locale_sweep.dart';

/// Demonstrates excluding *intentional* truncations from the report.
///
/// The list-row cells below deliberately clamp long text with
/// `maxLines: 1` + `ellipsis` — this is by design, not a localization bug,
/// so we don't want it flagged by `--fail-on truncation`.
///
/// The rules are passed inline so they apply to this flow only. The
/// equivalent global YAML form is shown (commented out) under
/// `truncation_ignore:` in `example/locale_sweep.yaml`; enabling it there
/// would also hide truncations in the other example flows.
void main() {
  sweepTest(
    'ignore_intentional_truncation',
    // No golden screenshots for this demo — we only assert truncation behavior.
    captureScreenshots: false,
    // en is the fully-translated base locale, so ARB analysis stays clean and
    // the test focuses purely on the truncation-ignore behavior.
    locales: ['en'],
    textScales: [1.0, 2.0],
    viewports: [ViewportPreset.phone],
    ignoreTruncation: [
      TruncationIgnores.byMaxLines(2),
      TruncationIgnores.byText(RegExp(r'^(RCP-|INV-)')),
    ],
    builder: () => Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        child: ListView(
          children: const [
            _ListRow(
              key: Key('brandTag'),
              title: 'Long product name that overflows the available width',
              subtitle: 'RCP-918273645 a deliberately clamped subtitle',
            ),
          ],
        ),
      ),
    ),
  );
}

/// A list row that intentionally clamps its title/subtitle to a single line.
class _ListRow extends StatelessWidget {
  const _ListRow({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
