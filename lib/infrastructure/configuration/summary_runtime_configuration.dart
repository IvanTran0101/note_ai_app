/// Boot-time selection of the Summary runtime (Phase 3.5).
///
/// The app is local-only by default. A build opts into the remote Summary path
/// with `--dart-define=NOTEFLOW_AI_MODE=remote` plus an endpoint, supplied
/// either explicitly as `--dart-define=NOTEFLOW_AI_API=<https base uri>` or,
/// when that define is absent, by the generated Amplify outputs' custom
/// `aiApiEndpoint` key (`amplify/backend.ts`).
///
/// This type is a pure selector: it reads no file, performs no I/O, never
/// throws, and holds no provider credential. Unknown or unusable configuration
/// fails closed to [SummaryRuntimeMode.unavailable] with a safe code - it never
/// silently falls back to local, and the raw endpoint value never appears in a
/// failure or in [SummaryRuntimeConfiguration.toString].
library;

import 'dart:convert';

/// Which Summary runtime one build selected.
enum SummaryRuntimeMode {
  /// On-device summarization. The default, and valid without any endpoint.
  local,

  /// The contract's `/ai/summary` route through the remote service.
  remote,

  /// No usable runtime: the compile-time mode is unknown, or the remote
  /// endpoint is missing or invalid. Summarization stays unavailable until the
  /// build configuration is fixed; this is a fail-closed outcome, not a
  /// fallback to [local].
  unavailable,
}

/// Why a build could not select a usable Summary runtime.
///
/// A code carries no endpoint, token, header, or response data, so it is safe
/// to log and safe to surface in a diagnostic string.
enum SummaryRuntimeFailureCode {
  /// `NOTEFLOW_AI_MODE` is neither `local` nor `remote`.
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
  /// [mode] is the raw mode token; blank or absent means "unconfigured" and
  /// selects [SummaryRuntimeMode.local], the established behavior. The tokens
  /// are the exact lowercase `local` and `remote` (surrounding whitespace is
  /// ignored); anything else fails closed. [explicitEndpoint] is the
  /// `NOTEFLOW_AI_API` value, where blank means absent. [amplifyOutputsJson] is
  /// the generated Amplify outputs document, consulted only when no explicit
  /// endpoint was supplied.
  ///
  /// In local mode any remote endpoint configuration, valid or not, is
  /// ignored. In remote mode an unknown, missing, or invalid endpoint produces
  /// [SummaryRuntimeMode.unavailable]; nothing is thrown.
  factory SummaryRuntimeConfiguration({
    String mode = '',
    String? explicitEndpoint,
    String? amplifyOutputsJson,
  }) {
    final String modeToken = mode.trim();
    if (modeToken.isEmpty || modeToken == localModeToken) {
      return const SummaryRuntimeConfiguration._local();
    }
    if (modeToken != remoteModeToken) {
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
  /// Reads [modeEnvironmentKey] (blank or absent selects local) and
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

  const SummaryRuntimeConfiguration._local()
    : mode = SummaryRuntimeMode.local,
      endpoint = null,
      failureCode = null;

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

  /// Compile-time define naming the runtime; blank or absent means local.
  static const String modeEnvironmentKey = 'NOTEFLOW_AI_MODE';

  /// Compile-time define carrying the explicit remote base URI.
  static const String endpointEnvironmentKey = 'NOTEFLOW_AI_API';

  /// Mode token selecting the on-device runtime.
  static const String localModeToken = 'local';

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

  /// Whether this build may summarize at all.
  ///
  /// Local mode is valid on its own; remote mode is valid only with a validated
  /// endpoint. [SummaryRuntimeMode.unavailable] is never summarizable.
  bool get canSummarize => mode != SummaryRuntimeMode.unavailable;

  /// Whether the on-device runtime is selected.
  bool get isLocal => mode == SummaryRuntimeMode.local;

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
