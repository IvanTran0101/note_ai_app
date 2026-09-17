/// One-time Amplify Auth Cognito configuration for the NoteFlow app.
///
/// The composition root owns the generated Amplify configuration and passes it
/// in as a [String]. Together with the rest of `lib/infrastructure/auth/`, this
/// is the only code that touches Amplify — Domain, Application, and Presentation
/// stay provider-neutral.
library;

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

/// Registers [AmplifyAuthCognito] and configures Amplify from [amplifyConfig].
///
/// [amplifyConfig] is the JSON configuration string produced for the deployed
/// Cognito user pool. It is validated only for being non-blank here: Amplify
/// parses and validates the configuration itself.
///
/// Calling this again after Amplify is configured is a no-op, so a second
/// composition pass or a hot reload does not fail. The failure of the call that
/// actually attempted configuration is never swallowed: it reaches that caller
/// unchanged, and Amplify itself refuses any later re-configuration.
Future<void> configureAmplifyAuthCognito({
  required String amplifyConfig,
}) async {
  final String configuration = amplifyConfig.trim();
  if (configuration.isEmpty) {
    throw ArgumentError.value(
      amplifyConfig,
      'amplifyConfig',
      'must not be blank',
    );
  }
  if (Amplify.isConfigured) {
    return;
  }

  try {
    await Amplify.addPlugin(AmplifyAuthCognito());
  } on AmplifyAlreadyConfiguredException {
    // A concurrent caller configured Amplify between the check above and this
    // call. The plugin and the configuration are already in place, so there is
    // nothing left for this call to do.
    return;
  }

  try {
    await Amplify.configure(configuration);
  } on AmplifyAlreadyConfiguredException {
    // Same race, now on the configuration itself. Nothing is swallowed here:
    // every other configuration error still propagates to the caller.
    return;
  }
}
