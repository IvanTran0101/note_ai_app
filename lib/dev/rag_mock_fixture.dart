/// The single synthetic fixture note and the exact documented questions of the
/// offline RAG mock.
///
/// The fixture is intentionally small and fully synthetic: one owned, synced,
/// unprotected note per actor, whose answerable span contains a surrogate pair
/// so the UTF-16 half-open offsets of the real citation contract are exercised.
library;

import 'rag_mock_actors.dart';

/// The exact question the mock answers from the selected actor's fixture note.
///
/// Any other question (including [ragMockUnrelatedQuestion]) is answered with a
/// normal `NOT_ENOUGH_CONTEXT` refusal, never with a copy of this fixture.
const String ragMockAnswerableQuestion =
    'What does the offline mock fixture note plan?';

/// A documented unrelated question that must abstain.
const String ragMockUnrelatedQuestion =
    'What is the warranty period for a fictional device?';

/// One validated synthetic fixture for exactly one actor.
final class RagMockFixture {
  RagMockFixture._({
    required this.actor,
    required this.noteId,
    required this.title,
    required this.content,
    required this.serverRevision,
    required this.quote,
    required this.startOffset,
    required this.endOffset,
    required this.answer,
  });

  /// Builds the fixed fixture for [actor], deriving the exact span from the
  /// fixture content rather than hard-coding offsets.
  factory RagMockFixture.forActor(RagMockActor actor) {
    final String name = actor.user.name;
    final String content =
        'Offline mock fixture for $name: ship the RAG demo 😀 then review '
        'tiếng Việt notes.';
    const String quote = 'RAG demo 😀 then review';
    final int start = content.indexOf(quote);
    if (start < 0) {
      throw StateError('The RAG mock fixture quote is missing.');
    }
    return RagMockFixture._(
      actor: actor,
      noteId: 'rag-mock-note-$name',
      title: 'Offline RAG mock fixture ($name)',
      content: content,
      serverRevision: 7,
      quote: quote,
      startOffset: start,
      endOffset: start + quote.length,
      answer:
          'Fixture answer for the $name actor: the note plans to ship the '
          'offline RAG demo [S1].',
    );
  }

  /// The actor whose store holds this note.
  final RagMockActor actor;

  /// Canonical note id, distinct per actor.
  final String noteId;

  /// Note title as the citation reports it.
  final String title;

  /// Note body the citation span is taken from.
  final String content;

  /// Server revision the mock reports and the citation carries.
  final int serverRevision;

  /// The exact cited slice of [content].
  final String quote;

  /// Inclusive start of the half-open UTF-16 span.
  final int startOffset;

  /// Exclusive end of the half-open UTF-16 span.
  final int endOffset;

  /// The exact synthetic answer text, carrying one `[S1]` citation label.
  final String answer;

  /// The exact `sources[0]` object the frozen `wireVersion` 1 mapper accepts.
  Map<String, Object?> get sourceWire => <String, Object?>{
    'sourceId': 'S1',
    'noteId': noteId,
    'revision': serverRevision,
    'title': title,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'quote': quote,
  };
}

/// The fixed fixture for [actor].
RagMockFixture ragMockFixtureFor(RagMockActor actor) =>
    RagMockFixture.forActor(actor);
