import 'package:flutter/material.dart';

/// Product-specific semantic colors that are not part of Material's core
/// [ColorScheme]. Components read these through [ThemeExtension] so light and
/// dark themes keep the same semantic contract.
@immutable
final class NoteFlowSemanticColors
    extends ThemeExtension<NoteFlowSemanticColors> {
  const NoteFlowSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  factory NoteFlowSemanticColors.fromColorScheme(ColorScheme colorScheme) {
    // Tertiary is the approved first-pass semantic accent. It can be replaced
    // by a dedicated success palette later without changing component APIs.
    return NoteFlowSemanticColors(
      success: colorScheme.tertiary,
      onSuccess: colorScheme.onTertiary,
      successContainer: colorScheme.tertiaryContainer,
      onSuccessContainer: colorScheme.onTertiaryContainer,
    );
  }

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  @override
  NoteFlowSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
  }) {
    return NoteFlowSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    );
  }

  @override
  NoteFlowSemanticColors lerp(
    covariant ThemeExtension<NoteFlowSemanticColors>? other,
    double t,
  ) {
    if (other is! NoteFlowSemanticColors) {
      return this;
    }
    return NoteFlowSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t) ?? onSuccess,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t) ??
          successContainer,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t) ??
          onSuccessContainer,
    );
  }
}

/// Shared responsive breakpoints and page widths measured from the reference.
abstract final class NoteFlowLayout {
  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 840;

  /// The compact page column starts after the 72dp navigation gutter and a
  /// 24dp page inset used by the Notion mobile/web reference.
  static const double compactPageLeadingInset = 96;

  /// Includes the page inset and trailing gutter around the content column.
  static const double compactPageMaxWidth = 360;
  static const double compactPageNarrowLeadingInset = 16;
  static const double compactEditorMaxWidth = compactPageMaxWidth;

  /// The mobile reference places its H1 at y=212 below a 44dp top bar.
  static const double compactPageTopPadding = 160;
  static const double editorTopPadding = 112;

  /// Detail has a second 44dp page toolbar before the editor content.
  static const double compactEditorTopPadding = 116;
  static const double editorMaxWidth = 720;
  static const double editorTextMaxWidth = 708;
  static const double dashboardContentMaxWidth = 768;
  static const double dashboardTopPadding = 116;

  static double compactPageLeadingInsetFor(BuildContext context) {
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final double progress = ((viewportWidth - 320) / 70).clamp(0.0, 1.0);
    return compactPageNarrowLeadingInset +
        (compactPageLeadingInset - compactPageNarrowLeadingInset) * progress;
  }

  static double compactPageFrameMaxWidthFor(BuildContext context) =>
      compactPageMaxWidth +
      compactPageLeadingInsetFor(context) +
      NoteFlowSpacing.lg;

  static double compactPageTopInset(BuildContext context) =>
      (compactPageTopPadding - MediaQuery.viewPaddingOf(context).top)
          .clamp(0.0, double.infinity)
          .toDouble();

  static double compactEditorTopInset(BuildContext context) =>
      (compactEditorTopPadding - MediaQuery.viewPaddingOf(context).top)
          .clamp(0.0, double.infinity)
          .toDouble();
}

/// Shared spacing scale (dp). Every gap in presentation code must pick one of
/// these values instead of an arbitrary number.
abstract final class NoteFlowSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Shared corner radii: small for rows and inputs, large for dialogs and cards.
abstract final class NoteFlowRadius {
  static const double row = 6;
  static const double input = 8;
  static const double card = 8;
  static const double dialog = 12;
}

/// Shared motion timings. Keep transitions short and non-blocking, and honour
/// `MediaQuery.disableAnimations` at every call site.
abstract final class NoteFlowMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 200);
}

/// Notion-inspired surface/text/line tokens for both brightnesses.
///
/// Values are measured against the Notion reference matrix
/// (`docs/notion-reference-matrix.md`). Components must read these instead of
/// literal colours so one visual role always maps to one token.
@immutable
final class NoteFlowUiTokens extends ThemeExtension<NoteFlowUiTokens> {
  const NoteFlowUiTokens({
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
    required this.success,
    required this.onDestructive,
  });

