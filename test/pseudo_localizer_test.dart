import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

String _rendered(WidgetTester tester, String containing) => tester
    .renderObjectList<RenderParagraph>(find.byType(RichText))
    .map((p) => p.text.toPlainText())
    .firstWhere((t) => t.contains(containing));

void main() {
  group('PseudoLocalizer.transform', () {
    test('accents letters, pads and brackets the string', () {
      final out = PseudoLocalizer.transform('Settings');
      expect(out, startsWith('[Šéţţîñĝš'));
      expect(out, endsWith(']'));
      expect(out.length, greaterThan('Settings'.length * 2));
    });

    test('short strings grow more than long ones', () {
      expect(PseudoLocalizer.expansionFor(10), 10);
      expect(PseudoLocalizer.expansionFor(20), 16);
      expect(PseudoLocalizer.expansionFor(100), 30);
    });

    test('padding uses breakable filler words', () {
      final pad = PseudoLocalizer.padding(12);
      expect(pad.length, greaterThanOrEqualTo(12));
      expect(pad, startsWith(' one two'));
    });

    test('leaves numbers, punctuation and icon glyphs alone', () {
      expect(PseudoLocalizer.transform('12:30'), '12:30');
      expect(PseudoLocalizer.transform('+42%'), '+42%');
      expect(PseudoLocalizer.transform(''), '');
      final icon = String.fromCharCode(Icons.settings.codePoint);
      expect(PseudoLocalizer.transform(icon), icon);
    });

    test('keeps non-Latin scripts and only pads them', () {
      final out = PseudoLocalizer.transform('設定');
      expect(out, startsWith('[設定'));
      expect(out, endsWith(']'));
    });
  });

  group('PseudoLocalizer.apply', () {
    testWidgets('expanded text overflows a layout that fits the base locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: Row(children: [Text('Settings'), Text('Profile')]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await PseudoLocalizer.apply(tester);

      expect(tester.takeException(), isA<FlutterError>());
      expect(_rendered(tester, 'Šéţţ'), startsWith('[Šéţţîñĝš'));
    });

    testWidgets('keeps span styling and inline widgets', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 2000,
              child: Text.rich(
                TextSpan(
                  text: 'Hello ',
                  children: [
                    TextSpan(
                      text: 'world',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    WidgetSpan(child: SizedBox(width: 10, height: 10)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await PseudoLocalizer.apply(tester);

      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      final spans = <InlineSpan>[];
      paragraph.text.visitChildren((span) {
        spans.add(span);
        return true;
      });
      expect(spans.whereType<WidgetSpan>(), hasLength(1));
      final bold = spans.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'ŵöŕļð',
      );
      expect(bold.style?.fontWeight, FontWeight.bold);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not touch icons', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Icon(Icons.settings)),
        ),
      );
      await PseudoLocalizer.apply(tester);

      final text = tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .toPlainText();
      expect(text, String.fromCharCode(Icons.settings.codePoint));
    });
  });

  group('SweepVariant pseudo locale', () {
    test('renders the base locale and is labelled PSEUDO', () {
      const variant = SweepVariant(
        locale: pseudoLocale,
        textScale: 1.0,
        viewport: ViewportPreset.phone,
        renderLocale: 'en',
      );
      expect(variant.isPseudo, isTrue);
      expect(variant.renderLocale, 'en');
      expect(variant.isRtl, isFalse);
      expect(variant.displayLabel, startsWith('PSEUDO'));
      expect(variant.screenshotPath('home'), 'home_pseudo_393x852.png');
    });

    test('follows the base locale direction', () {
      const variant = SweepVariant(
        locale: pseudoLocale,
        textScale: 1.0,
        viewport: ViewportPreset.phone,
        renderLocale: 'ar',
      );
      expect(variant.isRtl, isTrue);
    });

    test('regular variants render their own locale', () {
      const variant = SweepVariant(
        locale: 'de',
        textScale: 1.0,
        viewport: ViewportPreset.phone,
      );
      expect(variant.isPseudo, isFalse);
      expect(variant.renderLocale, 'de');
    });
  });

  group('sweepTest with the pseudo locale', () {
    final platformLocales = <String, Locale>{};

    sweepTest(
      'pseudo_flow',
      builder: () => const Center(
        child: SizedBox(
          width: 250,
          child: Text(
            'Settings page',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      locales: ['en', pseudoLocale],
      textScales: [1.0],
      viewports: [ViewportPreset.phone],
      captureScreenshots: false,
      variantBody: (tester, variant) async {
        platformLocales[variant.locale] = tester.platformDispatcher.locale;
      },
    );

    tearDownAll(() {
      final results = sweepResults
          .where((r) => r.flowName == 'pseudo_flow')
          .toList();
      expect(results, hasLength(2));

      final en = results.firstWhere((r) => r.variant.locale == 'en');
      final pseudo = results.firstWhere((r) => r.variant.isPseudo);

      expect(en.truncations, isEmpty);
      expect(pseudo.truncations, hasLength(1));
      expect(pseudo.truncations.single.text, startsWith('[Šéţţîñĝš'));
      expect(pseudo.truncations.single.locale, pseudoLocale);
      expect(platformLocales[pseudoLocale], const Locale('en'));
    });
  });
}
