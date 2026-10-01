import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_failure_mapper.dart';

void main() {
  const String canary = 'canary-note-body-marker';

  group('mapSummaryFailure', () {
    const Map<SummaryApiErrorCode, SummaryRunFailureCode> table =
        <SummaryApiErrorCode, SummaryRunFailureCode>{
          SummaryApiErrorCode.invalidInput: SummaryRunFailureCode.invalidInput,
          SummaryApiErrorCode.inputTooLong: SummaryRunFailureCode.inputTooLong,
          SummaryApiErrorCode.pipelineTooLarge:
              SummaryRunFailureCode.pipelineTooLarge,
          SummaryApiErrorCode.unauthorized: SummaryRunFailureCode.unauthorized,
          SummaryApiErrorCode.consentRequired:
              SummaryRunFailureCode.consentRequired,
          SummaryApiErrorCode.rateLimited: SummaryRunFailureCode.rateLimited,
          SummaryApiErrorCode.providerUnavailable:
              SummaryRunFailureCode.serviceUnavailable,
          SummaryApiErrorCode.invalidOutput:
              SummaryRunFailureCode.invalidOutput,
          SummaryApiErrorCode.timeout: SummaryRunFailureCode.deadlineExceeded,
          SummaryApiErrorCode.networkUnavailable:
              SummaryRunFailureCode.networkUnavailable,
          SummaryApiErrorCode.unexpected: SummaryRunFailureCode.unexpected,
        };

    test('classifies every API code', () {
      expect(
        table.keys.toSet(),
        SummaryApiErrorCode.values.toSet(),
        reason: 'a new API code must be classified here and in the mapper',
      );

      for (final MapEntry<SummaryApiErrorCode, SummaryRunFailureCode> entry
          in table.entries) {
        final SummaryRunFailure mapped = mapSummaryFailure(
          SummaryApiFailure(code: entry.key),
        );

        expect(mapped.code, entry.value, reason: entry.key.name);
        expect(mapped.retryAfterSeconds, isNull, reason: entry.key.name);
      }
    });

    test('preserves a valid rate-limit hint and drops the rest', () {
      SummaryRunFailure mapRate(int? hint) => mapSummaryFailure(
        SummaryApiFailure(
          code: SummaryApiErrorCode.rateLimited,
          retryAfterSeconds: hint,
        ),
      );

      expect(mapRate(90).retryAfterSeconds, 90);
      expect(mapRate(1).retryAfterSeconds, 1);
      expect(mapRate(3600).retryAfterSeconds, 3600);
      expect(mapRate(null).retryAfterSeconds, isNull);
      expect(mapRate(0).retryAfterSeconds, isNull);
      expect(mapRate(-3).retryAfterSeconds, isNull);
      expect(mapRate(3601).retryAfterSeconds, isNull);
      expect(
        mapSummaryFailure(
          const SummaryApiFailure(
            code: SummaryApiErrorCode.unexpected,
            retryAfterSeconds: 60,
          ),
        ).retryAfterSeconds,
        isNull,
      );
    });

    test('returns an existing run failure instance unchanged', () {
      final SummaryRunFailure failure = SummaryRunFailure(
        SummaryRunFailureCode.rateLimited,
        retryAfterSeconds: 45,
      );

      expect(identical(mapSummaryFailure(failure), failure), isTrue);
      expect(mapSummaryFailure(failure).retryAfterSeconds, 45);
    });

    test('maps unknown errors to unexpected without their message', () {
      final List<Object> errors = <Object>[
        StateError(canary),
        Exception(canary),
        FormatException(canary),
        ArgumentError(canary),
        canary,
      ];

      for (final Object error in errors) {
        final SummaryRunFailure mapped = mapSummaryFailure(error);

        expect(
          mapped,
          const SummaryRunFailure(SummaryRunFailureCode.unexpected),
        );
        expect(mapped.retryAfterSeconds, isNull);
        expect(mapped.toString(), 'SummaryRunFailure(unexpected)');
        expect(mapped.toString(), isNot(contains(canary)));
      }
    });
  });

  group('withSummaryFailureBoundary', () {
    test('returns the awaited value', () async {
      expect(await withSummaryFailureBoundary<int>(() async => 7), 7);
    });

    test('maps an asynchronous throw', () async {
      await expectLater(
        withSummaryFailureBoundary<void>(() async {
          throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
        }),
        throwsA(
          const SummaryRunFailure(SummaryRunFailureCode.deadlineExceeded),
        ),
      );
    });

    test('maps a synchronous throw before any future exists', () async {
      await expectLater(
        withSummaryFailureBoundary<void>(() {
          throw StateError(canary);
        }),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.unexpected)),
      );
    });

    test(
      'keeps a run failure instance and its code across the boundary',
      () async {
        final SummaryRunFailure failure = SummaryRunFailure(
          SummaryRunFailureCode.consentRequired,
        );
        Object? caught;

        try {
          await withSummaryFailureBoundary<void>(() async => throw failure);
        } on Object catch (error) {
          caught = error;
        }

        expect(identical(caught, failure), isTrue);
      },
    );

    test('maps a failure thrown after an await inside the callback', () async {
      await expectLater(
        withSummaryFailureBoundary<void>(() async {
          await Future<void>.delayed(Duration.zero);
          throw StateError(canary);
        }),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.unexpected)),
      );
    });
  });
}
