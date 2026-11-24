import 'dart:async';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/auth/amplify_auth_initializer.dart';

void main() {
  test(
    'simultaneous initialize calls share one plugin add and configure',
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..addPluginGate = Completer<void>();
      final AmplifyAuthInitializer initializer = sdk.initializer();

      final Future<void> first = initializer.initialize(amplifyConfig: ' {} ');
      final Future<void> second = initializer.initialize(amplifyConfig: '{}');
      expect(sdk.addPluginCalls, 1);

      sdk.addPluginGate!.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 1);
      expect(sdk.configurations, <String>['{}']);
      expect(sdk.configured, isTrue);
    },
  );

  test(
    'a retriable configure failure retries without re-adding the plugin',
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..configureError = Exception('plugin configuration failed');
      final AmplifyAuthInitializer initializer = sdk.initializer();

      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(isA<Exception>()),
      );
      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 1);
      expect(sdk.configured, isFalse);

      sdk.configureError = null;
      await initializer.initialize(amplifyConfig: '{}');

      expect(sdk.addPluginCalls, 1, reason: 'the plugin was already added');
      expect(sdk.configureCalls, 2);
      expect(sdk.configured, isTrue);
    },
  );

  test(
    'AmplifyAlreadyConfigured is not success while the SDK is unconfigured',
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..configureError = const AmplifyAlreadyConfiguredException(
          'already configured',
        );
      final AmplifyAuthInitializer initializer = sdk.initializer();

      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(isA<AmplifyAlreadyConfiguredException>()),
      );
      expect(sdk.configured, isFalse);

      sdk.configureError = null;
      await initializer.initialize(amplifyConfig: '{}');
      expect(sdk.configureCalls, 2);
      expect(sdk.configured, isTrue);
    },
  );

  test("an unrelated error containing 'already' still propagates", () async {
    final _FakeAmplifySdk sdk = _FakeAmplifySdk()
      ..configureError = Exception('resource already exists');
    final AmplifyAuthInitializer initializer = sdk.initializer();

    await expectLater(
      initializer.initialize(amplifyConfig: '{}'),
      throwsA(
        isA<Exception>().having(
          (Exception error) => error.toString(),
          'message',
          contains('already'),
        ),
      ),
    );
    expect(sdk.configured, isFalse);
    expect(sdk.configureCalls, 1);

    sdk.configureError = null;
    await initializer.initialize(amplifyConfig: '{}');
    expect(sdk.addPluginCalls, 1);
    expect(sdk.configureCalls, 2);
  });

  test(
    'a failed configure that flips isConfigured true stays a visible failure',
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..markConfiguredBeforeConfigureError = true
        ..configureError = Exception('configuration failed');
      final AmplifyAuthInitializer initializer = sdk.initializer();

      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(isA<AmplifyAuthInitializationFailure>()),
      );
      expect(sdk.configured, isTrue, reason: 'the SDK flag is misleading');
      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 1);

      // A later call must not turn the misleading SDK flag into auth success,
      // and must not call the SDK again.
      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(isA<AmplifyAuthInitializationFailure>()),
      );
      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 1);
    },
  );

  test(
    'a configure that returns without configuring the SDK fails the future',
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..configureWithoutMarkingConfigured = true;
      final AmplifyAuthInitializer initializer = sdk.initializer();

      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(isA<StateError>()),
      );
      expect(sdk.configured, isFalse, reason: 'no false configured shell');
      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 1);

      // The failed attempt recorded nothing terminal, so a later configure
      // that does set the flag succeeds without re-adding the plugin.
      sdk.configureWithoutMarkingConfigured = false;
      await initializer.initialize(amplifyConfig: '{}');

      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 2);
      expect(sdk.configured, isTrue);
    },
  );

  test(
    "an unrelated plugin error containing 'already' aborts before configure",
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..addPluginError = AmplifyException.fromMap(<String, String>{
          'message': 'the plugin resource already exists',
        });
      final AmplifyAuthInitializer initializer = sdk.initializer();

      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(
          isA<AmplifyException>().having(
            (AmplifyException error) => error.message,
            'message',
            contains('already'),
          ),
        ),
      );
      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 0, reason: 'no silent fallthrough');
      expect(sdk.configured, isFalse);
    },
  );

  test(
    'an already-configured plugin refusal with an unconfigured SDK fails',
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..addPluginError = const AmplifyAlreadyConfiguredException(
          'already configured',
        );
      final AmplifyAuthInitializer initializer = sdk.initializer();

      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(isA<AmplifyAlreadyConfiguredException>()),
      );
      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 0);
      expect(sdk.configured, isFalse);
    },
  );

  test(
    'a retriable plugin failure is retried and can then configure',
    () async {
      final _FakeAmplifySdk sdk = _FakeAmplifySdk()
        ..addPluginError = Exception('plugin registration failed');
      final AmplifyAuthInitializer initializer = sdk.initializer();

      await expectLater(
        initializer.initialize(amplifyConfig: '{}'),
        throwsA(isA<Exception>()),
      );
      expect(sdk.addPluginCalls, 1);
      expect(sdk.configureCalls, 0);
      expect(sdk.configured, isFalse);

      sdk.addPluginError = null;
      await initializer.initialize(amplifyConfig: '{}');

      expect(sdk.addPluginCalls, 2, reason: 'the plugin was never added');
      expect(sdk.configureCalls, 1);
      expect(sdk.configured, isTrue);
    },
  );

  test('an already-configured SDK is an idempotent no-op', () async {
    final _FakeAmplifySdk sdk = _FakeAmplifySdk()..configured = true;
    final AmplifyAuthInitializer initializer = sdk.initializer();

    await initializer.initialize(amplifyConfig: '{}');

    expect(sdk.addPluginCalls, 0);
    expect(sdk.configureCalls, 0);
  });

  test('a blank configuration is rejected before touching the SDK', () async {
    final _FakeAmplifySdk sdk = _FakeAmplifySdk();
    final AmplifyAuthInitializer initializer = sdk.initializer();

    await expectLater(
      initializer.initialize(amplifyConfig: '   '),
      throwsA(isA<ArgumentError>()),
    );

    expect(sdk.addPluginCalls, 0);
    expect(sdk.configureCalls, 0);
  });
}

final class _FakeAmplifySdk {
  bool configured = false;
  bool markConfiguredBeforeConfigureError = false;
  bool configureWithoutMarkingConfigured = false;
  int addPluginCalls = 0;
  int configureCalls = 0;
  final List<String> configurations = <String>[];

  Object? addPluginError;
  Object? configureError;
  Completer<void>? addPluginGate;

  AmplifyAuthInitializer initializer() {
    return AmplifyAuthInitializer(
      isConfigured: () => configured,
      addPlugin: _addPlugin,
      configure: _configure,
    );
  }

  Future<void> _addPlugin() async {
    addPluginCalls++;
    await addPluginGate?.future;
    final Object? error = addPluginError;
    if (error != null) {
      throw error;
    }
  }

  Future<void> _configure(String configuration) async {
    configureCalls++;
    configurations.add(configuration);
    await configureGate?.future;
    final Object? error = configureError;
    if (error != null) {
      if (markConfiguredBeforeConfigureError) {
        configured = true;
      }
      throw error;
    }
    if (!configureWithoutMarkingConfigured) {
      configured = true;
    }
  }

  Completer<void>? configureGate;
}
