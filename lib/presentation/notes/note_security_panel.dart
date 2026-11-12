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
    this.localFirst = false,
    this.pendingProtection = false,
    this.compact = false,
    this.menuItem = false,
  });
  final NoteDto note;
  final bool locked, busy, serverAvailable, canManage, retained;
  final bool localFirst, pendingProtection;
  final bool compact;
  final bool menuItem;
  final ValueChanged<NoteSecurityAction> onAction;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    if (!note.isProtected && !canManage && !locked) {
      return const SizedBox.shrink();
    }
    final copy = NoteSecurityCopy(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accessLost = locked && !note.isProtected && note.share != null;
    final actions = <(NoteSecurityAction, bool)>[
      if (localFirst && pendingProtection && note.share == null)
        (NoteSecurityAction.syncProtection, serverAvailable && !locked),
      if (!note.isProtected && canManage)
        (NoteSecurityAction.enable, (localFirst || serverAvailable) && !locked),
      if (note.isProtected) ...[
        if (locked || !canManage) (NoteSecurityAction.unlock, true),
        if (!locked) (NoteSecurityAction.lock, true),
        if (!locked && canManage) ...[
          (NoteSecurityAction.change, localFirst || serverAvailable),
          (NoteSecurityAction.disable, localFirst || serverAvailable),
        ],
        if (note.share == null) (NoteSecurityAction.recover, serverAvailable),
      ],
    ];
    if (compact && !locked) {
      return PopupMenuButton<NoteSecurityAction>(
        key: const ValueKey('note-security-menu'),
        tooltip: <String>[
          note.isProtected
              ? copy.protectedNote
              : copy.label(NoteSecurityAction.enable),
          if (pendingProtection) copy.pendingProtection,
          if (retained) copy.retained,
        ].join('. '),
        enabled: !busy,
        icon: menuItem
            ? null
            : busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                note.isProtected ? Icons.lock_outline : Icons.shield_outlined,
                size: 20,
              ),
        onSelected: onAction,
        itemBuilder: (_) => [
          if (pendingProtection)
            PopupMenuItem(enabled: false, child: Text(copy.pendingProtection)),
          if (retained)
            PopupMenuItem(enabled: false, child: Text(copy.retained)),
          for (final (action, enabled) in actions)
            PopupMenuItem(
              key: ValueKey('note-security-${action.name}'),
              value: action,
              enabled: enabled,
              child: Text(copy.label(action)),
            ),
        ],
        child: menuItem ? _menuLabel(copy) : null,
      );
    }
    Widget button(NoteSecurityAction action, {bool enabled = true}) =>
        TextButton(
          key: ValueKey('note-security-${action.name}'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: busy || !enabled ? null : () => onAction(action),
          child: Text(copy.label(action)),
        );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        : accessLost
                        ? copy.accessUnavailable
                        : copy.label(NoteSecurityAction.enable),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  note.isProtected
                      ? copy.locked
                      : accessLost
                      ? copy.accessUnavailableHint
                      : copy.unavailable,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accessLost ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (retained)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  accessLost ? copy.accessRetained : copy.retained,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (pendingProtection)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  copy.pendingProtection,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (action, enabled) in actions)
                  button(action, enabled: enabled),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuLabel(NoteSecurityCopy copy) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            note.isProtected ? Icons.lock_outline : Icons.shield_outlined,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              note.isProtected
                  ? copy.protectedNote
                  : copy.label(NoteSecurityAction.enable),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    ),
  );
}
