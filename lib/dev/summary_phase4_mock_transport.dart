/// Offline Summary transport mock: the frozen contract, answered locally.
///
/// This library is imported by the widget-test harness and by the offline tool
/// entrypoint (`tool/summary_phase4_mock.dart`), so it must never import
/// `package:flutter_test/flutter_test.dart`. It performs no real I/O: every
/// response is built in memory, and the reserved `summary-mock.invalid` host is
/// never contacted.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Compile-time sentinel that keeps offline runs away from every live endpoint.
///
/// `lib/main.dart` treats a non-empty `NOTEFLOW_SYNC_API` as a sync API
/// endpoint, and falls back to the generated Amplify outputs when it is blank.
/// Pinning it to a value that cannot parse as an absolute `https` URI disables
/// the sync runtime entirely, so no live AWS call is possible.
const String summaryMockSyncApiDefine = 'summary-mock-disabled';

/// Whether this compilation pinned `NOTEFLOW_SYNC_API` to the offline sentinel.
///
/// The tool and the acceptance tests fail fast when this is false instead of
/// risking a live sync endpoint from the generated Amplify outputs.
const bool summaryMockSyncApiPinned =
    String.fromEnvironment('NOTEFLOW_SYNC_API') == summaryMockSyncApiDefine;

/// How the mock transport answers the next request.
enum SummaryMockMode {
  /// A valid contract success envelope.
  ready,

  /// A success envelope that never arrives until the delay elapses, so a
  /// cancelled or disposed run can be observed against a still-pending call.
  delayed,

  /// HTTP 429 with a bounded `Retry-After` hint.
  rateLimited,

  /// HTTP 502 classified as `providerUnavailable`.
  providerUnavailable,

  /// HTTP 502 classified as `invalidOutput`.
  invalidOutput,

  /// HTTP 401, which the gateway may refresh exactly once.
  unauthorized;

  /// Short label for the tool overlay.
  String get label => switch (this) {
    SummaryMockMode.ready => 'ready',
    SummaryMockMode.delayed => 'delayed',
    SummaryMockMode.rateLimited => 'rateLimited',
    SummaryMockMode.providerUnavailable => 'providerUnavailable',
    SummaryMockMode.invalidOutput => 'invalidOutput',
    SummaryMockMode.unauthorized => 'unauthorized',
  };
}

/// Observable smoke state shared by the client and the tool overlay.
final class SummaryMockControl {
  /// Creates a control surface with an initial [mode].
  SummaryMockControl({
    SummaryMockMode mode = SummaryMockMode.ready,
    String policySource = 'bundled',
  }) : mode = ValueNotifier<SummaryMockMode>(mode),
       policySource = ValueNotifier<String>(policySource);

  /// Live mode; the tool overlay mutates it to steer the mock.
  final ValueNotifier<SummaryMockMode> mode;

  /// `bundled` for the real asset loader, `injected` for a test loader.
  final ValueNotifier<String> policySource;

  /// Flips to true once a policy document was actually loaded.
  final ValueNotifier<bool> policyLoaded = ValueNotifier<bool>(false);

  /// Number of Summary HTTP requests the mock answered.
  final ValueNotifier<int> requestCount = ValueNotifier<int>(0);

  /// Returns the mock to its default ready state.
  void reset() {
    mode.value = SummaryMockMode.ready;
    requestCount.value = 0;
  }
}

/// One recorded Summary HTTP request, decoded from the frozen request body.
final class SummaryMockRequest {
  /// Creates a record for one [stage] call.
  const SummaryMockRequest({
    required this.stage,
    required this.inputs,
    required this.consentAccepted,
    required this.consentVersion,
  });

  /// The requested stage (`direct`, `section`, or `merge`).
  final String stage;

  /// The exact inputs the gateway sent.
  final List<String> inputs;

  /// Whether the body declared accepted consent.
  final bool consentAccepted;

  /// The consent version the body declared.
  final String consentVersion;
}

/// Deterministic stage text the mock serves as `summary`.
///
/// The text carries the request ordinal, so a test can tell a late answer from
/// the result that is still on screen.
String summaryMockText(String stage, int requestNumber) =>
    'MOCK SUMMARY ($stage) #$requestNumber';

/// A synthetic Cognito-shaped access token; never a real credential.
///
/// Only the payload segment matters: the gateway reads `sub` and compares it
/// with the account the run was captured for.
String summaryMockJwt(String subject, {String id = 'mock'}) {
  final Map<String, Object?> payload = <String, Object?>{
    'token_use': 'access',
    'jti': id,
    'sub': subject,
  };
  return '${_jwtSegment(<String, Object?>{'alg': 'RS256', 'typ': 'JWT'})}'
      '.${_jwtSegment(payload)}.c2lnbmF0dXJl';
}

String _jwtSegment(Map<String, Object?> payload) =>
    base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');

/// In-memory Summary transport that speaks the frozen contract locally.
///
/// It counts and records every request, answers [SummaryMockMode] scenarios,
/// and honours the abort trigger of an `AbortableRequest`, so a cancelled run
/// releases its pending mock call instead of leaving it dangling.
final class SummaryMockHttpClient extends http.BaseClient {
  /// Creates a client over [control].
  SummaryMockHttpClient({
    required this.control,
    this.delay = const Duration(seconds: 30),
  });

