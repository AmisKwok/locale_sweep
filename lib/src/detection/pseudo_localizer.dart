import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rewrites rendered text into a longer, accented pseudo-locale form.
///
/// `Settings` becomes `[Šéţţîñĝš one two]`: accented letters reveal clipped
/// diacritics, the padding approximates translation growth, and the brackets
/// show at a glance whether a string was cut off.
class PseudoLocalizer {
  static const _accents = {
    'a': 'á', 'b': 'ƀ', 'c': 'ç', 'd': 'ð', 'e': 'é', 'f': 'ƒ', 'g': 'ĝ', //
    'h': 'ĥ', 'i': 'î', 'j': 'ĵ', 'k': 'ķ', 'l': 'ļ', 'm': 'ɱ', 'n': 'ñ', //
    'o': 'ö', 'p': 'þ', 'q': 'ǫ', 'r': 'ŕ', 's': 'š', 't': 'ţ', 'u': 'û', //
    'v': 'ṽ', 'w': 'ŵ', 'x': 'ẋ', 'y': 'ý', 'z': 'ž', //
    'A': 'Å', 'B': 'Ɓ', 'C': 'Ç', 'D': 'Ð', 'E': 'É', 'F': 'Ƒ', 'G': 'Ĝ', //
    'H': 'Ĥ', 'I': 'Î', 'J': 'Ĵ', 'K': 'Ķ', 'L': 'Ļ', 'M': 'Ṁ', 'N': 'Ñ', //
    'O': 'Ö', 'P': 'Þ', 'Q': 'Ǫ', 'R': 'Ŕ', 'S': 'Š', 'T': 'Ţ', 'U': 'Û', //
    'V': 'Ṽ', 'W': 'Ŵ', 'X': 'Ẋ', 'Y': 'Ý', 'Z': 'Ž',
  };

  static const _filler = [
    'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', //
    'ten',
  ];

  static final _letter = RegExp(r'\p{L}', unicode: true);

  /// Replaces ASCII letters with accented look-alikes.
  static String accent(String text) =>
      text.split('').map((c) => _accents[c] ?? c).join();

  /// Extra characters to add for a string of [length] characters.
  ///
  /// Short strings grow the most in translation (IBM's expansion guideline).
  static int expansionFor(int length) {
    final factor = switch (length) {
      <= 10 => 1.0,
      <= 20 => 0.8,
      <= 30 => 0.6,
      <= 50 => 0.5,
      <= 70 => 0.4,
      _ => 0.3,
    };
    return (length * factor).ceil();
  }

  /// Filler words, separated by spaces, totalling about [count] characters.
  static String padding(int count) {
    final buf = StringBuffer();
    var i = 0;
    while (buf.length < count) {
      buf.write(' ${_filler[i % _filler.length]}');
      i++;
    }
    return buf.toString();
  }

  /// Pseudo-localizes a plain string.
  static String transform(String text) {
    if (!shouldTransform(text)) return text;
    return '[${accent(text)}${padding(expansionFor(text.length))}]';
  }

  /// Whether [text] is user-facing copy worth expanding.
  ///
  /// Text without letters (numbers, times, punctuation) and icon glyphs from
  /// Unicode private-use areas are left as they are.
  static bool shouldTransform(String text) {
    if (!_letter.hasMatch(text)) return false;
    return text.runes.any((r) => !_isPrivateUse(r));
  }

  static bool _isPrivateUse(int rune) =>
      (rune >= 0xE000 && rune <= 0xF8FF) || rune >= 0xF0000;

  /// Pseudo-localizes every text paragraph in the current tree, then pumps a
  /// frame so layout, overflow and truncation reflect the expanded text.
  ///
  /// Call after [WidgetTester.pumpAndSettle]. Widgets that rebuild afterwards
  /// show their original text again.
  static Future<void> apply(WidgetTester tester) async {
    final root = tester.binding.rootElement?.renderObject;
    if (root == null) return;

    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        final plain = object.text.toPlainText(includePlaceholders: false);
        if (shouldTransform(plain)) {
          object.text = _wrap(object.text, plain.length);
        }
      }
      object.visitChildren(visit);
    }

    root.visitChildren(visit);
    await tester.pump();
  }

  static InlineSpan _wrap(InlineSpan span, int length) {
    final style = span.style;
    return TextSpan(
      children: [
        TextSpan(text: '[', style: style),
        _accentSpan(span),
        TextSpan(text: '${padding(expansionFor(length))}]', style: style),
      ],
    );
  }

  static InlineSpan _accentSpan(InlineSpan span) {
    if (span is! TextSpan) return span;
    return TextSpan(
      text: span.text == null ? null : accent(span.text!),
      children: span.children?.map(_accentSpan).toList(),
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}
