import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';

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
/// Keeps a 44dp minimum hit target, a soft selected background, theme-token
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
          color: widget.selected ? tokens.selectedSurface : Colors.transparent,
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
                constraints: BoxConstraints(minHeight: widget.dense ? 40 : 44),
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
                        size: 20,
                        color: foreground,
                      ),
                      const SizedBox(width: NoteFlowSpacing.md),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: base?.copyWith(
                            color: foreground,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w500,
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

/// Top bar for a page surface: optional back button, breadcrumb, actions.
final class NoteFlowPageHeader extends StatelessWidget {
  const NoteFlowPageHeader({
    super.key,
    required this.breadcrumb,
    this.statusLabel,
    this.statusBusy = false,
    this.statusUnavailable = false,
    this.statusDirty = false,
    this.statusError = false,
    this.statusDraft = false,
    this.onBack,
    this.backTooltip,
    this.backKey,
    this.actions = const <Widget>[],
  });

  final String breadcrumb;
  final String? statusLabel;
  final bool statusBusy;
  final bool statusUnavailable;
  final bool statusDirty;
  final bool statusError;
  final bool statusDraft;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Key? backKey;
  final List<Widget> actions;

  static const Key statusKey = ValueKey<String>('note-flow-page-status');

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextStyle? base = Theme.of(context).textTheme.labelLarge;
    return Material(
      color: tokens.pageSurface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.divider)),
        ),
        child: SafeArea(
          bottom: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: <Widget>[
                if (onBack != null)
                  IconButton(
                    key: backKey,
                    tooltip: backTooltip,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: NoteFlowSpacing.xs),
                Expanded(
                  child: Text(
                    breadcrumb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: base?.copyWith(
                      color: tokens.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (statusLabel != null)
                  _NoteFlowPageStatus(
                    key: statusKey,
                    label: statusLabel!,
                    busy: statusBusy,
                    unavailable: statusUnavailable,
                    dirty: statusDirty,
                    error: statusError,
                    draft: statusDraft,
                  ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _NoteFlowPageStatus extends StatelessWidget {
  const _NoteFlowPageStatus({
    super.key,
    required this.label,
    required this.busy,
    required this.unavailable,
    required this.dirty,
    required this.error,
    required this.draft,
  });

  final String label;
  final bool busy;
  final bool unavailable;
  final bool dirty;
  final bool error;
  final bool draft;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool compact =
        MediaQuery.sizeOf(context).width < NoteFlowLayout.compactBreakpoint;
    final IconData statusIcon = unavailable
        ? Icons.cloud_off_outlined
        : error
        ? Icons.error_outline
        : dirty
        ? Icons.cloud_upload_outlined
        : draft
        ? Icons.edit_note_outlined
        : Icons.cloud_done_outlined;
    final Color iconColor = error
        ? Theme.of(context).colorScheme.error
        : tokens.textMuted;
    final Widget icon = busy
        ? SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.textMuted,
            ),
          )
        : Icon(statusIcon, size: 16, color: iconColor);

    return Semantics(
      liveRegion: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.sm),
          child: compact
              ? icon
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    icon,
                    const SizedBox(width: NoteFlowSpacing.xs),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
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
            constraints: const BoxConstraints(minHeight: 44),
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
