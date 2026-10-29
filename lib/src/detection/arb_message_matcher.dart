/// Matches rendered strings against the ARB messages they could come from.
///
/// Literal messages are compared exactly. Messages with ICU arguments are
/// compiled to patterns: `{name}` matches any text, and each `plural` /
/// `select` branch becomes an alternative (`#` matches the plural count).
///
/// Alternatives without literal letters (`{name}`, or a `=0{{count}}`
/// branch) are dropped: they would match any rendered text, including
/// genuinely hardcoded strings.
class ArbMessageMatcher {
  final Set<String> _literals;
  final List<RegExp> _patterns;

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
      final alternatives = _parse(trimmed);
      if (alternatives == null) {
        literals.add(trimmed);
        continue;
      }
      final specific = [
        for (final alt in alternatives)
          if (alt.hasLetters) alt.pattern,
      ];
      if (specific.isEmpty) continue;
      patterns.add(
        RegExp('^(?:${specific.join('|')})\$', dotAll: true, unicode: true),
      );
    }
    return ArbMessageMatcher._(literals, patterns);
  }

  /// Whether [text] could have been produced by one of the messages.
  bool matches(String text) {
    final trimmed = text.trim();
    return _literals.contains(trimmed) ||
        _patterns.any((p) => p.hasMatch(trimmed));
  }

  /// Converts an ICU message to a regular-expression source, or `null` when
  /// the message is malformed.
  static String? toPattern(String message) {
    final alternatives = _parse(message);
    if (alternatives == null) return null;
    final patterns = alternatives.map((a) => a.pattern).toSet();
    return patterns.length == 1 ? patterns.single : '(?:${patterns.join('|')})';
  }

  static List<_Alternative>? _parse(String message) {
    try {
      final parser = _IcuParser(message);
      final alternatives = parser.message(inPlural: false, nested: false);
      return parser.atEnd ? alternatives : null;
    } on FormatException {
      return null;
    }
  }

  /// The names of the ICU arguments [message] references.
  ///
  /// The message is walked rather than scanned for braces, so branch bodies
  /// such as `male {he}` are not read as arguments whatever their spacing
  /// (`{gender, select, male {he}}` is the style used in Flutter's gen-l10n
  /// docs), while nested arguments (`other{{count} items}`) are still found.
  /// Messages the parser rejects fall back to [_fallbackArgumentNames].
  static Set<String> argumentNames(String message) {
    try {
      final parser = _IcuParser(message, collecting: true);
      parser.message(inPlural: false, nested: false);
      if (!parser.atEnd) throw const FormatException('Trailing input');
      return parser.arguments;
    } on FormatException {
      return _fallbackArgumentNames(message);
    }
  }

  /// Argument names for a message the ICU parser cannot parse.
  static Set<String> _fallbackArgumentNames(String message) {
    final names = <String>{};
    for (final match in _argumentPattern.allMatches(message)) {
      if (match.start > 0 && _isWordChar(message.codeUnitAt(match.start - 1))) {
        continue; // `good{Super}` — a branch body, not an argument.
      }
      names.add(match.group(1)!);
    }
    return names;
  }

  static final RegExp _argumentPattern = RegExp(
    r'\{([A-Za-z_][A-Za-z0-9_.-]*)[,}]',
  );

  static bool _isWordChar(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || // A-Z
      (unit >= 0x61 && unit <= 0x7A) || // a-z
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      unit == 0x5F; // _
}

/// One shape a message can render to, and whether it has literal letters.
typedef _Alternative = ({String pattern, bool hasLetters});

class _IcuParser {
  final String source;
  var _i = 0;

  /// Records the argument names it walks past into [arguments].
  final bool collecting;

  final Set<String> arguments = <String>{};

  _IcuParser(this.source, {this.collecting = false});

  bool get atEnd => _i >= source.length;

  static const _any = '.*?';

  static const _wildcard = <_Alternative>[(pattern: _any, hasLetters: false)];

  /// Messages expanding to more branch combinations are treated as malformed.
  static const _maxAlternatives = 256;

  /// Stops for reading an argument name: a comma or a closing brace.
  static const Set<String> _argNameStops = {',', '}'};

  static final _letter = RegExp(r'\p{L}', unicode: true);

  List<_Alternative> message({required bool inPlural, required bool nested}) {
    var alternatives = <_Alternative>[(pattern: '', hasLetters: false)];
    final literal = StringBuffer();
    var literalLetters = false;

    void flush() {
      if (literal.isEmpty) return;
      alternatives = _combine(alternatives, [
        (pattern: literal.toString(), hasLetters: literalLetters),
      ]);
      literal.clear();
      literalLetters = false;
    }

    while (!atEnd) {
      final c = source[_i];
      if (c == '}') {
        if (nested) break;
        throw const FormatException('Unbalanced "}"');
      }
      if (c == '{') {
        flush();
        _i++;
        alternatives = _combine(alternatives, _argument());
        continue;
      }
      if (c == '#' && inPlural) {
        flush();
        alternatives = _combine(alternatives, _wildcard);
      } else {
        literal.write(RegExp.escape(c));
        if (_letter.hasMatch(c)) literalLetters = true;
      }
      _i++;
    }
    flush();
    return alternatives;
  }

  List<_Alternative> _combine(List<_Alternative> a, List<_Alternative> b) {
    if (a.length * b.length > _maxAlternatives) {
      throw const FormatException('Too many branch combinations');
    }
    return [
      for (final x in a)
        for (final y in b)
          (
            pattern: x.pattern + y.pattern,
            hasLetters: x.hasLetters || y.hasLetters,
          ),
    ];
  }

  List<_Alternative> _argument() {
    final name = _readUntil(_argNameStops).trim();
    if (collecting) arguments.add(name);
    if (_take('}')) return _wildcard;
    _expect(',');
    final type = _readUntil(const {',', '}'}).trim();
    if (_take('}')) return _wildcard;
    _expect(',');
    if (type != 'plural' && type != 'select' && type != 'selectordinal') {
      _skipNested();
      return _wildcard;
    }
    final branches = <_Alternative>[];
    while (true) {
      _skipWhitespace();
      if (atEnd) throw const FormatException('Unterminated argument');
      if (_take('}')) break;
      final selector = _readUntil(const {'{', '}'}).trim();
      if (selector.isEmpty || atEnd || source[_i] != '{') {
        throw const FormatException('Missing branch body');
      }
      _i++;
      branches.addAll(message(inPlural: type != 'select', nested: true));
      _expect('}');
    }
    if (branches.isEmpty) throw const FormatException('No branches');
    return branches;
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
