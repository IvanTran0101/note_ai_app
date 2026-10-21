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
          final largeText = MediaQuery.textScalerOf(context).scale(18) > 28;
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
                          SizedBox(
                            height: largeText ? 64 : 48,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 72,
                                    ),
                                    child: Center(
                                      child: Text(
                                        title,
                                        maxLines: largeText ? 2 : 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: tokens.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton(
                                    onPressed: onClose,
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      padding: EdgeInsets.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      textStyle: const TextStyle(fontSize: 18),
                                    ),
                                    child: Text(closeLabel),
                                  ),
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
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : null,
        constraints: BoxConstraints(minHeight: compact ? 36 : 34),
        filled: true,
        fillColor: compact && Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFECEAE8)
            : tokens.subtleSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: tokens.textSecondary),
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
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          share.recipientId,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        Text(
          '${copy.status(share)} · ${share.updatedAt.toLocal().toIso8601String().split('.').first}',
          maxLines: compact ? 1 : null,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
      ],
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
              : Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: enabled ? onChangeRole : null,
                      child: Text(
                        copy.role(
                          share.role == NoteRole.viewer
                              ? NoteRole.editor
                              : NoteRole.viewer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: enabled ? onRevoke : null,
                      child: Text(copy.revoke),
                    ),
                  ],
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
