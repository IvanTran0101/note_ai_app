import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/rag_http_mapper.dart';

import 'rag_http_test_support.dart';

/// The strict `200` reader: an exact envelope or a safe
/// [RagFailureCode.invalidProviderOutput]. A `200` never becomes a refusal, an
/// abstention never carries a source, and a citation is only accepted when it
/// repeats the approved span exactly.
void main() {
  const RagHttpMapper mapper = RagHttpMapper();
  const Map<String, String> jsonHeaders = <String, String>{
    'content-type': 'application/json; charset=utf-8',
  };

  Uint8List bytes(Object? body) => Uint8List.fromList(
    utf8.encode(body is String ? body : jsonEncode(body)),
  );

  RagResult query(Object? body, {Map<String, String> headers = jsonHeaders}) {
    return mapper.mapQuery(
      statusCode: 200,
      headers: headers,
      bodyBytes: bytes(body),
    );
  }

  RagConsent consent(Object? body) {
    return mapper.mapConsent(
      statusCode: 200,
      headers: jsonHeaders,
      bodyBytes: bytes(body),
    );
  }

  RagFailureCode problemOf(void Function() action) {
    try {
      action();
    } on RagFailure catch (failure) {
      return failure.code;
    }
    fail('expected a RagFailure');
  }

  group('answered envelope', () {
    test('reads the exact envelope and its citation span', () {
      final RagResult result = query(answeredEnvelope());

      expect(result.isAnswered, isTrue);
      expect(result.requestId, 'req-1');
      expect(result.answer, 'Answer [S1]');
      expect(result.sources, hasLength(1));
      expect(result.sources.single.sourceId, 'S1');
      expect(result.sources.single.noteId, 'note-1');
      expect(result.sources.single.revision, 3);
      expect(result.sources.single.startOffset, 0);
      expect(result.sources.single.endOffset, 4);
      expect(result.sources.single.quote, 'Body');
    });

    test('keeps a UTF-16 span around an emoji code point', () {
      const String quote = 'plan \u{1F600}';
      final RagResult result = query(
        answeredEnvelope(
          sources: <Map<String, Object?>>[
            sourceJson(start: 5, end: 5 + quote.length, quote: quote),
          ],
        ),
      );

      expect(result.sources.single.quote, quote);
      expect(result.sources.single.endOffset - result.sources.single.startOffset,
          quote.length);
    });

    test('reads two labelled sources', () {
      final RagResult result = query(
        answeredEnvelope(
          answer: 'One [S1] and two [S2]',
          sources: <Map<String, Object?>>[
            sourceJson(),
            sourceJson(sourceId: 'S2', noteId: 'note-2'),
          ],
        ),
      );

      expect(result.sources, hasLength(2));
    });

    test('accepts a label repeated in the answer for one source', () {
      // The backend validates citation labels as a set, so the client mirrors it.
      final RagResult result = query(
        answeredEnvelope(answer: 'First [S1], again [S1]'),
      );

      expect(result.sources, hasLength(1));
    });

    test('refuses an unlabelled source', () {
      expect(
        problemOf(() => query(answeredEnvelope(answer: 'No label here'))),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a label that names no source', () {
      expect(
        problemOf(() => query(answeredEnvelope(answer: 'Answer [S2]'))),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a label count that does not match the citation count', () {
      expect(
        problemOf(
          () => query(
            answeredEnvelope(
              answer: 'One [S1]',
              sources: <Map<String, Object?>>[
                sourceJson(),
                sourceJson(sourceId: 'S2'),
              ],
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a duplicate sourceId', () {
      expect(
        problemOf(
          () => query(
            answeredEnvelope(
              answer: 'One [S1]',
              sources: <Map<String, Object?>>[sourceJson(), sourceJson()],
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses an empty or oversized citation list', () {
      expect(
        problemOf(
          () => query(answeredEnvelope(answer: 'Answer [S1]', sources: [])),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      expect(
        problemOf(
          () => query(
            answeredEnvelope(
              answer: List<String>.generate(25, (int i) => '[S${i + 1}]').join(),
              sources: List<Map<String, Object?>>.generate(
                25,
                (int i) => sourceJson(sourceId: 'S${i + 1}'),
              ),
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a quote that is not exactly the span length', () {
      expect(
        problemOf(
          () => query(
            answeredEnvelope(
              sources: <Map<String, Object?>>[
                sourceJson(start: 0, end: 4, quote: 'Bod'),
              ],
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a span that would bisect a surrogate pair', () {
      expect(
        problemOf(
          () => query(
            answeredEnvelope(
              sources: <Map<String, Object?>>[
                sourceJson(start: 0, end: 1, quote: '\uD83D'),
              ],
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses an inverted span and a zero revision', () {
      expect(
        problemOf(
          () => query(
            answeredEnvelope(
              sources: <Map<String, Object?>>[
                sourceJson(start: 4, end: 2, quote: 'xx'),
              ],
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      expect(
        problemOf(
          () => query(
            answeredEnvelope(
              sources: <Map<String, Object?>>[sourceJson(revision: 0)],
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a citation field that is not the exact type', () {
      for (final Map<String, Object?> source in <Map<String, Object?>>[
        sourceJson()..['revision'] = '3',
        sourceJson()..['startOffset'] = 1.5,
        sourceJson()..['quote'] = 4,
        sourceJson()..['noteId'] = '',
        sourceJson()..['title'] = null,
        sourceJson()..['extra'] = true,
      ]) {
        expect(
          problemOf(
            () => query(
              answeredEnvelope(sources: <Map<String, Object?>>[source]),
            ),
          ),
          RagFailureCode.invalidProviderOutput,
        );
      }
    });

    test('refuses a requestId that is not a contract identifier', () {
      expect(
        problemOf(() => query(answeredEnvelope(requestId: '  spaced  '))),
        RagFailureCode.invalidProviderOutput,
      );
    });
  });

  group('abstention envelope', () {
    test('reads the exact refusal', () {
      final RagResult result = query(<String, Object?>{
        'wireVersion': 1,
        'requestId': 'req-1',
        'status': 'NOT_ENOUGH_CONTEXT',
        'reason': 'UNCERTAIN',
        'answer': null,
        'sources': <Object?>[],
      });

      expect(result.status, RagResultStatus.notEnoughContext);
      expect(result.reason, RagResult.reasonUncertain);
      expect(result.answer, isNull);
      expect(result.sources, isEmpty);
    });

    test('accepts every canonical reason exactly', () {
      for (final String reason in RagResult.reasons) {
        expect(
          query(<String, Object?>{
            'wireVersion': 1,
            'requestId': 'req-1',
            'status': 'NOT_ENOUGH_CONTEXT',
            'reason': reason,
            'answer': null,
            'sources': <Object?>[],
          }).reason,
          reason,
        );
      }
    });

    test('refuses a lowercase, unknown, or ALLOW reason', () {
      for (final String reason in <String>[
        'insufficient_evidence',
        'TEAPOT',
        'ALLOW',
      ]) {
        expect(
          problemOf(
            () => query(<String, Object?>{
              'wireVersion': 1,
              'requestId': 'req-1',
              'status': 'NOT_ENOUGH_CONTEXT',
              'reason': reason,
              'answer': null,
              'sources': <Object?>[],
            }),
          ),
          RagFailureCode.invalidProviderOutput,
        );
      }
    });

    test('refuses an abstention that carries an answer or a source', () {
      expect(
        problemOf(
          () => query(<String, Object?>{
            'wireVersion': 1,
            'requestId': 'req-1',
            'status': 'NOT_ENOUGH_CONTEXT',
            'reason': 'UNCERTAIN',
            'answer': 'text',
            'sources': <Object?>[],
          }),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      expect(
        problemOf(
          () => query(<String, Object?>{
            'wireVersion': 1,
            'requestId': 'req-1',
            'status': 'NOT_ENOUGH_CONTEXT',
            'reason': 'UNCERTAIN',
            'answer': null,
            'sources': <Object?>[sourceJson()],
          }),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a missing field', () {
      expect(
        problemOf(
          () => query(<String, Object?>{
            'wireVersion': 1,
            'requestId': 'req-1',
            'status': 'NOT_ENOUGH_CONTEXT',
            'reason': 'UNCERTAIN',
            'sources': <Object?>[],
          }),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });
  });

  group('200 that is not a result', () {
    test('refuses an ERROR envelope served with 200', () {
      expect(
        problemOf(() => query(errorEnvelope('CONSENT_REQUIRED'))),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses an unknown status value', () {
      expect(
        problemOf(
          () => query(<String, Object?>{
            'wireVersion': 1,
            'requestId': 'req-1',
            'status': 'MAYBE',
            'answer': 'x [S1]',
            'sources': <Object?>[sourceJson()],
          }),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a wire version that is not the literal 1', () {
      for (final Object? version in <Object?>[2, '1', 1.0, null]) {
        expect(
          problemOf(
            () => query(<String, Object?>{
              ...answeredEnvelope(),
              'wireVersion': version,
            }),
          ),
          RagFailureCode.invalidProviderOutput,
        );
      }
    });

    test('refuses an extra or missing top-level field', () {
      expect(
        problemOf(
          () => query(<String, Object?>{...answeredEnvelope(), 'model': 'x'}),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      final Map<String, Object?> missing = answeredEnvelope()..remove('sources');
      expect(
        problemOf(() => query(missing)),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a wrong answer type', () {
      for (final Object? answer in <Object?>[null, 4, <String>[], '   ']) {
        expect(
          problemOf(
            () => query(<String, Object?>{...answeredEnvelope(), 'answer': answer}),
          ),
          RagFailureCode.invalidProviderOutput,
        );
      }
    });

    test('refuses a body that is not an object', () {
      expect(
        problemOf(() => query(<Object?>[1, 2])),
        RagFailureCode.invalidProviderOutput,
      );
    });
  });

  group('transport and encoding guards', () {
    test('refuses a null body as invalid provider output', () {
      expect(
        problemOf(
          () => mapper.mapQuery(
            statusCode: 200,
            headers: jsonHeaders,
            bodyBytes: null,
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a content type that is not JSON UTF-8', () {
      for (final String contentType in <String>[
        'text/plain',
        'application/json; charset=utf-16',
        'application/json; boundary=x',
        'application/jsonish',
      ]) {
        expect(
          problemOf(
            () => query(
              answeredEnvelope(),
              headers: <String, String>{'content-type': contentType},
            ),
          ),
          RagFailureCode.invalidProviderOutput,
        );
      }
    });

    test('accepts the JSON content type with and without a charset', () {
      expect(
        query(
          answeredEnvelope(),
          headers: <String, String>{'content-type': 'application/json'},
        ).isAnswered,
        isTrue,
      );
      expect(
        query(
          answeredEnvelope(),
          headers: <String, String>{
            'content-type': 'application/json; charset="utf-8"',
          },
        ).isAnswered,
        isTrue,
      );
    });

    test('refuses a missing content type header', () {
      expect(
        problemOf(
          () => mapper.mapQuery(
            statusCode: 200,
            headers: const <String, String>{},
            bodyBytes: bytes(answeredEnvelope()),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses malformed UTF-8, a duplicate key, and a deep body', () {
      expect(
        problemOf(
          () => mapper.mapQuery(
            statusCode: 200,
            headers: jsonHeaders,
            bodyBytes: Uint8List.fromList(<int>[0xff, 0xfe]),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      expect(
        problemOf(
          () => mapper.mapQuery(
            statusCode: 200,
            headers: jsonHeaders,
            bodyBytes: bytes(
              '{"wireVersion":1,"requestId":"req-1","requestId":"req-2",'
              '"status":"ANSWERED","answer":"Answer [S1]","sources":[]}',
            ),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      expect(
        problemOf(() => query('${'[' * 40}1${']' * 40}')),
        RagFailureCode.invalidProviderOutput,
      );
    });
  });

  group('consent envelope', () {
    test('reads the exact grant', () {
      final RagConsent grant = consent(
        consentEnvelope(accepted: true, generation: 4),
      );

      expect(grant.accepted, isTrue);
      expect(grant.version, RagConsent.currentVersion);
      expect(grant.generation, 4);
    });

    test('reads the default and a revoke', () {
      expect(
        consent(consentEnvelope(accepted: false, generation: 0)).accepted,
        isFalse,
      );
      expect(consent(consentEnvelope(accepted: false, generation: 5)).generation, 5);
    });

    test('refuses an impossible grant or a legacy/foreign version', () {
      expect(
        problemOf(
          () => consent(consentEnvelope(accepted: true, generation: 0)),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      // A legacy v1 grant or another version is never adopted as current permission.
      expect(
        problemOf(
          () => consent(consentEnvelope(version: 'rag-consent.v1')),
        ),
        RagFailureCode.invalidProviderOutput,
      );
      expect(
        problemOf(
          () => consent(consentEnvelope(version: 'rag-consent.v3')),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses a generation that is not a safe non-negative integer', () {
      for (final Object? generation in <Object?>[
        -1,
        1.5,
        '1',
        null,
        9007199254740992,
      ]) {
        expect(
          problemOf(
            () => consent(<String, Object?>{
              ...consentEnvelope(),
              'consent': <String, Object?>{
                'accepted': true,
                'version': RagConsent.currentVersion,
                'generation': generation,
              },
            }),
          ),
          RagFailureCode.invalidProviderOutput,
        );
      }
    });

    test('refuses an unknown field inside the grant', () {
      expect(
        problemOf(
          () => consent(<String, Object?>{
            ...consentEnvelope(),
            'consent': <String, Object?>{
              'accepted': true,
              'version': RagConsent.currentVersion,
              'generation': 1,
              'ownerId': 'user-1',
            },
          }),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('refuses an ERROR envelope served with 200', () {
      expect(
        problemOf(
          () => mapper.mapConsent(
            statusCode: 200,
            headers: jsonHeaders,
            bodyBytes: bytes(errorEnvelope('SOURCE_CHANGED')),
          ),
        ),
        RagFailureCode.invalidProviderOutput,
      );
    });
  });
}
