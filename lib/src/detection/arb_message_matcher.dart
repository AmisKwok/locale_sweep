/// Matches rendered strings against the ARB messages they could come from.
///
/// Literal messages are compared exactly. Messages with ICU arguments are
/// compiled to patterns: `{name}` matches any text, and each `plural` /
/// `select` branch becomes an alternative (`#` matches the plural count).
/// Pattern fragment standing in for the text an ICU argument renders to.
const _any = '.*?';

class ArbMessageMatcher {
  final Set<String> _literals;
  final List<RegExp> _patterns;
  final Map<String, bool> _cache = {};

  ArbMessageMatcher._(this._literals, this._patterns);

  /// Builds a matcher from ARB message values.
  factory ArbMessageMatcher.fromMessages(Iterable<String> messages) {
    final literals = <String>{};
    final patterns = <RegExp>[];
    for (final message in messages) {
      final trimmed = message.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.contains('{')) {
        literals.add(trimmed);
        continue;
      }
      // A message the ICU parser rejects (escaped `'{'`, non-ICU braces,
      // unsupported syntax) must not become a literal: it still contains `{`,
      // so it could never equal rendered text and every string produced by
      // that message would be reported as hardcoded. Treat its placeholders
      // as wildcards instead.
      final pattern = toPattern(trimmed) ?? _wildcardPattern(trimmed);
      patterns.add(RegExp('^$pattern\$', dotAll: true, unicode: true));
    }
    return ArbMessageMatcher._(literals, patterns);
  }

  /// Whether [text] could have been produced by one of the messages.
  bool matches(String text) {
    final trimmed = text.trim();
    // Rendered text repeats across paragraphs; caching keeps a large ARB from
    // being re-matched against every duplicate string.
    return _cache.putIfAbsent(
      trimmed,
      () =>
          _literals.contains(trimmed) ||
          _patterns.any((p) => p.hasMatch(trimmed)),
    );
  }

  /// Fallback for messages [toPattern] cannot parse: keeps the literal text
  /// and turns every `{...}` group into a wildcard match.
  static String _wildcardPattern(String message) {
    final buf = StringBuffer();
    var i = 0;
    while (i < message.length) {
      if (message[i] == '{') {
        var depth = 0;
        while (i < message.length) {
          final char = message[i];
          if (char == '{') {
            depth++;
          } else if (char == '}') {
            depth--;
            i++;
            if (depth == 0) break;
            continue;
          }
          i++;
        }
        buf.write(_any);
        continue;
      }
      buf.write(RegExp.escape(message[i]));
      i++;
    }
    return buf.toString();
  }

  /// Converts an ICU message to a regular-expression source, or `null` when
  /// the message is malformed.
  static String? toPattern(String message) {
    try {
      final parser = _IcuParser(message);
      final pattern = parser.message(inPlural: false, nested: false);
      return parser.atEnd ? pattern : null;
    } on FormatException {
      return null;
    }
  }
}

class _IcuParser {
  final String source;
  var _i = 0;

  _IcuParser(this.source);

  bool get atEnd => _i >= source.length;

  String message({required bool inPlural, required bool nested}) {
    final buf = StringBuffer();
    while (!atEnd) {
      final c = source[_i];
      if (c == '}') {
        if (nested) break;
        throw const FormatException('Unbalanced "}"');
      }
      if (c == '{') {
        _i++;
        buf.write(_argument());
        continue;
      }
      buf.write(c == '#' && inPlural ? _any : RegExp.escape(c));
      _i++;
    }
    return buf.toString();
  }

  String _argument() {
    _readUntil(const {',', '}'});
    if (_take('}')) return _any;
    _expect(',');
    final type = _readUntil(const {',', '}'}).trim();
    if (_take('}')) return _any;
    _expect(',');
    if (type != 'plural' && type != 'select' && type != 'selectordinal') {
      _skipNested();
      return _any;
    }
    final branches = <String>[];
    while (true) {
      _skipWhitespace();
      if (atEnd) throw const FormatException('Unterminated argument');
      if (_take('}')) break;
      final selector = _readUntil(const {'{', '}'}).trim();
      if (selector.isEmpty || atEnd || source[_i] != '{') {
        throw const FormatException('Missing branch body');
      }
      _i++;
      branches.add(message(inPlural: type != 'select', nested: true));
      _expect('}');
    }
    if (branches.isEmpty) throw const FormatException('No branches');
    return '(?:${branches.join('|')})';
  }

  String _readUntil(Set<String> stops) {
    final start = _i;
    while (!atEnd && !stops.contains(source[_i])) {
      if (source[_i] == '{') throw const FormatException('Unexpected "{"');
      _i++;
    }
    if (atEnd) throw const FormatException('Unterminated argument');
    return source.substring(start, _i);
  }

  void _skipNested() {
    var depth = 1;
    while (!atEnd) {
      final c = source[_i++];
      if (c == '{') depth++;
      if (c == '}' && --depth == 0) return;
    }
    throw const FormatException('Unterminated argument');
  }

  void _skipWhitespace() {
    while (!atEnd && source[_i].trim().isEmpty) {
      _i++;
    }
  }

  bool _take(String c) {
    if (!atEnd && source[_i] == c) {
      _i++;
      return true;
    }
    return false;
  }

  void _expect(String c) {
    if (!_take(c)) throw FormatException('Expected "$c"');
  }
}
