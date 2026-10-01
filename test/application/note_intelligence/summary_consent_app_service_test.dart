import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';

AuthIdentity _identity(String userId) {
  return AuthIdentity(
    userId: userId,
    email: '$userId@example.com',
    isEmailVerified: true,
  );
}

/// Runs [action] and returns the code of the [SummaryRunFailure] it threw.
SummaryRunFailureCode _failureCode(void Function() action) {
  try {
    action();
  } on SummaryRunFailure catch (failure) {
    return failure.code;
  }
  throw StateError('expected a SummaryRunFailure');
}

/// Real session and consent store wired exactly like the composition root.
final class _Harness {
  _Harness() {
    consent = SummaryCloudConsent(session: session);
    service = _build();
  }

  final CurrentUserSession session = CurrentUserSession();
  late final SummaryCloudConsent consent;
  late SummaryConsentAppService service;
  bool available = true;
  int cancelCalls = 0;
  void Function()? onCancel;

  SummaryConsentAppService _build() {
    return SummaryConsentAppService(
      currentUser: session,
      session: session,
      consent: consent,
      isAvailable: () => available,
      cancelActiveRuns: () {
        cancelCalls++;
        onCancel?.call();
      },
    );
  }

  /// Rebuilds the service over the same session and store.
  SummaryConsentAppService recreate() => service = _build();

  void signIn(String userId) => session.setIdentity(_identity(userId));

  void signOut() => session.clear();

  SummaryCloudConsentSnapshot captureFor(String userId) {
    return consent.capture(
      accountUserId: userId,
      sessionGeneration: session.sessionGeneration,
    );
  }
}

