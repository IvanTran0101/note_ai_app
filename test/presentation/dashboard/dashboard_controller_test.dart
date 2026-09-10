import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/dashboard/dashboard_overview.dart';
import 'package:note_ai_app/application/dashboard/get_dashboard_overview.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_controller.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_state.dart';

final DateTime _updatedAt = DateTime.utc(2026, 9, 10, 9);

void main() {
  group('DashboardController', () {
    test('starts idle and publishes loading then ready', () async {
      final _FakeDashboardQuery query = _FakeDashboardQuery(
        _overview(totalNotes: 2),
      );
      final DashboardController controller = DashboardController(query: query);
      final List<DashboardLoadStatus> statuses = <DashboardLoadStatus>[];
      controller.addListener((state) => statuses.add(state.status));

      expect(controller.state.status, DashboardLoadStatus.idle);
      final DashboardState state = await controller.load();

      expect(state.status, DashboardLoadStatus.ready);
      expect(controller.state, state);
      expect(statuses, <DashboardLoadStatus>[
        DashboardLoadStatus.loading,
        DashboardLoadStatus.ready,
      ]);
      expect(query.calls, 1);
      expect(query.lastRecentLimit, 5);
    });

    test('publishes empty when the overview has no notes', () async {
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(totalNotes: 0)),
      );

      final DashboardState state = await controller.load();

      expect(state.status, DashboardLoadStatus.empty);
      expect(state.overview!.isEmpty, isTrue);
    });

    test('converts query failures into a retryable failure state', () async {
      final StateError error = StateError('dashboard read failed');
      final _FakeDashboardQuery query = _FakeDashboardQuery(
        _overview(totalNotes: 1),
      )..error = error;
      final DashboardController controller = DashboardController(query: query);

      final DashboardState state = await controller.load();

      expect(state.status, DashboardLoadStatus.failure);
      expect(state.error, same(error));
      expect(state.hasError, isTrue);
      expect(query.calls, 1);
    });

    test('retry starts a new query after a failure', () async {
      final _FakeDashboardQuery query = _FakeDashboardQuery(
        _overview(totalNotes: 1),
      )..error = StateError('temporary failure');
      final DashboardController controller = DashboardController(query: query);

      expect((await controller.load()).status, DashboardLoadStatus.failure);
      query.error = null;

      final DashboardState retried = await controller.retry();

      expect(retried.status, DashboardLoadStatus.ready);
      expect(query.calls, 2);
    });

    test('shares concurrent loads as one in-flight query', () async {
      final Completer<DashboardOverview> completer =
          Completer<DashboardOverview>();
      final _FakeDashboardQuery query = _FakeDashboardQuery.pending(completer);
      final DashboardController controller = DashboardController(query: query);

      final Future<DashboardState> first = controller.load();
      final Future<DashboardState> second = controller.load();
      completer.complete(_overview(totalNotes: 1));

      expect(identical(first, second), isTrue);
      expect((await first).status, DashboardLoadStatus.ready);
      expect(query.calls, 1);
    });

    test('rejects invalid limits and operations after dispose', () {
      expect(
        () => DashboardController(
          query: _FakeDashboardQuery(_overview(totalNotes: 0)),
          recentLimit: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(totalNotes: 0)),
      )..dispose();

      expect(() => controller.load(), throwsA(isA<StateError>()));
      expect(controller.isDisposed, isTrue);
    });
  });
}

DashboardOverview _overview({required int totalNotes}) {
  final List<NoteDto> notes = <NoteDto>[
    NoteDto(
      id: 'note-1',
      ownerId: 'local-user',
      title: 'First note',
      content: 'Content',
      createdAt: _updatedAt,
      updatedAt: _updatedAt,
    ),
  ];
  return DashboardOverview(
    totalNotes: totalNotes,
    recentNotes: totalNotes == 0 ? const <NoteDto>[] : notes,
    lastUpdatedAt: totalNotes == 0 ? null : _updatedAt,
  );
}

final class _FakeDashboardQuery implements IDashboardOverviewQuery {
  _FakeDashboardQuery(this.result) : _pending = null;

  _FakeDashboardQuery.pending(Completer<DashboardOverview> completer)
    : result = null,
      _pending = completer;

  DashboardOverview? result;
  final Completer<DashboardOverview>? _pending;
  Object? error;
  int calls = 0;
  int? lastRecentLimit;

  @override
  Future<DashboardOverview> execute({required int recentLimit}) async {
    calls++;
    lastRecentLimit = recentLimit;
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    final Completer<DashboardOverview>? pending = _pending;
    if (pending != null) {
      return pending.future;
    }
    return result!;
  }
}