  /// Shared counters, policy label, and live mode.
  final SummaryMockControl control;

  /// How long [SummaryMockMode.delayed] holds one response.
  final Duration delay;

  /// Every request this client answered, in arrival order.
  final List<SummaryMockRequest> requests = <SummaryMockRequest>[];

  /// The `summary` value served by the last success envelope.
  String? lastSummary;

  /// Whether a pending delayed response is still outstanding.
  bool get hasPendingCall => _pending > 0;

  /// Completes the pending [SummaryMockMode.delayed] response immediately.
  ///
  /// Tests use it to let a cancelled run's late answer arrive on purpose; the
  /// held timer is cancelled first, so no timer is left behind.
  void releaseHeld() {
    final void Function()? release = _releaseHeld;
    _releaseHeld = null;
    release?.call();
  }

  void Function()? _releaseHeld;
  bool _closed = false;
  int _pending = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final List<int> bytes = await request.finalize().toBytes();
    final SummaryMockRequest recorded = _record(bytes);
    requests.add(recorded);
    control.requestCount.value = control.requestCount.value + 1;
    return switch (control.mode.value) {
      SummaryMockMode.ready => _success(recorded),
      SummaryMockMode.delayed => _hold(request, recorded),
      SummaryMockMode.rateLimited => _envelope(
        429,
        'rateLimited',
        headers: const <String, String>{'retry-after': '3'},
      ),
      SummaryMockMode.providerUnavailable => _envelope(
        502,
        'providerUnavailable',
      ),
      SummaryMockMode.invalidOutput => _envelope(502, 'invalidOutput'),
      SummaryMockMode.unauthorized => _envelope(401, 'unauthorized'),
    };
  }

  @override
  void close() {
    _closed = true;
    super.close();
  }

  /// Whether [close] was called; the tool surfaces it in the overlay.
  bool get isClosed => _closed;

  /// Holds one success envelope for [delay], or until the call is aborted.
  Future<http.StreamedResponse> _hold(
    http.BaseRequest request,
    SummaryMockRequest recorded,
  ) {
    final Completer<http.StreamedResponse> completer =
        Completer<http.StreamedResponse>();
    _pending++;
    void finish(http.StreamedResponse response) {
      if (completer.isCompleted) {
        return;
      }
      _pending--;
      _releaseHeld = null;
      completer.complete(response);
    }

    void fail(http.ClientException error) {
      if (completer.isCompleted) {
        return;
      }
      _pending--;
      _releaseHeld = null;
      completer.completeError(error, StackTrace.current);
    }

    final Timer timer = Timer(delay, () => finish(_success(recorded)));
    _releaseHeld = () {
      timer.cancel();
      finish(_success(recorded));
    };
    final http.AbortableRequest? abortable = request is http.AbortableRequest
        ? request
        : null;
    // The trigger is nullable on the request type even though the gateway
    // always supplies one, so it is checked rather than assumed.
    final Future<void>? abortTrigger = abortable?.abortTrigger;
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((void _) {
          timer.cancel();
          fail(http.ClientException('mock request aborted', request.url));
        }),
      );
    }
    return completer.future;
  }

  http.StreamedResponse _success(SummaryMockRequest recorded) {
    final String text = summaryMockText(recorded.stage, requests.length);
    lastSummary = text;
    return _body(200, <String, Object?>{
      'summary': text,
      'requestId': 'mock-request-${requests.length}',
      'usage': <String, Object?>{'inputTokens': 120, 'outputTokens': 20},
    });
  }

  http.StreamedResponse _envelope(
    int statusCode,
    String code, {
    Map<String, String> headers = const <String, String>{},
  }) => _body(statusCode, <String, Object?>{
    'error': <String, Object?>{'code': code},
    'requestId': 'mock-request-${requests.length}',
  }, headers: headers);

  http.StreamedResponse _body(
    int statusCode,
    Map<String, Object?> payload, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(payload))),
      statusCode,
      headers: <String, String>{'content-type': 'application/json', ...headers},
      contentLength: utf8.encode(jsonEncode(payload)).length,
    );
  }

  /// Decodes the frozen request body; a malformed body records `unknown`.
  static SummaryMockRequest _record(List<int> bytes) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) {
        final Object? consent = decoded['consent'];
        return SummaryMockRequest(
          stage: decoded['stage'] is String ? decoded['stage'] as String : '',
          inputs: (decoded['inputs'] as List<dynamic>? ?? <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
          consentAccepted:
              consent is Map<String, dynamic> && consent['accepted'] == true,
          consentVersion: consent is Map<String, dynamic>
              ? '${consent['version']}'
              : '',
        );
      }
    } on Object {
      // Fall through to the unknown record; the contract mapper never sees it.
    }
    return const SummaryMockRequest(
      stage: 'unknown',
      inputs: <String>[],
      consentAccepted: false,
      consentVersion: '',
    );
  }
}
