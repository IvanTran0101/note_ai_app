import 'package:flutter/material.dart';

import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';
import 'sharing_localizations.dart';
import 'notes_theme_tokens.dart';

/// Compact presentation shell for the existing share-management controls.
/// Permission state and all actions remain owned by ShareManagementDialog.
final class ShareManagementSurface extends StatelessWidget {
  const ShareManagementSurface({
    super.key,
    required this.title,
    required this.closeLabel,
    required this.onClose,
    required this.content,
    required this.tokens,
  });

  final String title;
  final String closeLabel;
  final VoidCallback onClose;
  final Widget content;
  final NoteFlowUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final safeTop = view.viewPadding.top / view.devicePixelRatio;
    final topGap = (64 - safeTop).clamp(0, 64).toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(18) > 28;
    final titleLabel = Text(
      title,
      maxLines: largeText ? 3 : 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: tokens.textPrimary,
      ),
    );
    final closeButton = TextButton(
      onPressed: onClose,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 18),
      ),
      child: Text(closeLabel),
    );
    return Dialog(
      alignment: Alignment.bottomCenter,
      // The route already consumes the actual top safe area. A fixed40dp gap
      // assumed24dp status bars and pushed this sheet too low on tall cutouts.
      insetPadding: EdgeInsets.only(top: topGap),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Material(
              color: dark ? const Color(0xFF252525) : const Color(0xFFF9F8F7),
              surfaceTintColor: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                side: BorderSide(color: tokens.divider),
              ),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: tokens.divider,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (largeText)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: titleLabel),
                                closeButton,
                              ],
                            )
                          else
                            SizedBox(
                              height: 48,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 72,
                                      ),
                                      child: Center(child: titleLabel),
                                    ),
                                  ),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: closeButton,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: tokens.divider),
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: content,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final class ShareInviteField extends StatelessWidget {
  const ShareInviteField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.compact,
    required this.tokens,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final bool compact;
  final NoteFlowUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(compact ? 8 : 10),
      borderSide: compact ? BorderSide.none : BorderSide(color: tokens.divider),
    );
    return TextField(
      key: const ValueKey('share-recipient-email'),
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      style: TextStyle(fontSize: compact ? 16 : 14),
      decoration: InputDecoration(
        labelText: compact ? null : label,
        hintText: compact ? label : null,
        labelStyle: const TextStyle(fontSize: 14),
        hintStyle: TextStyle(
          fontSize: compact ? 16 : 14,
          color: tokens.textMuted,
        ),
        prefixIcon: compact
            ? Icon(Icons.search, size: 20, color: tokens.textMuted)
            : null,
        prefixIconConstraints: compact
            ? const BoxConstraints(minWidth: 48, minHeight: 48)
            : null,
        constraints: BoxConstraints(minHeight: compact ? 48 : 34),
        filled: true,
        fillColor: compact && Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFECEAE8)
            : tokens.subtleSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: tokens.focusRing),
        ),
      ),
    );
  }
}

final class ShareRecipientRow extends StatelessWidget {
  const ShareRecipientRow({
    super.key,
    required this.share,
    required this.copy,
    required this.compact,
    required this.enabled,
    required this.onChangeRole,
    required this.onRevoke,
    required this.onReactivate,
  });

  final NoteShareGrant share;
  final SharingCopy copy;
  final bool compact;
  final bool enabled;
  final VoidCallback onChangeRole;
  final VoidCallback onRevoke;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    final updatedAt = share.updatedAt
        .toLocal()
        .toIso8601String()
        .split('.')
        .first;
    final identity = Tooltip(
      message: share.recipientId,
      excludeFromSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            share.recipientId,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: copy.status(share)),
                TextSpan(text: ' · $updatedAt'),
              ],
            ),
            style: TextStyle(fontSize: 12, color: tokens.textSecondary),
          ),
        ],
      ),
    );
    final actions = share.isActive
        ? compact
              ? PopupMenuButton<_RecipientAction>(
                  enabled: enabled,
                  icon: Icon(Icons.more_horiz, color: tokens.textMuted),
                  onSelected: (action) => switch (action) {
                    _RecipientAction.changeRole => onChangeRole(),
                    _RecipientAction.revoke => onRevoke(),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _RecipientAction.changeRole,
                      child: Text(
                        copy.role(
                          share.role == NoteRole.viewer
                              ? NoteRole.editor
                              : NoteRole.viewer,
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _RecipientAction.revoke,
                      child: Text(copy.revoke),
                    ),
                  ],
                )
              : PopupMenuButton<_PermissionAction>(
                  key: const ValueKey('share-recipient-permission'),
                  enabled: enabled,
                  tooltip: copy.role(share.role),
                  padding: EdgeInsets.zero,
                  onSelected: (action) {
                    switch (action) {
                      case _PermissionAction.viewer:
                        if (share.role != NoteRole.viewer) onChangeRole();
                        break;
                      case _PermissionAction.editor:
                        if (share.role != NoteRole.editor) onChangeRole();
                        break;
                      case _PermissionAction.revoke:
                        onRevoke();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _PermissionAction.viewer,
                      enabled: share.role != NoteRole.viewer,
                      child: Text(copy.role(NoteRole.viewer)),
                    ),
                    PopupMenuItem(
                      value: _PermissionAction.editor,
                      enabled: share.role != NoteRole.editor,
                      child: Text(copy.role(NoteRole.editor)),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _PermissionAction.revoke,
                      child: Text(copy.revoke),
                    ),
                  ],
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            copy.role(share.role),
                            style: TextStyle(
                              fontSize: 13,
                              color: tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.expand_more,
                            size: 18,
                            color: tokens.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
        : TextButton(
            onPressed: enabled ? onReactivate : null,
            child: Text(copy.share),
          );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: identity),
            actions,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: identity),
          const SizedBox(width: 8),
          actions,
        ],
      ),
    );
  }
}

enum _RecipientAction { changeRole, revoke }

enum _PermissionAction { viewer, editor, revoke }
