/// One-time Amplify Auth Cognito configuration for the NoteFlow app.
///
/// The composition root owns the generated Amplify configuration and passes it
/// in as a [String]. Together with the rest of `lib/infrastructure/auth/`, this
/// is the only code that touches Amplify — Domain, Application, and Presentation
/// stay provider-neutral.
library;

import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

/// A terminal Amplify Auth configuration failure that a retry cannot repair.
///
/// The SDK's own [Amplify.isConfigured] flag is not a reliable success signal:
/// after some failed configuration attempts it remains `true` even though this
/// process cannot configure Amplify again. The initializer records its own
/// outcome and throws this typed, message-safe failure on every later call
/// until the app is reloaded with corrected configuration.
final class AmplifyAuthInitializationFailure implements Exception {
  /// Creates a terminal failure around the SDK [cause].
  const AmplifyAuthInitializationFailure({required this.cause});

  /// The SDK error that produced this terminal state.
  ///
  /// Kept for diagnostics; it is never rendered as user-facing copy.
  final Object cause;

  @override
  String toString() =>
      'AmplifyAuthInitializationFailure: Amplify Auth could not be configured '
      'and cannot be reconfigured in this process. Reload the app with '
      'corrected configuration. (${cause.runtimeType})';
}

/// Narrow, testable seam over the Amplify SDK operations the initializer drives.
///
/// [AmplifyAuthInitializer] owns the process-wide state (single flight,
/// whether the plugin was actually added, and whether this attempt reached a
/// terminal configuration failure). The default instance binds these callbacks
/// to [Amplify]; tests bind them to an in-memory fake.
final class AmplifyAuthInitializer {
  /// Creates an initializer over the injected SDK operations.
  factory AmplifyAuthInitializer({
    required bool Function() isConfigured,
    required Future<void> Function() addPlugin,
    required Future<void> Function(String configuration) configure,
  }) {
    return AmplifyAuthInitializer._(isConfigured, addPlugin, configure);
  }

  AmplifyAuthInitializer._(
    this._isConfigured,
    this._addPlugin,
    this._configure,
  );

  final bool Function() _isConfigured;
  final Future<void> Function() _addPlugin;
  final Future<void> Function(String configuration) _configure;

  /// One shared future for every caller while addPlugin/configure is running.
  Future<void>? _inFlight;

  /// Records that our `addPlugin` completed, so a retry never adds it twice.
  bool _pluginAdded = false;

  /// Set only when this process can no longer reach a configured SDK.
  AmplifyAuthInitializationFailure? _terminalFailure;

  /// Registers the Cognito plugin and configures Amplify from [amplifyConfig].
  ///
  /// Concurrent callers share exactly one addPlugin + configure run. After the
  /// run settles the shared future is cleared, so a retriable partial failure
  /// (plugin added, configuration not applied) can be retried without adding
  /// the plugin again.
  ///
  /// A known terminal failure is rethrown on every later call without touching
  /// the SDK: the SDK's misleading [isConfigured] flag must not turn a failed
  /// attempt into success.
  Future<void> initialize({required String amplifyConfig}) {
    final String configuration = amplifyConfig.trim();
    if (configuration.isEmpty) {
      return Future<void>.error(
        ArgumentError.value(
          amplifyConfig,
          'amplifyConfig',
          'must not be blank',
        ),
        StackTrace.current,
      );
    }

    // Check the shared run before the SDK flag: the SDK can flip isConfigured
    // to true between a failed configure and this catch. A concurrent caller
    // must join that failing run instead of observing a false success.
    final Future<void>? pending = _inFlight;
    if (pending != null) {
      return pending;
    }

    final AmplifyAuthInitializationFailure? terminal = _terminalFailure;
    if (terminal != null) {
      return Future<void>.error(terminal, StackTrace.current);
    }
    if (_isConfigured()) {
      return Future<void>.value();
    }

    final Completer<void> completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(_run(configuration, completer));
    return completer.future;
  }

  Future<void> _run(String configuration, Completer<void> completer) async {
    try {
      await _addPluginOnce();
      await _configureOnce(configuration);
      // Contract: never report success while the SDK stayed unconfigured. A
      // configure callback that returns without setting the SDK flag is a
      // failed attempt. Nothing terminal is recorded, so this partial failure
      // remains retriable.
      if (!_isConfigured()) {
        throw StateError(
          'Amplify configure completed without configuring the SDK.',
        );
      }
      completer.complete();
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      // Only this run's completer can be memoized while it is in flight.
      if (identical(_inFlight, completer.future)) {
        _inFlight = null;
      }
    }
  }

  Future<void> _addPluginOnce() async {
    if (_pluginAdded) {
      return;
    }
    try {
      await _addPlugin();
      _pluginAdded = true;
    } on AmplifyAlreadyConfiguredException {
      // Only a genuinely configured SDK makes this refusal equivalent to
      // success. Otherwise it is propagated: there is no configuration to use
      // and this attempt must not report a configured auth shell.
      if (!_isConfigured()) {
        rethrow;
      }
    } on Object catch (error, stackTrace) {
      if (_isConfigured()) {
        _throwTerminal(error, stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _configureOnce(String configuration) async {
    try {
      await _configure(configuration);
    } on AmplifyAlreadyConfiguredException {
      // Same rule as addPlugin: success only when the SDK really reports a
      // configured state; otherwise the refusal is the caller's failure.
      if (!_isConfigured()) {
        rethrow;
      }
    } on ConfigurationError catch (error, stackTrace) {
      // The configuration document is immutable for this process and the SDK
      // completes its config future with the error, so a retry cannot help.
      _throwTerminal(error, stackTrace);
    } on Object catch (error, stackTrace) {
      // Amplify can leave isConfigured == true after a failed attempt. Never
      // retry into an AmplifyAlreadyConfiguredException that would look like
      // success, and never publish an auth shell on a known failed attempt.
      if (_isConfigured()) {
        _throwTerminal(error, stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Never _throwTerminal(Object cause, StackTrace stackTrace) {
    final AmplifyAuthInitializationFailure failure =
        AmplifyAuthInitializationFailure(cause: cause);
    _terminalFailure = failure;
    Error.throwWithStackTrace(failure, stackTrace);
  }
}

/// Process-wide initializer shared by every composition root in this process.
final AmplifyAuthInitializer _amplifyAuthInitializer = AmplifyAuthInitializer(
  isConfigured: () => Amplify.isConfigured,
  addPlugin: () => Amplify.addPlugin(AmplifyAuthCognito()),
  configure: (String configuration) => Amplify.configure(configuration),
);

/// Registers [AmplifyAuthCognito] and configures Amplify from [amplifyConfig].
///
/// [amplifyConfig] is the JSON configuration string produced for the deployed
/// Cognito user pool. It is validated only for being non-blank here: Amplify
/// parses and validates the configuration itself.
///
/// This entry point is safe across repeated app roots and retries: concurrent
/// calls share one SDK configuration run, and a retry after a partial failure
/// reuses the already-registered plugin. A failure that leaves the SDK in a
/// known unrecoverable state is reported as [AmplifyAuthInitializationFailure]
/// so startup can direct the user to reload with corrected configuration.
Future<void> configureAmplifyAuthCognito({required String amplifyConfig}) {
  return _amplifyAuthInitializer.initialize(amplifyConfig: amplifyConfig);
}
