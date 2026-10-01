import 'package:flutter/material.dart';

import '../../application/notes/note_dto.dart';
import 'note_security_localizations.dart';

final class NoteSecurityPanel extends StatelessWidget {
  const NoteSecurityPanel({
    super.key,
    required this.note,
    required this.locked,
    required this.busy,
    required this.serverAvailable,
    required this.canManage,
    required this.retained,
    required this.onAction,
    this.onBack,
  });
  final NoteDto note;
  final bool locked, busy, serverAvailable, canManage, retained;
  final ValueChanged<NoteSecurityAction> onAction;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final copy = NoteSecurityCopy(context);
    Widget button(NoteSecurityAction action, {bool enabled = true}) =>
        TextButton(
          key: ValueKey('note-security-${action.name}'),
          onPressed: busy || !enabled ? null : () => onAction(action),
          child: Text(copy.label(action)),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    onPressed: onBack,
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    icon: const Icon(Icons.arrow_back),
                  ),
                Icon(
                  note.isProtected ? Icons.lock_outline : Icons.shield_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note.isProtected
                        ? copy.protectedNote
                        : copy.label(NoteSecurityAction.enable),
                  ),
                ),
              ],
            ),
            if (locked) Text(note.isProtected ? copy.locked : copy.unavailable),
            if (retained) Text(copy.retained),
            if (busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                if (!note.isProtected)
                  button(
                    NoteSecurityAction.enable,
                    enabled: serverAvailable && !locked,
                  ),
                if (note.isProtected) ...[
                  if (locked || !canManage) button(NoteSecurityAction.unlock),
                  if (!locked) button(NoteSecurityAction.lock),
                  if (!locked && canManage) ...[
                    button(NoteSecurityAction.change, enabled: serverAvailable),
                    button(
                      NoteSecurityAction.disable,
                      enabled: serverAvailable,
                    ),
                  ],
                  button(NoteSecurityAction.recover, enabled: serverAvailable),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
