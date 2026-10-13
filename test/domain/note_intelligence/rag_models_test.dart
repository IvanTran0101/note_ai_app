import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

void main() {
  group('RagScope', () {
    test('account scope carries no note id', () {
      const RagScope scope = RagScope.account();

      expect(scope.type, RagScopeType.account);
      expect(scope.noteId, isNull);
      expect(scope.isAccount, isTrue);
      expect(scope, const RagScope.account());
      expect(scope.toString(), 'RagScope.account()');
    });

    test('note scope keeps the canonical note id', () {
      final RagScope scope = RagScope.note('note-1');

      expect(scope.type, RagScopeType.note);
      expect(scope.noteId, 'note-1');
      expect(scope.isAccount, isFalse);
      expect(scope, RagScope.note('note-1'));
      expect(scope == RagScope.note('note-2'), isFalse);
      expect(scope.hashCode, RagScope.note('note-1').hashCode);
    });

    test('note id must be a trimmed, control-free, well-formed identifier', () {
      expect(() => RagScope.note(''), throwsArgumentError);
      expect(() => RagScope.note('   '), throwsArgumentError);
      expect(() => RagScope.note(' padded '), throwsArgumentError);
      expect(() => RagScope.note('bad\u0000id'), throwsArgumentError);
      expect(() => RagScope.note('bad\u007Fid'), throwsArgumentError);
      expect(() => RagScope.note('\uD800'), throwsArgumentError);
      expect(() => RagScope.note('a' * 129), throwsArgumentError);
    });

    test('note id ceiling counts code points, not UTF-16 units', () {
      final String emoji = '\u{1F600}';

      expect(RagScope.note(emoji * 128).noteId, emoji * 128);
      expect(() => RagScope.note(emoji * 129), throwsArgumentError);
    });
  });

  group('RagRequest', () {
    test('carries the exact question and scope', () {
      final RagRequest request = RagRequest(
        question: '  What did I decide?  ',
        scope: const RagScope.account(),
      );

      expect(request.question, '  What did I decide?  ');
      expect(request.scope, const RagScope.account());
      expect(request, RagRequest(question: '  What did I decide?  ', scope: const RagScope.account()));
      expect(request.toString(), contains('<redacted>'));
      expect(request.toString(), isNot(contains('decide')));
      expect(RagRequest.wireVersion, 1);
      expect(ragWireVersion, 1);
    });

    test('rejects a question that cannot go on the wire', () {
      expect(
        RagRequest.questionProblem(''),
        RagQuestionProblem.blank,
      );
      expect(
        RagRequest.questionProblem('   '),
        RagQuestionProblem.blank,
      );
      expect(
        RagRequest.questionProblem('bad \uD800'),
        RagQuestionProblem.malformed,
      );
      expect(
        RagRequest.questionProblem('a' * (RagRequest.maxQuestionCodePoints + 1)),
        RagQuestionProblem.tooLong,
      );
      expect(
        RagRequest.questionProblem('a' * 2048),
        isNull,
      );
      expect(
        RagRequest.questionProblem('\u{1F600}' * 2048),
        RagQuestionProblem.tooLong,
      );
      expect(
        RagRequest.questionProblem('\u{1F600}' * 1024),
        isNull,
      );
    });

    test('construction throws when the question is invalid', () {
      expect(
        () => RagRequest(question: '   ', scope: const RagScope.account()),
        throwsArgumentError,
      );
      expect(
        () => RagRequest(question: 'bad \uD800', scope: const RagScope.account()),
        throwsArgumentError,
      );
      expect(
        () => RagRequest(
          question: 'a' * (RagRequest.maxQuestionCodePoints + 1),
          scope: const RagScope.account(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('RagSource', () {
    test('keeps a well-formed half-open span', () {
      final RagSource source = RagSource(
        sourceId: 's1',
        noteId: 'note-1',
        revision: 4,
        title: 'Title',
        startOffset: 2,
        endOffset: 6,
        quote: 'cdef',
      );

      expect(source.revision, 4);
      expect(source.matchesContent('abcdefgh'), isTrue);
      expect(source.matchesContent('abXdefgh'), isFalse);
      expect(source.matchesContent('abc'), isFalse);
      expect(source.toString(), isNot(contains('cdef')));
      expect(source.toString(), contains('revision: 4'));
    });

    test('refuses a revision below one and an inverted or negative span', () {
      expect(() => _source(revision: 0), throwsArgumentError);
      expect(() => _source(startOffset: -1, endOffset: 4, quote: 'abcd'), throwsArgumentError);
      expect(() => _source(startOffset: 3, endOffset: 3, quote: ''), throwsArgumentError);
      expect(() => _source(startOffset: 4, endOffset: 2, quote: 'ab'), throwsArgumentError);
    });

    test('refuses a quote that is not exactly the span length', () {
      expect(
        () => _source(startOffset: 0, endOffset: 4, quote: 'abc'),
        throwsArgumentError,
      );
    });

    test('refuses a lone surrogate and an empty quote', () {
      expect(
        () => _source(startOffset: 0, endOffset: 1, quote: '\uD800'),
        throwsArgumentError,
      );
      expect(
        () => _source(startOffset: 0, endOffset: 0, quote: ''),
        throwsArgumentError,
      );
    });

    test('matchesContent requires the exact slice inside the content', () {
      const String content = 'a\u{1F600}b';
      expect(content.length, 4);
      final RagSource emoji = RagSource(
        sourceId: 's1',
        noteId: 'note-1',
        revision: 1,
        title: 'Title',
        startOffset: 1,
        endOffset: 3,
        quote: '\u{1F600}',
      );
      final RagSource pastEnd = RagSource(
        sourceId: 's2',
        noteId: 'note-1',
        revision: 1,
        title: 'Title',
        startOffset: 1,
        endOffset: 4,
        quote: '\u{1F600}b',
      );
      final RagSource otherText = RagSource(
        sourceId: 's3',
        noteId: 'note-1',
        revision: 1,
        title: 'Title',
        startOffset: 1,
        endOffset: 4,
        quote: 'abc',
      );

      expect(emoji.matchesContent(content), isTrue);
      expect(pastEnd.matchesContent('a\u{1F600}'), isFalse);
      expect(pastEnd.matchesContent(content), isTrue);
      expect(otherText.matchesContent(content), isFalse);
      expect(emoji.matchesContent(''), isFalse);
    });
  });

  group('RagResult', () {
    test('answered keeps at least one citation and read-only sources', () {
      final RagSource source = _source();
      final RagResult result = RagResult.answered(
        requestId: 'req-1',
        answer: 'Answer [S1]',
        sources: <RagSource>[source],
      );

      expect(result.status, RagResultStatus.answered);
      expect(result.isAnswered, isTrue);
      expect(result.answer, 'Answer [S1]');
      expect(result.reason, isNull);
      expect(result.sources, <RagSource>[source]);
      expect(result.toString(), isNot(contains('Answer [S1]')));
      expect(() => result.sources.add(source), throwsUnsupportedError);
    });

    test('answered refuses an empty or duplicated citation set', () {
      expect(
        () => RagResult.answered(
          requestId: 'req-1',
          answer: 'Answer',
          sources: const <RagSource>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => RagResult.answered(
          requestId: 'req-1',
          answer: 'Answer',
          sources: <RagSource>[_source(), _source()],
        ),
        throwsArgumentError,
      );
      expect(
        () => RagResult.answered(
          requestId: 'req-1',
          answer: '   ',
          sources: <RagSource>[_source()],
        ),
        throwsArgumentError,
      );
    });

    test('notEnoughContext carries only a canonical verdict', () {
      final RagResult result = RagResult.notEnoughContext(
        requestId: 'req-2',
        reason: RagResult.reasonUnresolvedConflict,
      );

      expect(result.status, RagResultStatus.notEnoughContext);
      expect(result.isAnswered, isFalse);
      expect(result.answer, isNull);
      expect(result.sources, isEmpty);
      expect(result.reason, 'UNRESOLVED_CONFLICT');
      expect(RagResult.reasons, hasLength(3));
      expect(
        () => RagResult.notEnoughContext(requestId: 'req-2', reason: 'MAYBE'),
        throwsArgumentError,
      );
    });
  });

  group('RagConsent', () {
    test('models the default, a grant, and a revoke', () {
      expect(RagConsent.none.accepted, isFalse);
      expect(RagConsent.none.generation, 0);
      expect(RagConsent.none.version, 'rag-consent.v1');
      expect(RagConsent.none.allowsQuery, isFalse);

      final RagConsent granted = RagConsent(accepted: true, generation: 1);
      expect(granted.allowsQuery, isTrue);
      expect(granted, RagConsent(accepted: true, generation: 1));
      expect(
        granted == RagConsent(accepted: true, generation: 2),
        isFalse,
      );

      final RagConsent revoked = RagConsent(accepted: false, generation: 2);
      expect(revoked.generation, 2);
      expect(revoked.allowsQuery, isFalse);
    });

    test('refuses an impossible grant or a foreign version', () {
      expect(
        () => RagConsent(accepted: true, generation: 0),
        throwsArgumentError,
      );
      expect(
        () => RagConsent(accepted: false, generation: -1),
        throwsArgumentError,
      );
      expect(
        () => RagConsent(
          accepted: true,
          version: 'rag-consent.v2',
          generation: 1,
        ),
        throwsArgumentError,
      );
    });

    test('RagConsentUpdate carries the read generation', () {
      final RagConsentUpdate update = RagConsentUpdate(
        accepted: true,
        expectedGeneration: 3,
      );

      expect(update.accepted, isTrue);
      expect(update.version, 'rag-consent.v1');
      expect(update.expectedGeneration, 3);
      expect(
        update,
        RagConsentUpdate(accepted: true, expectedGeneration: 3),
      );
      expect(
        () => RagConsentUpdate(accepted: false, expectedGeneration: -1),
        throwsArgumentError,
      );
      expect(
        () => RagConsentUpdate(
          accepted: false,
          version: 'other',
          expectedGeneration: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('RagFailure', () {
    test('maps every backend code and fails closed on an unknown one', () {
      const Map<String, RagFailureCode> wire = <String, RagFailureCode>{
        'INVALID_INPUT': RagFailureCode.invalidInput,
        'INPUT_TOO_LONG': RagFailureCode.inputTooLong,
        'UNAUTHORIZED': RagFailureCode.unauthorized,
        'CONSENT_REQUIRED': RagFailureCode.consentRequired,
        'SCOPE_DENIED': RagFailureCode.scopeDenied,
        'INDEX_NOT_READY': RagFailureCode.indexNotReady,
        'SOURCE_CHANGED': RagFailureCode.sourceChanged,
        'RATE_LIMITED': RagFailureCode.rateLimited,
        'EVIDENCE_VALIDATION_UNAVAILABLE':
            RagFailureCode.evidenceValidationUnavailable,
        'PROVIDER_UNAVAILABLE': RagFailureCode.providerUnavailable,
        'INVALID_PROVIDER_OUTPUT': RagFailureCode.invalidProviderOutput,
        'TIMEOUT': RagFailureCode.timeout,
        'LIVE_POLICY_NOT_CONFIGURED': RagFailureCode.livePolicyNotConfigured,
      };

      for (final MapEntry<String, RagFailureCode> entry in wire.entries) {
        expect(RagFailureCode.fromWireCode(entry.key), entry.value);
        expect(entry.value.wireCode, entry.key);
        expect(RagFailure.fromWire(entry.key).code, entry.value);
      }
      expect(RagFailureCode.fromWireCode('SOMETHING_NEW'), isNull);
      expect(RagFailureCode.fromWireCode(null), isNull);
      expect(
        RagFailure.fromWire('SOMETHING_NEW').code,
        RagFailureCode.unexpected,
      );
      expect(RagFailureCode.cancelled.wireCode, isNull);
      expect(RagFailureCode.sessionChanged.wireCode, isNull);
      expect(RagFailureCode.network.wireCode, isNull);
      expect(RagFailureCode.consentUnknown.wireCode, isNull);
    });

    test('sanitizes the retry hint and prints the code only', () {
      expect(
        const RagFailure(RagFailureCode.rateLimited, retryAfterSeconds: 5)
            .retryAfterSeconds,
        5,
      );
      expect(
        const RagFailure(RagFailureCode.rateLimited, retryAfterSeconds: 0)
            .retryAfterSeconds,
        isNull,
      );
      expect(
        const RagFailure(RagFailureCode.rateLimited, retryAfterSeconds: 3601)
            .retryAfterSeconds,
        isNull,
      );
      expect(
        const RagFailure(RagFailureCode.providerUnavailable, retryAfterSeconds: 5)
            .retryAfterSeconds,
        isNull,
      );
      expect(
        const RagFailure(RagFailureCode.cancelled).toString(),
        'RagFailure(cancelled)',
      );
      expect(
        const RagFailure(RagFailureCode.cancelled),
        const RagFailure(RagFailureCode.cancelled),
      );
    });
  });

  group('RagCallContext', () {
    test('keeps the captured account, cancellation, and deadline', () async {
      final Completer<void> cancelled = Completer<void>();
      int guards = 0;
      final RagCallContext context = RagCallContext(
        expectedUserId: 'user-1',
        cancelled: cancelled.future,
        beforeDispatch: () async {
          guards++;
        },
        deadline: DateTime.utc(2026, 1, 1, 0, 0, 26),
      );

      expect(RagCallContext.requestBudget, const Duration(seconds: 26));
      expect(context.expectedUserId, 'user-1');
      expect(context.deadline, DateTime.utc(2026, 1, 1, 0, 0, 26));
      await context.beforeDispatch();
      expect(guards, 1);
      expect(cancelled.isCompleted, isFalse);
      expect(context.toString(), contains('user-1'));
      expect(
        () => RagCallContext(
          expectedUserId: '  ',
          cancelled: cancelled.future,
          beforeDispatch: () async {},
          deadline: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });
  });

  group('sensitive errors', () {
    test('a rejected question never echoes its text', () {
      final String malformed = _rejectionMessage(
        () => RagRequest(
          question: '$_secret\uD800',
          scope: const RagScope.account(),
        ),
      );
      expect(malformed, isNot(contains(_secret)));
      expect(malformed, contains('question'));

      final String tooLong = _rejectionMessage(
        () => RagRequest(
          question: '$_secret${'a' * (RagRequest.maxQuestionCodePoints + 1)}',
          scope: const RagScope.account(),
        ),
      );
      expect(tooLong, isNot(contains(_secret)));
      expect(tooLong, contains('question'));
    });

    test('a rejected title, quote, or answer never echoes its text', () {
      final String title = _rejectionMessage(
        () => _source(title: '$_secret\uD800'),
      );
      expect(title, isNot(contains(_secret)));
      expect(title, contains('title'));

      final String quote = _rejectionMessage(
        () => _source(quote: _secret, endOffset: 4),
      );
      expect(quote, isNot(contains(_secret)));
      expect(quote, contains('quote'));

      final String answer = _rejectionMessage(
        () => RagResult.answered(
          requestId: 'req-1',
          answer: '$_secret\uD800',
          sources: <RagSource>[_source()],
        ),
      );
      expect(answer, isNot(contains(_secret)));
      expect(answer, contains('answer'));
    });

    test('a rejected identifier, reason, or version never echoes its value', () {
      final String noteId = _rejectionMessage(
        () => RagScope.note('$_secret\u0000'),
      );
      expect(noteId, isNot(contains(_secret)));
      expect(noteId, contains('noteId'));

      final String sourceId = _rejectionMessage(
        () => _source(sourceId: '$_secret\u0000'),
      );
      expect(sourceId, isNot(contains(_secret)));
      expect(sourceId, contains('sourceId'));

      final String reason = _rejectionMessage(
        () => RagResult.notEnoughContext(requestId: 'req-1', reason: _secret),
      );
      expect(reason, isNot(contains(_secret)));
      expect(reason, contains('reason'));

      final String version = _rejectionMessage(
        () => RagConsent(accepted: true, version: _secret, generation: 1),
      );
      expect(version, isNot(contains(_secret)));
      expect(version, contains('version'));
    });

    test('a rejected citation set never echoes a source id', () {
      final String duplicate = _rejectionMessage(
        () => RagResult.answered(
          requestId: 'req-1',
          answer: 'Answer',
          sources: <RagSource>[
            _source(sourceId: _secret),
            _source(sourceId: _secret),
          ],
        ),
      );
      expect(duplicate, isNot(contains(_secret)));
      expect(duplicate, contains('sources'));
    });

    test('rejections stay ArgumentErrors with the same verdicts', () {
      expect(
        () => RagRequest(
          question: '$_secret\uD800',
          scope: const RagScope.account(),
        ),
        throwsArgumentError,
      );
      expect(() => _source(title: '$_secret\uD800'), throwsArgumentError);
      expect(
        () => RagResult.answered(
          requestId: 'req-1',
          answer: '$_secret\uD800',
          sources: <RagSource>[_source()],
        ),
        throwsArgumentError,
      );
      expect(
        () => RagResult.notEnoughContext(requestId: 'req-1', reason: _secret),
        throwsArgumentError,
      );
    });
  });

  group('architecture', () {
    test('Domain RAG files import no Application, Flutter, or SDK package', () {
      for (final String path in <String>[
        'lib/domain/note_intelligence/rag_models.dart',
        'lib/domain/note_intelligence/rag_call_context_part.dart',
        'lib/domain/note_intelligence/rag_consent_part.dart',
        'lib/domain/note_intelligence/rag_failure_part.dart',
        'lib/domain/note_intelligence/rag_query_part.dart',
        'lib/domain/note_intelligence/rag_result_part.dart',
        'lib/domain/note_intelligence/rag_source_part.dart',
        'lib/domain/note_intelligence/rag_validation_part.dart',
        'lib/domain/note_intelligence/i_rag_gateway.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(source, isNot(contains('package:flutter')));
        expect(source, isNot(contains('/application/')));
        expect(source, isNot(contains("import 'dart:io'")));
        expect(source, isNot(contains("import 'dart:ui'")));
      }
    });

    test('Application RAG files import no Flutter or SDK package', () {
      for (final String path in <String>[
        'lib/application/note_intelligence/rag_app_service.dart',
        'lib/application/note_intelligence/rag_app_binding_part.dart',
        'lib/application/note_intelligence/rag_app_consent_part.dart',
        'lib/application/note_intelligence/rag_app_run_part.dart',
        'lib/application/note_intelligence/rag_app_scope_part.dart',
        'lib/application/note_intelligence/rag_app_source_part.dart',
        'lib/application/note_intelligence/rag_run_context.dart',
        'lib/application/note_intelligence/rag_state.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(source, isNot(contains('package:flutter')));
        expect(source, isNot(contains('/presentation/')));
        expect(source, isNot(contains('/infrastructure/')));
      }
    });
  });
}

/// A marker that must never appear in a rejection message.
const String _secret = 'SECRET_MARKER';

/// Runs [build] and returns the text of the [ArgumentError] it must throw.
String _rejectionMessage(void Function() build) {
  try {
    build();
  } on ArgumentError catch (error) {
    return error.toString();
  }
  fail('the invalid value was accepted');
}

RagSource _source({
  String sourceId = 's1',
  String noteId = 'note-1',
  int revision = 4,
  String title = 'Title',
  int startOffset = 0,
  int endOffset = 4,
  String quote = 'abcd',
}) {
  return RagSource(
    sourceId: sourceId,
    noteId: noteId,
    revision: revision,
    title: title,
    startOffset: startOffset,
    endOffset: endOffset,
    quote: quote,
  );
}
