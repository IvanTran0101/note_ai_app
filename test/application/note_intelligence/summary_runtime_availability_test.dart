import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';

void main() {
  late CurrentUserSession session;
  late SummaryCloudConsent store;
  setUp(() {
    session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: 'account-a',
          email: 'a@example.test',
          isEmailVerified: true,
        ),
      );
    store = SummaryCloudConsent(session: session);
  });
  SummaryConsentAppService service({
    bool cloud = true,
    bool available = true,
  }) => SummaryConsentAppService(
    currentUser: session,
    session: session,
    consent: store,
    requiresCloudConsent: cloud,
    isAvailable: () => available,
    cancelActiveRuns: () {},
  );

  test('native local mode needs no consent but is available', () {
    final app = service(cloud: false);
    expect(app.requiresCloudConsent, isFalse);
    expect(app.unavailableReason, isNull);
    expect(app.state, SummaryConsentStatus.unavailable);
    expect(
      app.beginConsent,
      throwsA(
        const SummaryRunFailure(SummaryRunFailureCode.runtimeUnavailable),
      ),
    );
    expect(store.generation, 0);
  });
  test('unsupported local runtime is blocked before generation', () {
    expect(
      service(cloud: false, available: false).unavailableReason,
      SummaryRunFailureCode.runtimeUnavailable,
    );
  });
  test('remote invalid configuration has a safe runtime reason', () {
    expect(
      service(available: false).unavailableReason,
      SummaryRunFailureCode.runtimeUnavailable,
    );
  });
  test('available remote runtime requires a current account', () {
    session.clear();
    final app = service();
    expect(app.requiresCloudConsent, isTrue);
    expect(app.unavailableReason, SummaryRunFailureCode.unauthorized);
    expect(app.state, SummaryConsentStatus.unavailable);
  });
}
