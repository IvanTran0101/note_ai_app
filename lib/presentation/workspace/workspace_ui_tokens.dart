import 'package:flutter/material.dart';

/// Notion-inspired colors scoped to the workspace and dashboard surfaces.
///
/// Authentication and editor routes keep using the shared app palette, so
/// workspace polish does not change locked Login/Register UI.
final class NoteFlowWorkspaceTokens {
  const NoteFlowWorkspaceTokens({
    required this.pageSurface,
    required this.sidebarSurface,
    required this.elevatedSurface,
    required this.subtleSurface,
    required this.selectedSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.link,
    required this.focusRing,
    required this.error,
    this.compactHomeSurface = const Color(0xFFF9F8F7),
  });

  static const NoteFlowWorkspaceTokens _light = NoteFlowWorkspaceTokens(
    pageSurface: Color(0xFFFFFFFF),
    sidebarSurface: Color(0xFFF7F7F5),
    elevatedSurface: Color(0xFFFFFFFF),
    subtleSurface: Color(0xFFF0EFED),
    selectedSurface: Color(0xFFF0EFED),
    textPrimary: Color(0xFF252525),
    textSecondary: Color(0xFF5D625F),
    textMuted: Color(0xFF656965),
    divider: Color(0xFFE5E8E5),
    link: Color(0xFF236BB3),
    focusRing: Color(0xFF236BB3),
    error: Color(0xFFB3261E),
  );

  static const NoteFlowWorkspaceTokens _dark = NoteFlowWorkspaceTokens(
    compactHomeSurface: Color(0xFF191919),
    pageSurface: Color(0xFF191919),
    sidebarSurface: Color(0xFF202020),
    elevatedSurface: Color(0xFF2F2F2F),
    subtleSurface: Color(0xFF252525),
    selectedSurface: Color(0xFF2F2F2F),
    textPrimary: Color(0xFFF4F4F1),
    textSecondary: Color(0xFFC0C5C1),
    textMuted: Color(0xFF969C98),
    divider: Color(0xFF353A37),
    link: Color(0xFF80B6F4),
    focusRing: Color(0xFF80B6F4),
    error: Color(0xFFFFB4AB),
  );

  static NoteFlowWorkspaceTokens light() => _light;

  static NoteFlowWorkspaceTokens dark() => _dark;

  final Color pageSurface;
  final Color compactHomeSurface;
  final Color sidebarSurface;
  final Color elevatedSurface;
  final Color subtleSurface;
  final Color selectedSurface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color link;
  final Color focusRing;
  final Color error;

  static NoteFlowWorkspaceTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }
}
