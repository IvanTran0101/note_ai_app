import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';

export 'note_flow_page_header.dart';

/// Shared Notion-inspired presentation primitives.
///
/// These widgets are presentation-only: they own no state beyond what is
/// passed in, never touch Application/Infrastructure, and expose stable
/// semantics and focus behaviour so feature screens can be re-skinned without
/// changing their contracts.
final class NoteFlowSurface extends StatelessWidget {
  const NoteFlowSurface({
    super.key,
    required this.child,
    this.tone = NoteFlowSurfaceTone.page,
    this.radius,
    this.bordered = false,
    this.padding,
  });

  final Widget child;
  final NoteFlowSurfaceTone tone;
  final double? radius;
  final bool bordered;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final Color color = switch (tone) {
      NoteFlowSurfaceTone.page => tokens.pageSurface,
      NoteFlowSurfaceTone.sidebar => tokens.sidebarSurface,
      NoteFlowSurfaceTone.elevated => tokens.elevatedSurface,
      NoteFlowSurfaceTone.subtle => tokens.subtleSurface,
      NoteFlowSurfaceTone.selected => tokens.selectedSurface,
    };
    final double resolvedRadius = radius ?? 0;
    final Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(resolvedRadius),
        side: bordered ? BorderSide(color: tokens.divider) : BorderSide.none,
      ),
      child: content,
    );
  }
}

enum NoteFlowSurfaceTone { page, sidebar, elevated, subtle, selected }

/// Small muted label used to title a navigation or list section.
final class NoteFlowSectionLabel extends StatelessWidget {
  const NoteFlowSectionLabel({super.key, required this.label, this.padding});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextStyle? base = Theme.of(context).textTheme.labelSmall;
    return Semantics(
      header: true,
      child: Padding(
        padding:
            padding ??
            const EdgeInsets.symmetric(
              horizontal: NoteFlowSpacing.md,
              vertical: NoteFlowSpacing.xs,
            ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: base?.copyWith(
            color: tokens.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// One icon+label row in a sidebar or navigation list.
///
/// Keeps 48dp compact touch targets and dense desktop pointer rows, theme-token
/// keyboard focus feedback, and hover/press feedback driven by [InkWell] (which
/// already respects `MediaQuery.disableAnimations`).
final class NoteFlowSidebarRow extends StatefulWidget {
  const NoteFlowSidebarRow({
    super.key,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.selected = false,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;

  @override
  State<NoteFlowSidebarRow> createState() => _NoteFlowSidebarRowState();
}

final class _NoteFlowSidebarRowState extends State<NoteFlowSidebarRow> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final compact = NoteFlowLayout.isCompact(context);
    final Color foreground = widget.selected
        ? tokens.textPrimary
        : tokens.textSecondary;
    final TextStyle? base = Theme.of(context).textTheme.labelLarge;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NoteFlowSpacing.sm,
          vertical: 2,
        ),
        child: Material(
          color: widget.selected ? tokens.subtleSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(NoteFlowRadius.row),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (bool hasFocus) {
              if (_hasFocus != hasFocus) {
                setState(() => _hasFocus = hasFocus);
              }
            },
            hoverColor: tokens.subtleSurface,
            borderRadius: BorderRadius.circular(NoteFlowRadius.row),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NoteFlowRadius.row),
                border: Border.all(
                  color: _hasFocus ? tokens.focusRing : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: compact
                      ? 48
                      : widget.dense
                      ? 28
                      : 44,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NoteFlowSpacing.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        widget.selected
                            ? (widget.selectedIcon ?? widget.icon)
                            : widget.icon,
                        size: compact ? 20 : 18,
                        color: foreground,
                      ),
                      SizedBox(width: compact ? NoteFlowSpacing.md : 8),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: base?.copyWith(
                            color: foreground,
                            fontWeight: widget.selected
                                ? compact
                                      ? FontWeight.w600
                                      : FontWeight.w500
                                : compact
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Row inside a menu (More actions, settings lists).
///
/// Destructive items use [NoteFlowUiTokens.error]; disabled items keep their
/// label readable and expose `enabled: false` semantics.
final class NoteFlowMenuItem extends StatelessWidget {
  const NoteFlowMenuItem({
    super.key,
    required this.label,
    this.icon,
    this.destructive = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool enabled = onTap != null;
    final Color foreground = destructive
        ? tokens.error
        : (enabled ? tokens.textPrimary : tokens.textMuted);
    final TextStyle? base = Theme.of(context).textTheme.bodyLarge;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(NoteFlowRadius.row),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.subtleSurface,
          borderRadius: BorderRadius.circular(NoteFlowRadius.row),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: NoteFlowLayout.isCompact(context) ? 48 : 44,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NoteFlowSpacing.md,
                vertical: NoteFlowSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: NoteFlowSpacing.md),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: base?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
