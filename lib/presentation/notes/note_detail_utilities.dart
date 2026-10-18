import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

/// Keeps the existing note metadata available without crowding the document.
/// Children remain mounted so transfers, previews and access listeners keep
/// their original owner when this presentation section is folded.
final class NoteDetailUtilities extends StatelessWidget {
  const NoteDetailUtilities({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const PageStorageKey('note-detail-utilities'),
        maintainState: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 16),
        minTileHeight: 48,
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        iconColor: tokens.textMuted,
        collapsedIconColor: tokens.textMuted,
        textColor: tokens.textSecondary,
        collapsedTextColor: tokens.textMuted,
        title: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        children: [child],
      ),
    );
  }
}
