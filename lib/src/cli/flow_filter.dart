import 'package:path/path.dart' as p;

final _flowDeclaration = RegExp(r'''sweepTest\s*\(\s*(['"])(.*?)\1''');

/// Test files and an optional `flutter test --name` pattern for `--flows`.
class FlowSelection {
  final List<String> files;
  final String? namePattern;

  /// Flow names declared in the scanned sources, for error messages.
  final Set<String> declaredFlows;

  /// True when at least one selected file was matched by its name only, so it
  /// runs unfiltered and may execute flows the user did not name. The caller
  /// prints the warning; this stays a pure function.
  final bool matchedByFileNameOnly;

  const FlowSelection({
    required this.files,
    required this.namePattern,
    required this.declaredFlows,
    this.matchedByFileNameOnly = false,
  });
}

/// Selects test files for [names], given each file's path and source.
///
/// A name matches a `sweepTest('<name>', ...)` declaration or, for
/// compatibility, a file named `<name>_test.dart`.
FlowSelection selectFlows(Map<String, String> sources, Set<String> names) {
  final files = <String>[];
  final declared = <String>{};
  final matchedByDeclaration = <String>{};
  var matchedByFileNameOnly = false;

  for (final MapEntry(key: path, value: source) in sources.entries) {
    final fileFlows = _flowDeclaration
        .allMatches(source)
        .map((m) => m[2]!)
        .toSet();
    declared.addAll(fileFlows);
    final base = p.basename(path).replaceFirst(RegExp(r'_test\.dart$'), '');
    final hits = fileFlows.intersection(names);
    final baseHit = names.contains(base);
    if (hits.isEmpty && !baseHit) continue;
    files.add(path);
    matchedByDeclaration.addAll(hits);
    if (baseHit && !fileFlows.contains(base)) matchedByFileNameOnly = true;
  }

  // A file matched only by its name may declare flows under other names
  // (or computed names), so it must run unfiltered. Flag it for the caller to
  // warn about: silently running every flow in the file is wider than the user
  // asked for.
  final namePattern = matchedByFileNameOnly || matchedByDeclaration.isEmpty
      ? null
      : '^sweep: (?:${matchedByDeclaration.map((n) {
          final e = RegExp.escape(n);
          return '$e $e \\[';
        }).join('|')})';

  return FlowSelection(
    files: files,
    namePattern: namePattern,
    declaredFlows: declared,
    matchedByFileNameOnly: matchedByFileNameOnly,
  );
}