  factory NoteFlowUiTokens.light() {
    return const NoteFlowUiTokens(
      pageSurface: Color(0xFFFFFFFF),
      sidebarSurface: Color(0xFFF7F7F5),
      elevatedSurface: Color(0xFFFFFFFF),
      subtleSurface: Color(0xFFF1F1EF),
      selectedSurface: Color(0xFFEDEDEC),
      textPrimary: Color(0xFF2C2C2B),
      textSecondary: Color(0xFF62615C),
      textMuted: Color(0xFF70706B),
      divider: Color(0xFFEDEDEC),
      link: Color(0xFF2383E2),
      focusRing: Color(0xFF2383E2),
      error: Color(0xFFEB5757),
      success: Color(0xFF448361),
      onDestructive: Color(0xFFFFFFFF),
    );
  }

  factory NoteFlowUiTokens.dark() {
    return const NoteFlowUiTokens(
      pageSurface: Color(0xFF191919),
      sidebarSurface: Color(0xFF202020),
      elevatedSurface: Color(0xFF2F2F2F),
      subtleSurface: Color(0xFF252525),
      selectedSurface: Color(0xFF2F2F2F),
      textPrimary: Color(0xFFF0EFED),
      textSecondary: Color(0xFFB3B3B3),
      textMuted: Color(0xFF8B8B8B),
      divider: Color(0xFF303030),
      link: Color(0xFF529CCA),
      focusRing: Color(0xFF529CCA),
      error: Color(0xFFE06A6A),
      success: Color(0xFF5FA784),
      onDestructive: Color(0xFF191919),
    );
  }

  /// Page/editor background.
  final Color pageSurface;

  /// Navigation sidebar background.
  final Color sidebarSurface;

  /// Menus, dialogs and bottom sheets.
  final Color elevatedSurface;

  /// Hover/press wash on interactive rows.
  final Color subtleSurface;

  /// Background of the active/selected row.
  final Color selectedSurface;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color link;
  final Color focusRing;
  final Color error;
  final Color success;

  /// Foreground for destructive menu items and destructive buttons.
  final Color onDestructive;

  static NoteFlowUiTokens of(BuildContext context) {
    return Theme.of(context).extension<NoteFlowUiTokens>() ??
        NoteFlowUiTokens.light();
  }

  @override
  NoteFlowUiTokens copyWith({
    Color? pageSurface,
    Color? sidebarSurface,
    Color? elevatedSurface,
    Color? subtleSurface,
    Color? selectedSurface,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? divider,
    Color? link,
    Color? focusRing,
    Color? error,
    Color? success,
    Color? onDestructive,
  }) {
    return NoteFlowUiTokens(
      pageSurface: pageSurface ?? this.pageSurface,
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      selectedSurface: selectedSurface ?? this.selectedSurface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      link: link ?? this.link,
      focusRing: focusRing ?? this.focusRing,
      error: error ?? this.error,
      success: success ?? this.success,
      onDestructive: onDestructive ?? this.onDestructive,
    );
  }

  @override
  NoteFlowUiTokens lerp(
    covariant ThemeExtension<NoteFlowUiTokens>? other,
    double t,
  ) {
    if (other is! NoteFlowUiTokens) {
      return this;
    }
    return NoteFlowUiTokens(
      pageSurface: Color.lerp(pageSurface, other.pageSurface, t) ?? pageSurface,
      sidebarSurface:
          Color.lerp(sidebarSurface, other.sidebarSurface, t) ?? sidebarSurface,
      elevatedSurface:
          Color.lerp(elevatedSurface, other.elevatedSurface, t) ??
          elevatedSurface,
      subtleSurface:
          Color.lerp(subtleSurface, other.subtleSurface, t) ?? subtleSurface,
      selectedSurface:
          Color.lerp(selectedSurface, other.selectedSurface, t) ??
          selectedSurface,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      link: Color.lerp(link, other.link, t) ?? link,
      focusRing: Color.lerp(focusRing, other.focusRing, t) ?? focusRing,
      error: Color.lerp(error, other.error, t) ?? error,
      success: Color.lerp(success, other.success, t) ?? success,
      onDestructive:
          Color.lerp(onDestructive, other.onDestructive, t) ?? onDestructive,
    );
  }
}
