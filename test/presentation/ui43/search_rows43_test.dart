import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_search_sections.dart';

void main() {
  testWidgets(
    'uses inclusive local-date bucket boundaries and pinned override',
    (WidgetTester tester) async {
      final _GroupSnapshot result = await _observeGroups(
        tester,
        byCreatedAt: true,
        notesFor: (DateTime today) => <NoteDto>[
          _note('today', createdAt: _dateOffset(today, 0)),
          _note('yesterday', createdAt: _dateOffset(today, -1)),
          _note('week-start', createdAt: _dateOffset(today, -2)),
          _note('week-end', createdAt: _dateOffset(today, -6)),
          _note('month-start', createdAt: _dateOffset(today, -7)),
          _note('month-end', createdAt: _dateOffset(today, -29)),
          _note('older', createdAt: _dateOffset(today, -30)),
          _note('future', createdAt: _dateOffset(today, 1)),
          _note(
            'pinned-old',
            createdAt: _dateOffset(today, -90),
            pinnedAt: _dateOffset(today, -80),
          ),
        ],
      );
      final DashboardCopy copy = result.copy;
      final String olderDate = result.materialLocalizations.formatCompactDate(
        _dateOffset(result.today, -30),
      );
      final String futureDate = result.materialLocalizations.formatCompactDate(
        _dateOffset(result.today, 1),
      );

      expect(result.sections.keys.toList(), <String>[
        copy.today,
        copy.yesterday,
        copy.pastWeek,
        copy.past30Days,
        olderDate,
        futureDate,
        copy.pinned,
      ]);
      expect(_ids(result.sections, copy.today), <String>['today']);
      expect(_ids(result.sections, copy.yesterday), <String>['yesterday']);
      expect(_ids(result.sections, copy.pastWeek), <String>[
        'week-start',
        'week-end',
      ]);
      expect(_ids(result.sections, copy.past30Days), <String>[
        'month-start',
        'month-end',
      ]);
      expect(_ids(result.sections, olderDate), <String>['older']);
      expect(_ids(result.sections, futureDate), <String>['future']);
      expect(_ids(result.sections, copy.pinned), <String>['pinned-old']);
    },
  );

  testWidgets('keeps first-seen heading order and result order within groups', (
    WidgetTester tester,
  ) async {
    final _GroupSnapshot result = await _observeGroups(
      tester,
      byCreatedAt: true,
      notesFor: (DateTime today) => <NoteDto>[
        _note('week-first', createdAt: _dateOffset(today, -3)),
        _note('today-first', createdAt: _dateOffset(today, 0)),
        _note(
          'pinned-third',
          createdAt: _dateOffset(today, -30),
          pinnedAt: _dateOffset(today, -2),
        ),
        _note('week-second', createdAt: _dateOffset(today, -6)),
        _note('today-second', createdAt: _dateOffset(today, 0)),
      ],
    );

    expect(result.sections.keys.toList(), <String>[
      result.copy.pastWeek,
      result.copy.today,
      result.copy.pinned,
    ]);
    expect(_ids(result.sections, result.copy.pastWeek), <String>[
      'week-first',
      'week-second',
    ]);
    expect(_ids(result.sections, result.copy.today), <String>[
      'today-first',
      'today-second',
    ]);
    expect(_ids(result.sections, result.copy.pinned), <String>['pinned-third']);
  });

  testWidgets('groups by the selected created or updated date field', (
    WidgetTester tester,
  ) async {
    List<NoteDto> notesFor(DateTime today) => <NoteDto>[
      _note(
        'created-today-updated-old',
        createdAt: _dateOffset(today, 0),
        updatedAt: _dateOffset(today, -10),
      ),
      _note(
        'created-old-updated-yesterday',
        createdAt: _dateOffset(today, -10),
        updatedAt: _dateOffset(today, -1),
      ),
    ];

    final _GroupSnapshot byCreated = await _observeGroups(
      tester,
      byCreatedAt: true,
      notesFor: notesFor,
    );
    final _GroupSnapshot byUpdated = await _observeGroups(
      tester,
      byCreatedAt: false,
      notesFor: notesFor,
    );

    expect(_ids(byCreated.sections, byCreated.copy.today), <String>[
      'created-today-updated-old',
    ]);
    expect(_ids(byCreated.sections, byCreated.copy.past30Days), <String>[
      'created-old-updated-yesterday',
    ]);
    expect(_ids(byUpdated.sections, byUpdated.copy.past30Days), <String>[
      'created-today-updated-old',
    ]);
    expect(_ids(byUpdated.sections, byUpdated.copy.yesterday), <String>[
      'created-old-updated-yesterday',
    ]);
  });

  testWidgets('returns no sections for an empty result list', (
    WidgetTester tester,
  ) async {
    final _GroupSnapshot result = await _observeGroups(
      tester,
      byCreatedAt: false,
      notesFor: (_) => const <NoteDto>[],
    );

    expect(result.sections, isEmpty);
  });
}

Future<_GroupSnapshot> _observeGroups(
  WidgetTester tester, {
  required bool byCreatedAt,
  required List<NoteDto> Function(DateTime today) notesFor,
}) async {
  _GroupSnapshot? snapshot;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DashboardCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: Builder(
        builder: (BuildContext context) {
          final DateTime now = DateTime.now();
          final DateTime today = DateTime(now.year, now.month, now.day);
          final DashboardCopy copy = DashboardCopy.of(context);
          final MaterialLocalizations materialLocalizations =
              MaterialLocalizations.of(context);
          final List<NoteDto> notes = notesFor(today);
          snapshot = _GroupSnapshot(
            today: today,
            copy: copy,
            materialLocalizations: materialLocalizations,
            sections: dashboardSearchSections(
              context,
              notes,
              copy: copy,
              byCreatedAt: byCreatedAt,
            ),
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return snapshot!;
}

NoteDto _note(
  String id, {
  required DateTime createdAt,
  DateTime? updatedAt,
  DateTime? pinnedAt,
}) => NoteDto(
  id: id,
  ownerId: 'synthetic-user',
  title: 'Synthetic $id',
  content: 'Synthetic preview',
  createdAt: createdAt,
  updatedAt: updatedAt ?? createdAt,
  pinnedAt: pinnedAt,
);

DateTime _dateOffset(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day, 12).add(Duration(days: offset));

List<String> _ids(Map<String, List<NoteDto>> sections, String label) =>
    sections[label]!.map((NoteDto note) => note.id).toList();

final class _GroupSnapshot {
  const _GroupSnapshot({
    required this.today,
    required this.copy,
    required this.materialLocalizations,
    required this.sections,
  });

  final DateTime today;
  final DashboardCopy copy;
  final MaterialLocalizations materialLocalizations;
  final Map<String, List<NoteDto>> sections;
}
