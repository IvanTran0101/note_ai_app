import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_report.dart';

void main() {
  test('defaults to a no-op run without a cursor', () {
    final SyncReport report = SyncReport();

    expect(report.applied, 0);
    expect(report.pulled, 0);
    expect(report.conflicts, 0);
    expect(report.cursor, isNull);
    expect(report.isNoop, isTrue);
    expect(SyncReport(applied: 1).isNoop, isFalse);
    expect(SyncReport(conflicts: 1).isNoop, isFalse);
  });

  test('rejects negative counts', () {
    expect(() => SyncReport(applied: -1), throwsArgumentError);
    expect(() => SyncReport(pulled: -1), throwsArgumentError);
    expect(() => SyncReport(conflicts: -1), throwsArgumentError);
  });

  test('carries the resulting cursor opaquely', () {
    final SyncReport report = SyncReport(
      applied: 2,
      pulled: 3,
      conflicts: 1,
      cursor: const SyncCursor('  next:abc  '),
    );

    expect(report.cursor?.value, '  next:abc  ');
    expect(report.applied, 2);
    expect(report.pulled, 3);
    expect(report.conflicts, 1);
    expect(
      report,
      SyncReport(
        applied: 2,
        pulled: 3,
        conflicts: 1,
        cursor: const SyncCursor('  next:abc  '),
      ),
    );
    expect(
      report.hashCode,
      SyncReport(
        applied: 2,
        pulled: 3,
        conflicts: 1,
        cursor: const SyncCursor('  next:abc  '),
      ).hashCode,
    );
    expect(report, isNot(SyncReport(applied: 2, pulled: 3)));
    expect(report, isNot(SyncReport(applied: 2, pulled: 3, conflicts: 1)));
  });
}
