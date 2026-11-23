import 'package:flutter/material.dart';

/// Explicit navigation remains usable inside the editor's outer scroll view.
final class AttachmentDocumentControls extends StatelessWidget {
  const AttachmentDocumentControls({
    super.key,
    required this.page,
    required this.pages,
    required this.busy,
    required this.onPage,
  });
  final int page, pages;
  final bool busy;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: constraints.hasBoundedHeight
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous PDF page',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: !busy && page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(pages == 0 ? 'Loading PDF…' : 'Page $page / $pages'),
          IconButton(
            tooltip: 'Next PDF page',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: !busy && pages > 0 && page < pages
                ? () => onPage(page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );
}
