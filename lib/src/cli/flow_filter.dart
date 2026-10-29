import 'dart:io';

import 'package:path/path.dart' as p;

final _flowDeclaration = RegExp(r'''sweepTest\s*\(\s*(['"])(.*?)\1''');

/// Test files and an optional `flutter test --name` pattern for `--flows`.
class FlowSelection {
  final List<String> files;
  final String? namePattern;

  /// Flow names declared in the scanned sources, for error messages.
  final Set<String> declaredFlows;

  const FlowSelection({
    required this.files,
    required this.namePattern,
    required this.declaredFlows,
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
  // (or computed names), so it must run unfiltered. Say so: silently running
  // every flow in the file is wider than the user asked for.
  if (matchedByFileNameOnly) {
    stderr.writeln(
      'Warning: --flows matched file name(s) only; every sweep flow declared '
      'in ${files.join(', ')} will run.',
    );
  }
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
  );
}
