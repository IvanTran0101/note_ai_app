import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';

void main() {
  test('classifies retryable and permanent failures', () {
    expect(const SyncFailure(code: SyncErrorCode.timeout).retryable, isTrue);
    expect(
      const SyncFailure(code: SyncErrorCode.unauthorized).retryable,
      isFalse,
    );
  });
}
