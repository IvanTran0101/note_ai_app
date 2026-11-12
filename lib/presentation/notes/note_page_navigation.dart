import 'package:flutter/material.dart';

import '../../application/notes/note_page.dart';

/// One bounded page, with keyboard focus and native 48dp controls.
final class NotePageNavigation extends StatelessWidget {
  const NotePageNavigation({
    super.key,
    required this.page,
    required this.onPage,
    this.busy = false,
  });
  final NotePage page;
  final ValueChanged<int> onPage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final vi = Localizations.localeOf(context).languageCode == 'vi';
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('notes-page-previous'),
          tooltip: vi ? 'Trang trước' : 'Previous page',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          visualDensity: VisualDensity.standard,
          onPressed: busy || !page.hasPrevious
              ? null
              : () => onPage(page.page - 1),
          icon: const Icon(Icons.chevron_left),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            '${page.start}–${page.end} / ${page.total}',
            key: const ValueKey('notes-page-range'),
          ),
        ),
        IconButton(
          key: const ValueKey('notes-page-next'),
          tooltip: vi ? 'Trang sau' : 'Next page',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          visualDensity: VisualDensity.standard,
          onPressed: busy || !page.hasNext ? null : () => onPage(page.page + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
