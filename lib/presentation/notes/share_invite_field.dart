import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

final class ShareInviteField extends StatelessWidget {
  const ShareInviteField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.compact,
    required this.tokens,
    this.webPopup = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final bool compact;
  final NoteFlowUiTokens tokens;
  final bool webPopup;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final compact = this.compact && !webPopup;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        webPopup
            ? 6
            : compact
            ? 8
            : 10,
      ),
      borderSide: compact ? BorderSide.none : BorderSide(color: tokens.divider),
    );
    final field = TextField(
      key: const ValueKey('share-recipient-email'),
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      style: TextStyle(
        fontSize: compact ? 16 : 14,
        height: webPopup ? 20 / 14 : null,
      ),
      decoration: InputDecoration(
        visualDensity: webPopup ? VisualDensity.standard : null,
        labelText: compact || webPopup ? null : label,
        hintText: compact ? label : null,
        hint: webPopup
            ? ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    color: tokens.textMuted,
                  ),
                ),
              )
            : null,
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
        constraints: BoxConstraints(
          minHeight: webPopup
              ? 32
              : compact
              ? 48
              : 34,
        ),
        filled: true,
        fillColor: webPopup
            ? Colors.transparent
            : compact && Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFECEAE8)
            : tokens.subtleSurface,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: webPopup ? 8 : 12,
          vertical: webPopup ? 6 : 8,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: tokens.focusRing,
            width: webPopup ? 2 : 1,
          ),
        ),
      ),
    );
    return webPopup ? Semantics(label: label, child: field) : field;
  }
}
