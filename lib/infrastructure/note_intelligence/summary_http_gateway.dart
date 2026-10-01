import 'summary_note_lineage.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../application/note_intelligence/summary_run_context.dart';
import 'summary_api_failure.dart';
import 'summary_http_call.dart';
import 'summary_http_mapper.dart';
import 'summary_request_policy.dart';

part 'summary_http_response.dart';

/// One Summary stage generation: validated final text for exactly one stage.
typedef SummaryStageGenerator = Future<String> Function({
  required SummaryStage stage,
  required List<String> inputs,
  required bool consentAccepted,
  DateTime? deadline,
});

/// HTTP transport for one Summary stage against the contract's `/ai/summary`.
final class SummaryHttpGateway {
  /// Creates a gateway over [baseUri], [policy], and [tokenProvider].
  factory SummaryHttpGateway({
    required Uri baseUri,
    required SummaryRequestPolicy policy,
    required Future<String?> Function({required bool forceRefresh})
    tokenProvider,
    required String expectedAccountUserId,
    SummaryRunScope? runScope,
    SummaryNoteLineage? noteLineage,
    String? Function()? grantHeader,
    Future<void> Function()? beforeDispatch,
    SummaryRunFailureCode? Function()? currentRunFailure,
    http.Client? client,
    Duration timeout = maxTimeout,
  }) {
    return SummaryHttpGateway._(
      baseUri: _validateBaseUri(baseUri),
      policy: policy,
      tokenProvider: tokenProvider,
      expectedAccountUserId: _validateAccountUserId(expectedAccountUserId),
      runScope: runScope,
      noteLineage: noteLineage,
      grantHeader: grantHeader,
      beforeDispatch: beforeDispatch,
      currentRunFailure: currentRunFailure,
      client: client ?? http.Client(),
      ownsClient: client == null,
      timeout: _validateTimeout(timeout),
    );
  }

  SummaryHttpGateway._({
    required this._baseUri,
    required this._policy,
    required this._tokenProvider,
    required this._expectedAccountUserId,
    required this._runScope,
    required this.noteLineage,
    required this.grantHeader,
    required this._beforeDispatch,
    required this._currentRunFailure,
    required this._client,
    required this._ownsClient,
    required this._timeout,
  });

  /// The contract's only route, appended to the base URI's path.
  static const String routePath = 'ai/summary';

  /// Hard ceiling for one [generate] call, from the contract's 35 s/request.
  static const Duration maxTimeout = Duration(seconds: 35);

  /// Transport cap for one response body, from the contract's transport limits.
  static const int maxResponseBytes = 64 * 1024;

  final Uri _baseUri;
  final SummaryRequestPolicy _policy;
  final Future<String?> Function({required bool forceRefresh}) _tokenProvider;
  final String _expectedAccountUserId;
  final SummaryRunScope? _runScope;
  final SummaryNoteLineage? noteLineage;
  final String? Function()? grantHeader;
  final Future<void> Function()? _beforeDispatch;
  final SummaryRunFailureCode? Function()? _currentRunFailure;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  late final SummaryHttpMapper _mapper = SummaryHttpMapper(policy: _policy);

  /// Generates the final text for exactly one [stage].
  Future<String> generate({
    required SummaryStage stage,
    required List<String> inputs,
    required bool consentAccepted,
    DateTime? deadline,
  }) async {
    final Duration? budget = _budgetFor(deadline);
    if (budget == null) {
      // The caller's deadline has already passed: report it without a token
      // read and without a request.
      throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
    }
    final SummaryRunScope? runScope = _runScope;
    if (runScope?.isCancelled ?? false) {
      throw SummaryRunFailure(
        runScope?.cancelReason ?? SummaryRunFailureCode.cancelled,
      );
    }
    final SummaryHttpCall call = SummaryHttpCall(budget, scope: runScope);
    try {
      return await _run(
        call,
        stage: stage,
        inputs: inputs,
        consentAccepted: consentAccepted,
      ).timeout(budget);
    } on TimeoutException {
      call.abortForTimeout();
      throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
    } finally {
      call.dispose();
    }
  }

  /// Releases the HTTP client, but only when this gateway created it.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Runs one whole call - token, optional refresh, and body read - inside
  Future<String> _run(
    SummaryHttpCall call, {
    required SummaryStage stage,
    required List<String> inputs,
    required bool consentAccepted,
  }) {
    final Uint8List body = _requestBody(stage, inputs, consentAccepted);
    return _classify(call, () async {
      final String token = await _token(call, forceRefresh: false);
      final http.StreamedResponse first = await _dispatch(call, body, token);
      if (first.statusCode != 401) {
        return _readMapped(call, stage, first);
      }

      // Exactly one refresh, inside the same deadline, then one resend. The
      // first response is released first so its connection can be reused.
      await _discard(first);
      final String refreshed = await _token(call, forceRefresh: true);
      final http.StreamedResponse second = await _dispatch(
        call,
        body,
        refreshed,
      );
      return _readMapped(call, stage, second);
    });
  }

