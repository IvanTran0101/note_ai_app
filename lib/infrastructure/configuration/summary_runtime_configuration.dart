/// Boot-time configuration for cloud Summary.
///
/// The HTTPS endpoint comes from `NOTEFLOW_AI_API` or the generated Amplify
/// outputs' custom `aiApiEndpoint` key. Endpoint values stay out of failures
/// and [SummaryRuntimeConfiguration.toString].
library;

import 'dart:convert';

/// Which Summary runtime one build selected.
enum SummaryRuntimeMode {
  /// The contract's `/ai/summary` route through the remote service.
  remote,

  /// The mode is unsupported, or the endpoint is missing or invalid.
  unavailable,
}

/// Why a build could not select a usable Summary runtime.
///
/// A code carries no endpoint, token, header, or response data, so it is safe
/// to log and safe to surface in a diagnostic string.
enum SummaryRuntimeFailureCode {
  /// A nonblank `NOTEFLOW_AI_MODE` value other than `remote` was supplied.
  unknownMode,

  /// Remote mode was selected but neither the explicit define nor the generated
  /// Amplify outputs supplied an endpoint value. Unreadable or unexpected
  /// outputs are reported here too: by design they are indistinguishable from
  /// an absent endpoint, so no raw document content can ride along.
  missingEndpoint,

  /// An endpoint value existed but is not an absolute `https` URI with a host
  /// and without userinfo, query, or fragment.
  invalidEndpoint,
}

/// Immutable Summary runtime selection for one app composition.
///
/// Build it once in `main`, from [SummaryRuntimeConfiguration.fromEnvironment],
/// and hand [endpoint] to the remote gateway only when [isRemote] is true.
final class SummaryRuntimeConfiguration {
  /// Selects the runtime from injectable values.
  ///
  /// [mode] accepts blank or `remote`, ignoring surrounding whitespace.
  /// [explicitEndpoint] takes precedence over [amplifyOutputsJson] when
  /// nonblank. An unsupported mode or unusable endpoint leaves Summary
  /// unavailable.
  factory SummaryRuntimeConfiguration({
    String mode = '',
    String? explicitEndpoint,
    String? amplifyOutputsJson,
  }) {
    final String modeToken = mode.trim();
    if (modeToken.isNotEmpty && modeToken != remoteModeToken) {
      return const SummaryRuntimeConfiguration._unavailable(
        SummaryRuntimeFailureCode.unknownMode,
      );
    }

    final String? rawEndpoint =
        _firstNonBlank(explicitEndpoint) ??
        _generatedEndpoint(amplifyOutputsJson);
    if (rawEndpoint == null) {
      return const SummaryRuntimeConfiguration._unavailable(
        SummaryRuntimeFailureCode.missingEndpoint,
      );
    }
    final Uri? endpoint = _validatedEndpoint(rawEndpoint);
    if (endpoint == null) {
      return const SummaryRuntimeConfiguration._unavailable(
        SummaryRuntimeFailureCode.invalidEndpoint,
      );
    }
    return SummaryRuntimeConfiguration._remote(endpoint);
  }

  /// Selects the runtime from the compile-time defines.
  ///
  /// Reads [modeEnvironmentKey] (blank or absent selects remote) and
  /// [endpointEnvironmentKey]. [amplifyOutputsJson] is the generated outputs
  /// document, normally `amplifyConfig` from `lib/amplify_outputs.dart`. This
  /// factory never throws, so it is safe in `main` before any error surface
  /// exists.
  factory SummaryRuntimeConfiguration.fromEnvironment({
    String? amplifyOutputsJson,
  }) {
    return SummaryRuntimeConfiguration(
      mode: const String.fromEnvironment(modeEnvironmentKey),
      explicitEndpoint: const String.fromEnvironment(endpointEnvironmentKey),
      amplifyOutputsJson: amplifyOutputsJson,
    );
  }

  const SummaryRuntimeConfiguration._remote(Uri endpoint)
    : this._(
        mode: SummaryRuntimeMode.remote,
        endpoint: endpoint,
        failureCode: null,
      );

  const SummaryRuntimeConfiguration._unavailable(SummaryRuntimeFailureCode code)
    : this._(
        mode: SummaryRuntimeMode.unavailable,
        endpoint: null,
        failureCode: code,
      );

  const SummaryRuntimeConfiguration._({
    required this.mode,
    required this.endpoint,
    required this.failureCode,
  });

  /// Optional compile-time define naming the remote runtime.
  static const String modeEnvironmentKey = 'NOTEFLOW_AI_MODE';

  /// Compile-time define carrying the explicit remote base URI.
  static const String endpointEnvironmentKey = 'NOTEFLOW_AI_API';

  /// Mode token selecting the remote runtime.
  static const String remoteModeToken = 'remote';

  /// Amplify outputs custom key that carries the generated endpoint.
  static const String generatedEndpointKey = 'aiApiEndpoint';

  /// The selected runtime, or [SummaryRuntimeMode.unavailable] when the build
  /// configuration failed closed.
  final SummaryRuntimeMode mode;

  /// The validated remote base URI, non-null exactly when [isRemote] is true.
  ///
  /// The gateway receives this value. It is deliberately excluded from
  /// [toString] and from every failure, so no diagnostic string can leak a
  /// deployment-specific URL.
  final Uri? endpoint;

  /// Why the selection failed, or null exactly when [canSummarize] is true.
  final SummaryRuntimeFailureCode? failureCode;

  /// Whether this build has a validated cloud endpoint.
  bool get canSummarize => isRemote;

  /// Whether the remote runtime is selected.
  bool get isRemote => mode == SummaryRuntimeMode.remote;

  @override
  String toString() =>
      'SummaryRuntimeConfiguration('
      'mode: ${mode.name}, '
      'canSummarize: $canSummarize, '
      'failureCode: ${failureCode?.name ?? 'none'})';

  /// Returns [value] trimmed, or null when it is null or blank.
  static String? _firstNonBlank(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Reads `<custom.aiApiEndpoint>` from the generated Amplify outputs.
  ///
  /// Only that one key is consulted: a provider credential key is never read
  /// and no other value can stand in for the endpoint. An unreadable document
  /// or an unexpected shape returns null, and the caller reports it as a
  /// missing endpoint.
  static String? _generatedEndpoint(String? amplifyOutputsJson) {
    if (amplifyOutputsJson == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(amplifyOutputsJson);
      if (decoded is! Map) {
        return null;
      }
      final Object? custom = decoded['custom'];
      if (custom is! Map) {
        return null;
      }
      final Object? endpoint = custom[generatedEndpointKey];
      return endpoint is String ? _firstNonBlank(endpoint) : null;
    } on Object {
      // Bootstrap must not fail on a corrupt or hand-edited outputs document.
      return null;
    }
  }

  /// Applies the same transport constraints the gateway enforces, one phase
  /// earlier, so an unusable remote build never reaches composition.
  static Uri? _validatedEndpoint(String rawEndpoint) {
    final Uri? uri = Uri.tryParse(rawEndpoint);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return null;
    }
    return uri;
  }
}
