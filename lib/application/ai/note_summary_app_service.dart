import '../../domain/note_intelligence/i_note_summarization_service.dart';
import '../../domain/note_intelligence/summary.dart';

/// Application use case for summarizing note content.
///
/// The application layer depends on the Domain contract only. A local or
/// remote Infrastructure implementation is supplied by the composition root.
final class NoteSummaryAppService {
  const NoteSummaryAppService({required this.summarizationService});

  final INoteSummarizationService summarizationService;

  Future<Summary> summarize(String content) {
    return summarizationService.summarize(content);
  }
}