  Uint8List _requestBody(
    SummaryStage stage,
    List<String> inputs,
    bool consentAccepted,
  ) {
    if (!consentAccepted) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.consentRequired);
    }
    final List<String> copied = List<String>.of(inputs, growable: false);
    if (stage == SummaryStage.merge && copied.length > _policy.maxChunks) {
      // More chunks than one pipeline may ever merge; the orchestrator reports
      // this before its first generation call, and the transport refuses it if
      // it is reached anyway.
      throw const SummaryApiFailure(code: SummaryApiErrorCode.pipelineTooLarge);
    }
    final int estimate;
    try {
      estimate = _policy.estimateInputTokens(stage, copied);
    } on ArgumentError {
      // Wrong input count for the stage, or an input that is empty after the
      // policy's ECMAScript trim.
      throw const SummaryApiFailure(code: SummaryApiErrorCode.invalidInput);
    }
    if (estimate > _policy.maxInputEstimate) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.inputTooLong);
    }

    final Uint8List encoded = utf8.encode(
      _policy.requestJson(
        stage,
        copied,
        note: noteLineage?.forStage(stage, copied),
      ),
    );
    if (encoded.length > _policy.maxBodyBytesUtf8) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.inputTooLong);
    }
    return encoded;
  }

  Future<String> _token(
    SummaryHttpCall call, {
    required bool forceRefresh,
  }) async {
    final String? token = await call.raceScope(
      _tokenProvider(forceRefresh: forceRefresh),
    );
    call.throwIfExpired();
    if (token == null || token.trim().isEmpty) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.unauthorized);
    }
    if (_jwtSubject(token) != _expectedAccountUserId) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.unauthorized);
    }
    // The read may have finished after the deadline (a refresh that took too
    // long, or a session call that never answers): a late token must never
    // start a request that nothing is waiting for any more.
    return token;
  }

  Future<http.StreamedResponse> _dispatch(
    SummaryHttpCall call,
    Uint8List body,
    String token,
  ) async {
    call.throwIfExpired();
    final http.AbortableRequest request = http.AbortableRequest(
      'POST',
      _endpoint(),
      abortTrigger: call.abortTrigger,
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json';
    request.followRedirects = false;
    request.maxRedirects = 0;
    // `bodyBytes` keeps the content type exactly `application/json`; the string
    // setter appends a charset parameter the backend does not expect.
    request.bodyBytes = body;
    final Future<void> Function()? guard = _beforeDispatch;
    if (guard != null) {
      await call.raceScope(guard());
    }
    call.throwIfExpired();
    final SummaryRunFailureCode? invalid = _currentRunFailure?.call();
    if (invalid != null) {
      throw SummaryRunFailure(invalid);
    }
    final grant = grantHeader?.call();
    if (grant != null) request.headers['X-Note-Unlock-Grant'] = grant;
    return _client.send(request);
  }

  Future<String> _readMapped(
    SummaryHttpCall call,
    SummaryStage stage,
    http.StreamedResponse response,
  ) async {
    final Uint8List body = await _readBounded(call, response);
    final guard = _beforeDispatch;
    if (guard != null) await call.raceScope(guard());
    call.throwIfExpired();
    final invalid = _currentRunFailure?.call();
    if (invalid != null) throw SummaryRunFailure(invalid);
    return _mapper.mapResponse(
      stage: stage,
      statusCode: response.statusCode,
      bodyBytes: body,
      headers: response.headers,
    );
  }

  Duration? _budgetFor(DateTime? deadline) {
    if (deadline == null) {
      return _timeout;
    }
    final Duration remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return null;
    }
    return remaining < _timeout ? remaining : _timeout;
  }

  /// Builds the absolute endpoint from the base URI's path and [routePath].
  Uri _endpoint() {
    final String basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path
        : '${_baseUri.path}/';
    return Uri(
      scheme: _baseUri.scheme,
      host: _baseUri.host,
      port: _baseUri.hasPort ? _baseUri.port : null,
      path: '$basePath$routePath',
    );
  }

  static Uri _validateBaseUri(Uri baseUri) {
    if (baseUri.scheme != 'http' && baseUri.scheme != 'https') {
      throw ArgumentError('Summary base URI must be http or https');
    }
    if (baseUri.host.isEmpty) {
      throw ArgumentError('Summary base URI must have a host');
    }
    if (baseUri.userInfo.isNotEmpty) {
      throw ArgumentError('Summary base URI must not carry credentials');
    }
    if (baseUri.hasQuery || baseUri.hasFragment) {
      throw ArgumentError(
        'Summary base URI must not carry a query or fragment',
      );
    }
    return baseUri;
  }

  static String _validateAccountUserId(String expectedAccountUserId) {
    if (expectedAccountUserId.trim().isEmpty) {
      throw ArgumentError('expectedAccountUserId must not be blank');
    }
    return expectedAccountUserId;
  }

  static Duration _validateTimeout(Duration timeout) {
    if (timeout <= Duration.zero || timeout > maxTimeout) {
      throw ArgumentError(
        'Summary timeout must be above zero and at most 35 s',
      );
    }
    return timeout;
  }
}

/// Reads the `sub` claim of a JWT without verifying it.
String? _jwtSubject(String token) {
  final List<String> parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final Object? payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map<String, dynamic>) {
      final Object? subject = payload['sub'];
      return subject is String && subject.isNotEmpty ? subject : null;
    }
  } on Object {
    return null;
  }
  return null;
}
