import 'dart:convert';

/// Decodes the JSON payload of a single line of `flutter test --machine`
/// output.
///
/// Machine output mixes several line shapes, and only some of them carry the
/// `type` field the reports are built from:
///
/// * plain startup text (`Building flutter tool...`),
/// * a JSON **array** line,
///   `[{"event":"test.startedProcess","params":{...}}]`,
/// * the event objects (`{"type":"testStart"...}`, `{"type":"testDone"...}`,
///   `{"type":"done"...}`).
///
/// Every JSON object found on the line is returned, so the payload of an array
/// line is preserved instead of discarded. Lines without JSON, and JSON that is
/// not an object, produce an empty result.
///
/// Decoding must never throw: a bare `jsonDecode(line) as Map<String, dynamic>`
/// raises a `TypeError` on the array line (a `List` is not a `Map`), which is
/// not caught by `on FormatException` and used to abort the CLI before it wrote
/// any results or report. This helper is internal — it is intentionally not
/// exported by `package:locale_sweep/locale_sweep.dart`.
List<Map<String, dynamic>> parseMachineLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return const [];

  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return const [];
  }

  if (decoded is Map<String, dynamic>) return [decoded];
  if (decoded is List) {
    return decoded.whereType<Map<String, dynamic>>().toList();
  }
  return const [];
}
