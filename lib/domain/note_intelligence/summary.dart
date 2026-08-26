/// The user-visible summary produced for a note.
///
/// Summary is a small immutable value object. Runtime details such as the
/// model, model path, latency, and memory usage belong outside the domain.
final class Summary {
  const Summary(this.text);

  /// The generated summary text.
  final String text;

  @override
  bool operator ==(Object other) {
    return other is Summary && other.text == text;
  }

  @override
  int get hashCode => Object.hash(runtimeType, text);

  @override
  String toString() => "Summary('$text')";
}
