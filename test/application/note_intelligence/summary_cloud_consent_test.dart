import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';

/// Not-granted snapshot for [accountUserId] at [sessionGeneration].
SummaryCloudConsentSnapshot _notGranted(
  String accountUserId,
  int sessionGeneration,
) {
  return SummaryCloudConsentSnapshot.notGranted(
    accountUserId: accountUserId,
    sessionGeneration: sessionGeneration,
  );
}

final class _FakeSessionGeneration implements SessionGenerationSource {
  _FakeSessionGeneration(this.sessionGeneration);

  @override
  int sessionGeneration;
}

void main() {
  group('SummaryCloudConsentSnapshot', () {
    test('notGranted carries the binding and no grant generation', () {
      final SummaryCloudConsentSnapshot snapshot = _notGranted('user-1', 4);

      expect(snapshot.accountUserId, 'user-1');
      expect(snapshot.sessionGeneration, 4);
      expect(snapshot.isGranted, isFalse);
      expect(snapshot.consentGeneration, 0);
      expect(snapshot, _notGranted('user-1', 4));
      expect(snapshot.hashCode, _notGranted('user-1', 4).hashCode);
    });

    test('compares by every bound fact', () {
      final SummaryCloudConsentSnapshot snapshot = _notGranted('user-1', 4);

      expect(snapshot, isNot(_notGranted('user-2', 4)));
      expect(snapshot, isNot(_notGranted('user-1', 5)));
    });
  });

  group('SummaryCloudConsent default off', () {
    test('starts with generation 0 and grants nothing', () {
      final SummaryCloudConsent consent = SummaryCloudConsent();

      expect(consent.generation, 0);
      final SummaryCloudConsentSnapshot snapshot = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 1,
      );

      expect(snapshot.isGranted, isFalse);
      expect(snapshot.consentGeneration, 0);
      expect(consent.isCurrent(snapshot), isFalse);
    });

    test('a not-granted snapshot is never current', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 1);

      expect(consent.isCurrent(_notGranted('user-1', 1)), isFalse);
    });
  });

  group('SummaryCloudConsent grant', () {
    test('binds the exact account and session generation', () {
      final SummaryCloudConsent consent = SummaryCloudConsent();

      consent.grant(accountUserId: 'user-1', sessionGeneration: 3);

      expect(consent.generation, 1);
      final SummaryCloudConsentSnapshot snapshot = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );

      expect(snapshot.isGranted, isTrue);
      expect(snapshot.consentGeneration, 1);
      expect(consent.isCurrent(snapshot), isTrue);
    });

    test('does not leak into another account', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);

      final SummaryCloudConsentSnapshot other = consent.capture(
        accountUserId: 'user-2',
        sessionGeneration: 3,
      );

      expect(other.isGranted, isFalse);
      expect(consent.isCurrent(other), isFalse);
      expect(
        consent
            .capture(accountUserId: 'user-1', sessionGeneration: 3)
            .isGranted,
        isTrue,
      );
    });

    test('does not leak into another session generation', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);

      final SummaryCloudConsentSnapshot later = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 4,
      );

      expect(later.isGranted, isFalse);
      expect(consent.isCurrent(later), isFalse);
    });

    test('an account switch invalidates a snapshot captured before it', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot beforeSwitch = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );
      expect(consent.isCurrent(beforeSwitch), isTrue);

      // Session 4 is the switched-away generation, session 5 is the new one.
      consent.capture(accountUserId: 'user-2', sessionGeneration: 4);
      final SummaryCloudConsentSnapshot afterSwitch = consent.capture(
        accountUserId: 'user-2',
        sessionGeneration: 5,
      );

      expect(afterSwitch.isGranted, isFalse);
      expect(consent.isCurrent(beforeSwitch), isFalse);
    });
  });

  group('SummaryCloudConsent revoke', () {
    test('clears the grant and invalidates its snapshots', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot granted = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );

      consent.revoke();

      expect(consent.isCurrent(granted), isFalse);
      expect(
        consent
            .capture(accountUserId: 'user-1', sessionGeneration: 3)
            .isGranted,
        isFalse,
      );
    });

    test('a targeted revoke leaves other accounts granted', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3)
        ..grant(accountUserId: 'user-2', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot first = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );

      consent.revoke(accountUserId: 'user-2');

      expect(consent.isCurrent(first), isTrue);
      expect(
        consent
            .capture(accountUserId: 'user-2', sessionGeneration: 3)
            .isGranted,
        isFalse,
      );
    });

    test('an untargeted revoke clears every account', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3)
        ..grant(accountUserId: 'user-2', sessionGeneration: 3);

      consent.revoke();

      expect(
        consent
            .capture(accountUserId: 'user-1', sessionGeneration: 3)
            .isGranted,
        isFalse,
      );
      expect(
        consent
            .capture(accountUserId: 'user-2', sessionGeneration: 3)
            .isGranted,
        isFalse,
      );
    });

    test('grant and revoke advance the generation monotonically', () {
      final SummaryCloudConsent consent = SummaryCloudConsent();

      consent.grant(accountUserId: 'user-1', sessionGeneration: 1);
      expect(consent.generation, 1);
      consent.grant(accountUserId: 'user-1', sessionGeneration: 1);
      expect(consent.generation, 2);
      consent.revoke(accountUserId: 'user-1');
      expect(consent.generation, 3);
      consent.revoke();
      expect(consent.generation, 4);
    });
  });

  group('SummaryCloudConsent regrant', () {
    test('never revives a snapshot from before the revoke', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot beforeRevoke = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );

      consent.revoke(accountUserId: 'user-1');
      consent.grant(accountUserId: 'user-1', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot afterRegrant = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );

      expect(afterRegrant.isGranted, isTrue);
      expect(consent.isCurrent(afterRegrant), isTrue);
      expect(consent.isCurrent(beforeRevoke), isFalse);
      expect(
        afterRegrant.consentGeneration,
        isNot(beforeRevoke.consentGeneration),
      );
    });

    test('a second grant retires the first snapshot for the same binding', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot first = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );

      consent.grant(accountUserId: 'user-1', sessionGeneration: 3);

      expect(consent.isCurrent(first), isFalse);
      expect(
        consent.isCurrent(
          consent.capture(accountUserId: 'user-1', sessionGeneration: 3),
        ),
        isTrue,
      );
    });
  });

  group('SummaryCloudConsent with a live session', () {
    test('a stale snapshot stops being current once the session advances', () {
      final _FakeSessionGeneration session = _FakeSessionGeneration(3);
      final SummaryCloudConsent consent = SummaryCloudConsent(session: session)
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot snapshot = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );
      expect(consent.isCurrent(snapshot), isTrue);

      session.sessionGeneration = 4;

      expect(consent.isCurrent(snapshot), isFalse);
    });

    test('capture refuses a binding that is not the live session', () {
      final _FakeSessionGeneration session = _FakeSessionGeneration(5);
      final SummaryCloudConsent consent = SummaryCloudConsent(session: session)
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);

      final SummaryCloudConsentSnapshot stale = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );

      expect(stale.isGranted, isFalse);
      expect(consent.isCurrent(stale), isFalse);
      expect(
        consent
            .capture(accountUserId: 'user-1', sessionGeneration: 5)
            .isGranted,
        isFalse,
      );
    });

    test('a grant for the live session is current', () {
      final _FakeSessionGeneration session = _FakeSessionGeneration(7);
      final SummaryCloudConsent consent = SummaryCloudConsent(session: session)
        ..grant(accountUserId: 'user-1', sessionGeneration: 7);

      final SummaryCloudConsentSnapshot snapshot = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 7,
      );

      expect(snapshot.isGranted, isTrue);
      expect(consent.isCurrent(snapshot), isTrue);
    });
  });

  group('SummaryCloudConsent without a live session', () {
    test('a newer observed generation invalidates an older snapshot', () {
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-1', sessionGeneration: 3);
      final SummaryCloudConsentSnapshot snapshot = consent.capture(
        accountUserId: 'user-1',
        sessionGeneration: 3,
      );
      expect(consent.isCurrent(snapshot), isTrue);

      consent.capture(accountUserId: 'user-2', sessionGeneration: 9);

      expect(consent.isCurrent(snapshot), isFalse);
    });
  });
}
