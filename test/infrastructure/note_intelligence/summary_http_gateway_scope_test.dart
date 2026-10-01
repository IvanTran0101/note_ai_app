import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_http_gateway.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

import 'summary_policy_test_support.dart' show loadSummaryTestPolicy;
import 'summary_gateway_test_support.dart'
    show SummaryTestClient, jwt, successBody;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SummaryRequestPolicy> loadPolicy() => loadSummaryTestPolicy();

  SummaryHttpGateway createGateway({
    required SummaryRequestPolicy policy,
    required http.Client client,
    required SummaryRunScope scope,
    Future<String?> Function({required bool forceRefresh})? tokenProvider,
    Future<void> Function()? beforeDispatch,
    SummaryRunFailureCode? Function()? currentRunFailure,
  }) => SummaryHttpGateway(
    baseUri: Uri.parse('https://api.example.test/prod'),
    policy: policy,
    tokenProvider:
        tokenProvider ?? ({required bool forceRefresh}) async => jwt('user-1'),
    expectedAccountUserId: 'user-1',
    runScope: scope,
    beforeDispatch: beforeDispatch,
    currentRunFailure: currentRunFailure,
    client: client,
  );

  Future<String> generate(SummaryHttpGateway gateway) => gateway.generate(
    stage: SummaryStage.direct,
    inputs: const <String>['synthetic note'],
    consentAccepted: true,
  );

  test('pre-dispatch guard failure stays typed and sends no request', () async {
    final SummaryRequestPolicy policy = await loadPolicy();
    int sends = 0;
    final MockClient client = MockClient((http.Request request) async {
      sends++;
      return http.Response(successBody(), 200);
    });
    addTearDown(client.close);
    final SummaryHttpGateway gateway = createGateway(
      policy: policy,
      client: client,
      scope: SummaryRunScope(),
      beforeDispatch: () async {
        throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
      },
    );

    await expectLater(
      generate(gateway),
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
    );
    expect(sends, 0);
  });

  test(
    'cancelling a pending token read completes and blocks a late token',
    () async {
      final SummaryRequestPolicy policy = await loadPolicy();
      final Completer<String?> token = Completer<String?>();
      final Completer<void> tokenRead = Completer<void>();
      int sends = 0;
      final MockClient client = MockClient((http.Request request) async {
        sends++;
        return http.Response(successBody(), 200);
      });
      addTearDown(client.close);
      final SummaryRunScope scope = SummaryRunScope();
      final Future<String> pending = generate(
        createGateway(
          policy: policy,
          client: client,
          scope: scope,
          tokenProvider: ({required bool forceRefresh}) {
            tokenRead.complete();
            return token.future;
          },
        ),
      );
      await tokenRead.future;
      scope.cancel(reason: SummaryRunFailureCode.sessionChanged);

      await expectLater(
        pending,
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.sessionChanged)),
      );
      token.complete(jwt('user-1'));
      await Future<void>.delayed(Duration.zero);
      expect(sends, 0);
    },
  );

  test('revalidates after token refresh before the resend', () async {
    final SummaryRequestPolicy policy = await loadPolicy();
    int sends = 0;
    int tokenReads = 0;
    final MockClient client = MockClient((http.Request request) async {
      sends++;
      return http.Response(
        '{"error":{"code":"unauthorized"},"requestId":"synthetic"}',
        401,
      );
    });
    addTearDown(client.close);
    final SummaryHttpGateway gateway = createGateway(
      policy: policy,
      client: client,
      scope: SummaryRunScope(),
      tokenProvider: ({required bool forceRefresh}) async {
        tokenReads++;
        return jwt('user-1');
      },
      beforeDispatch: () async {
        if (tokenReads == 2) {
          throw const SummaryRunFailure(SummaryRunFailureCode.consentRequired);
        }
      },
    );

    await expectLater(
      generate(gateway),
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.consentRequired)),
    );
    expect(tokenReads, 2);
    expect(sends, 1);
  });

  test(
    'scope cancellation aborts and releases an in-flight response stream',
    () async {
      final SummaryRequestPolicy policy = await loadPolicy();
      final StreamController<List<int>> body = StreamController<List<int>>();
      final Completer<void> requested = Completer<void>();
      final Completer<void> bodyCancelled = Completer<void>();
      body.onCancel = bodyCancelled.complete;
      final SummaryTestClient client = SummaryTestClient((
        http.BaseRequest request,
      ) async {
        requested.complete();
        return http.StreamedResponse(body.stream, 200);
      });
      addTearDown(client.close);
      final SummaryRunScope scope = SummaryRunScope();
      final Future<String> pending = generate(
        createGateway(policy: policy, client: client, scope: scope),
      );
      await requested.future;
      scope.cancel(reason: SummaryRunFailureCode.cancelled);

      await expectLater(
        pending,
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.cancelled)),
      );
      await bodyCancelled.future;
    },
  );
}
