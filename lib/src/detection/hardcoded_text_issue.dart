/// Rendered text that matches no ARB message for the variant's locale.
class HardcodedTextIssue {
  /// The rendered text.
  final String text;

  /// The locale of the variant where the text was rendered.
  final String locale;

  const HardcodedTextIssue({required this.text, required this.locale});

  Map<String, dynamic> toJson() => {'text': text, 'locale': locale};

  factory HardcodedTextIssue.fromJson(Map<String, dynamic> json) =>
      HardcodedTextIssue(
        text: json['text'] as String,
        locale: json['locale'] as String,
      );

  @override
  String toString() {
    final shown = text.length > 50 ? '${text.substring(0, 47)}...' : text;
    return 'Hardcoded text: "$shown" matches no ARB message for $locale';
  }
}
