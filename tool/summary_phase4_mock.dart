/// Offline Phase 4.5 Summary smoke tool: the real production root app over a
/// local mock transport. No provider, network, credential, or asset override is
/// used, and `main()` (and its Cognito bootstrap) is bypassed entirely.
///
/// Run it (Web):
///
/// ```
/// flutter run -d chrome \
///   --dart-define=NOTEFLOW_SYNC_API=summary-mock-disabled \
///   -t tool/summary_phase4_mock.dart
/// ```
///
/// Run it (native, to exercise the shared local latch):
///
/// ```
/// flutter run -d macos \
///   --dart-define=NOTEFLOW_SYNC_API=summary-mock-disabled \
///   --dart-define=NOTEFLOW_MOCK_LOCAL_SUMMARY=true \
///   -t tool/summary_phase4_mock.dart
/// ```
///
/// Compile-time API:
///
/// * Background sync is disabled in this fixture root, independently of
///   compile-time endpoint values. The shown invalid endpoint is optional.
/// * `NOTEFLOW_MOCK_LOCAL_SUMMARY` (`true`) selects the on-device runtime with
///   an injected delayed summarizer instead of the mocked remote one.
/// * `NOTEFLOW_MOCK_OVERLAY` (`false`) hides the test-only overlay.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/main.dart';

import 'package:note_ai_app/dev/summary_phase4_mock_support.dart';

/// Global switch selecting the on-device runtime for the native latch smoke.
const bool _localMode = bool.fromEnvironment('NOTEFLOW_MOCK_LOCAL_SUMMARY');

/// Whether the test-only overlay is shown; it is never part of production UI.
const bool _showOverlay = bool.fromEnvironment(
  'NOTEFLOW_MOCK_OVERLAY',
  defaultValue: true,
);

/// Held for the whole browser session: a disposed handle disables semantics,
/// which is what the browser automation of this tool relies on.
SemanticsHandle? _semanticsHandle;

void main() {
  final WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };
  // Browser automation needs an explicit semantics tree.
  binding.addPostFrameCallback((_) {
    _semanticsHandle = binding.ensureSemantics();
  });
  debugPrint(
    'NoteFlow Phase 4.5 mock tool: semantics=${_semanticsHandle != null}, '
    'localMode=$_localMode, define=$summaryMockSyncApiDefine',
  );

  final SummaryMockEnvironment environment = createSummaryMockEnvironment(
    localRuntime: _localMode,
  );
  final ValueNotifier<int> localCalls = ValueNotifier<int>(0);
  runApp(
    _MockHarness(
      environment: environment,
      localCalls: localCalls,
      localSummarizer: _localMode
          ? (String content) => _summarizeLocally(localCalls, content)
          : null,
    ),
  );
}

/// The injected on-device callback: slow enough to cancel mid-run.
Future<Summary> _summarizeLocally(
  ValueNotifier<int> localCalls,
  String content,
) async {
  final int call = localCalls.value + 1;
  localCalls.value = call;
  await Future<void>.delayed(const Duration(seconds: 4));
  return Summary('MOCK LOCAL SUMMARY #$call (${content.length} chars)');
}

/// Renders the production root app and optionally the test-only overlay.
final class _MockHarness extends StatelessWidget {
  const _MockHarness({
    required this.environment,
    required this.localCalls,
    required this.localSummarizer,
  });

  final SummaryMockEnvironment environment;
  final ValueNotifier<int> localCalls;
  final SummarizeNoteContent? localSummarizer;

  @override
  Widget build(BuildContext context) {
    // App and test controls need one directionality and keyboard order.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.topLeft,
          children: <Widget>[
            NoteFlowApp(
              authController: environment.authController,
              currentUserSession: environment.session,
              summaryRuntime: environment.runtime,
              localSyncStoreFactory: environment.storeFor,
              localSummarizer: localSummarizer,
              enableSync: false,
            ),
            if (_showOverlay)
              _MockOverlay(
                environment: environment,
                localCalls: localCalls,
                localMode: _localMode,
              ),
          ],
        ),
      ),
    );
  }
}

/// Test-only control panel: request counter, policy source, and mode switches.
///
/// It is deliberately outside the production widget tree and never part of a
/// shipped build.
final class _MockOverlay extends StatelessWidget {
  const _MockOverlay({
    required this.environment,
    required this.localCalls,
    required this.localMode,
  });

  final SummaryMockEnvironment environment;
  final ValueNotifier<int> localCalls;
  final bool localMode;

  @override
  Widget build(BuildContext context) {
    final SummaryMockControl control = environment.control;
    // The overlay sits outside the app's own MaterialApp, so it brings the
    // inherited widgets it needs instead of borrowing the production ones.
    return MediaQuery.fromView(
      view: View.of(context),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _mockCounters(control),
                      if (!localMode) ...<Widget>[
                        const SizedBox(height: 6),
                        _MockModes(control: control),
                      ],
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () {
                          control.reset();
                          localCalls.value = 0;
                        },
                        child: const Text('Reset counters'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mockCounters(SummaryMockControl control) {
    return ValueListenableBuilder<int>(
      valueListenable: control.requestCount,
      builder: (BuildContext context, int count, Widget? child) {
        return ValueListenableBuilder<bool>(
          valueListenable: control.policyLoaded,
          builder: (BuildContext context, bool loaded, Widget? inner) {
            return ValueListenableBuilder<String>(
              valueListenable: control.policySource,
              builder: (BuildContext context, String source, Widget? inner) {
                return ValueListenableBuilder<int>(
                  valueListenable: localCalls,
                  builder: (BuildContext context, int local, Widget? inner) {
                    return Text(
                      'Mock HTTP: $count\n'
                      'Policy: $source${loaded ? ' (loaded)' : ''}\n'
                      'Local calls: $local',
                      style: const TextStyle(fontSize: 11, height: 1.4),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// One button per [SummaryMockMode], highlighting the live one.
final class _MockModes extends StatelessWidget {
  const _MockModes({required this.control});

  final SummaryMockControl control;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SummaryMockMode>(
      valueListenable: control.mode,
      builder: (BuildContext context, SummaryMockMode mode, Widget? child) {
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final SummaryMockMode candidate in SummaryMockMode.values)
              TextButton(
                onPressed: () => control.mode.value = candidate,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: mode == candidate
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                child: Text(candidate.label),
              ),
          ],
        );
      },
    );
  }
}