void main() {
  group('SummaryConsentAppService state', () {
    test('a fresh store and service start consentRequired', () {
      final _Harness h = _Harness()..signIn('user-a');

      expect(h.service.state, SummaryConsentStatus.consentRequired);
      expect(h.consent.generation, 0);
      expect(h.captureFor('user-a').isGranted, isFalse);
    });

    test('a granted confirmation reports granted', () {
      final _Harness h = _Harness()..signIn('user-a');

      h.service.grantConsent(h.service.beginConsent());

      expect(h.service.state, SummaryConsentStatus.granted);
      expect(h.consent.isCurrent(h.captureFor('user-a')), isTrue);
    });

    test(
      'an unavailable runtime or a signed-out session reports unavailable',
      () {
        final _Harness h = _Harness()..signIn('user-a');
        h.available = false;

        expect(h.service.state, SummaryConsentStatus.unavailable);

        final _Harness signedOut = _Harness();

        expect(signedOut.session.isAuthenticated, isFalse);
        expect(signedOut.service.state, SummaryConsentStatus.unavailable);
      },
    );
  });

  group('SummaryConsentAppService beginConsent', () {
    test('refuses an unavailable runtime or an unauthenticated session', () {
      final _Harness h = _Harness()..signIn('user-a');
      h.available = false;

      expect(
        _failureCode(h.service.beginConsent),
        SummaryRunFailureCode.runtimeUnavailable,
      );

      h.available = true;
      h.signOut();

      expect(
        _failureCode(h.service.beginConsent),
        SummaryRunFailureCode.sessionChanged,
      );
      expect(h.consent.generation, 0);
    });

    test('captures the live account, session, and consent generation', () {
      final _Harness h = _Harness()..signIn('user-a');
      h.consent.grant(accountUserId: 'user-b', sessionGeneration: 9);

      final SummaryConsentRequest request = h.service.beginConsent();

      expect(request.accountUserId, 'user-a');
      expect(request.sessionGeneration, h.session.sessionGeneration);
      expect(request.consentGeneration, h.consent.generation);
      expect(request.toString(), isNot(contains('user-a')));
    });
  });

  group('SummaryConsentAppService grantConsent', () {
    test('grants the captured account and session exactly', () {
      final _Harness h = _Harness()..signIn('user-a');
      final int generation = h.consent.generation;
      final SummaryConsentRequest request = h.service.beginConsent();

      h.service.grantConsent(request);

      expect(h.consent.generation, generation + 1);
      final SummaryCloudConsentSnapshot snapshot = h.captureFor('user-a');
      expect(snapshot.isGranted, isTrue);
      expect(snapshot.sessionGeneration, request.sessionGeneration);
      expect(snapshot.consentGeneration, request.consentGeneration + 1);
    });

    test('never grants the live account when it is not the captured one', () {
      final _Harness h = _Harness()..signIn('user-a');
      final SummaryConsentRequest request = h.service.beginConsent();

      h.signIn('user-b');

      expect(
        _failureCode(() => h.service.grantConsent(request)),
        SummaryRunFailureCode.sessionChanged,
      );
      expect(h.captureFor('user-b').isGranted, isFalse);
      expect(h.consent.generation, request.consentGeneration);
    });

    test('rejects an account round trip A to B to A without mutating', () {
      final _Harness h = _Harness()..signIn('user-a');
      final SummaryConsentRequest request = h.service.beginConsent();

      h.signIn('user-b');
      expect(
        _failureCode(() => h.service.grantConsent(request)),
        SummaryRunFailureCode.sessionChanged,
      );
      h.signIn('user-a');

      expect(
        _failureCode(() => h.service.grantConsent(request)),
        SummaryRunFailureCode.sessionChanged,
      );
      expect(h.consent.generation, request.consentGeneration);
      expect(h.captureFor('user-a').isGranted, isFalse);
      expect(h.service.state, SummaryConsentStatus.consentRequired);
    });

    test(
      'rejects sign-out and sign-in as the same account without mutating',
      () {
        final _Harness h = _Harness()..signIn('user-a');
        final SummaryConsentRequest request = h.service.beginConsent();

        h.signOut();
        h.signIn('user-a');

        expect(
          _failureCode(() => h.service.grantConsent(request)),
          SummaryRunFailureCode.sessionChanged,
        );
        expect(h.consent.generation, request.consentGeneration);
        expect(h.captureFor('user-a').isGranted, isFalse);
      },
    );

    test('rejects a confirmation when the runtime went away', () {
      final _Harness h = _Harness()..signIn('user-a');
      final SummaryConsentRequest request = h.service.beginConsent();

      h.available = false;

      expect(
        _failureCode(() => h.service.grantConsent(request)),
        SummaryRunFailureCode.runtimeUnavailable,
      );
      expect(h.consent.generation, request.consentGeneration);
      expect(h.captureFor('user-a').isGranted, isFalse);
      expect(h.service.state, SummaryConsentStatus.unavailable);
    });

    test('a confirmation that already granted cannot grant again', () {
      final _Harness h = _Harness()..signIn('user-a');
      final SummaryConsentRequest request = h.service.beginConsent();
      h.service.grantConsent(request);
      final int grantedGeneration = h.consent.generation;

      expect(
        _failureCode(() => h.service.grantConsent(request)),
        SummaryRunFailureCode.consentRequired,
      );
      expect(h.consent.generation, grantedGeneration);
      expect(h.consent.isCurrent(h.captureFor('user-a')), isTrue);
    });

    test(
      'a second outstanding confirmation is stale after the first grants',
      () {
        final _Harness h = _Harness()..signIn('user-a');
        final SummaryConsentRequest first = h.service.beginConsent();
        final SummaryConsentRequest second = h.service.beginConsent();

        h.service.grantConsent(first);

        expect(
          _failureCode(() => h.service.grantConsent(second)),
          SummaryRunFailureCode.consentRequired,
        );
      },
    );

    test('a recreated service cannot grant the old service request', () {
      final _Harness h = _Harness()..signIn('user-a');
      final SummaryConsentRequest request = h.service.beginConsent();

      final SummaryConsentAppService recreated = h.recreate();

      expect(recreated.state, SummaryConsentStatus.consentRequired);
      expect(
        _failureCode(() => recreated.grantConsent(request)),
        SummaryRunFailureCode.consentRequired,
      );
      expect(h.consent.generation, request.consentGeneration);
      expect(h.captureFor('user-a').isGranted, isFalse);
    });
  });

  group('SummaryConsentAppService revokeConsent', () {
    test('clears the store before cancelling active runs', () {
      final _Harness h = _Harness()..signIn('user-a');
      h.service.grantConsent(h.service.beginConsent());
      final List<SummaryCloudConsentSnapshot> cancelledWith =
          <SummaryCloudConsentSnapshot>[];
      h.onCancel = () => cancelledWith.add(h.captureFor('user-a'));

      h.service.revokeConsent();

      expect(h.cancelCalls, 1);
      expect(cancelledWith.single.isGranted, isFalse);
      expect(h.service.state, SummaryConsentStatus.consentRequired);
    });

    test('cancels an active run as consentRequired', () {
      final _Harness h = _Harness()..signIn('user-a');
      h.service.grantConsent(h.service.beginConsent());
      final SummaryRunScope scope = SummaryRunScope();
      h.onCancel = () =>
          scope.cancel(reason: SummaryRunFailureCode.consentRequired);

      h.service.revokeConsent();

      expect(scope.isCancelled, isTrue);
      expect(scope.cancelReason, SummaryRunFailureCode.consentRequired);
    });

    test(
      'a regrant never revives the grant or intent from before the revoke',
      () {
        final _Harness h = _Harness()..signIn('user-a');
        final SummaryConsentRequest first = h.service.beginConsent();
        h.service.grantConsent(first);
        final SummaryCloudConsentSnapshot granted = h.captureFor('user-a');
        expect(h.consent.isCurrent(granted), isTrue);

        h.service.revokeConsent();
        expect(h.service.state, SummaryConsentStatus.consentRequired);
        expect(h.consent.isCurrent(granted), isFalse);

        final SummaryConsentRequest second = h.service.beginConsent();
        expect(
          _failureCode(() => h.service.grantConsent(first)),
          SummaryRunFailureCode.consentRequired,
        );

        h.service.grantConsent(second);

        expect(h.service.state, SummaryConsentStatus.granted);
        expect(h.consent.isCurrent(granted), isFalse);
        expect(h.consent.isCurrent(h.captureFor('user-a')), isTrue);
      },
    );
  });
}
