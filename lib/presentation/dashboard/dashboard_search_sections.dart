import 'package:flutter/material.dart';

import '../../application/notes/note_dto.dart';
import 'dashboard_localizations.dart';

/// Labels the already ordered result projection without changing its query,
/// pin priority, access state or persistence.
Map<String, List<NoteDto>> dashboardSearchSections(
  BuildContext context,
  List<NoteDto> notes, {
  required DashboardCopy copy,
  required bool byCreatedAt,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sections = <String, List<NoteDto>>{};
  for (final note in notes) {
    final date = (byCreatedAt ? note.createdAt : note.updatedAt).toLocal();
    final days = today
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    final label = note.isPinned
        ? copy.pinned
        : switch (days) {
            0 => copy.today,
            1 => copy.yesterday,
            >= 2 && < 7 => copy.pastWeek,
            >= 7 && < 30 => copy.past30Days,
            _ => MaterialLocalizations.of(context).formatCompactDate(date),
          };
    sections.putIfAbsent(label, () => <NoteDto>[]).add(note);
  }
  return sections;
}
