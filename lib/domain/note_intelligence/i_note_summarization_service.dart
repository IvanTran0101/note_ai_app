import 'summary.dart';

/// Domain contract for summarizing note content.
///
/// Implementations may use a local or remote provider, but the contract does
/// not expose runtime, model, platform, or transport details.
abstract interface class INoteSummarizationService {
  /// Summarizes the supplied raw note [content].
  Future<Summary> summarize(String content);
}
