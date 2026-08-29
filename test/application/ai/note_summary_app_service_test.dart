import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/ai/note_summary_app_service.dart';
import 'package:note_ai_app/domain/note_intelligence/i_note_summarization_service.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';

final class _FakeSummarizationService implements INoteSummarizationService {
  String? receivedContent;

  @override
  Future<Summary> summarize(String content) async {
    receivedContent = content;
    return const Summary('fake summary');
  }
}

void main() {
  test('application service delegates through the Domain contract', () async {
    final _FakeSummarizationService fake = _FakeSummarizationService();
    final NoteSummaryAppService service = NoteSummaryAppService(
      summarizationService: fake,
    );

    final Summary result = await service.summarize('note content');

    expect(result, const Summary('fake summary'));
    expect(fake.receivedContent, 'note content');
  });
}
