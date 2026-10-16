import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';

/// Short fades for display state only; never wrap a live note editor here.
final class NoteFlowStateTransition extends StatelessWidget {
  const NoteFlowStateTransition({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: NoteFlowMotion.duration(context, NoteFlowMotion.fast),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (Widget? current, List<Widget> outgoing) => Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          for (final Widget previous in outgoing)
            ExcludeFocus(
              child: ExcludeSemantics(child: IgnorePointer(child: previous)),
            ),
          ?current,
        ],
      ),
      child: child,
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
    this.statusIndicator,
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
  final Widget? statusIndicator;

  static const Key statusKey = ValueKey<String>('note-flow-page-status');

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    return Material(
      color: tokens.pageSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.divider)),
        ),
        child: SafeArea(bottom: false, child: LayoutBuilder(builder: _layout)),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final compact = constraints.maxWidth < NoteFlowLayout.compactBreakpoint;
    final wrapActions = constraints.maxWidth < 360 && actions.length > 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 56 : 44),
          child: _row(context, compact: compact, inlineActions: !wrapActions),
        ),
        if (wrapActions)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(alignment: WrapAlignment.end, children: actions),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required bool compact,
    required bool inlineActions,
  }) {
    final tokens = NoteFlowUiTokens.of(context);
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            key: backKey,
            tooltip: backTooltip,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 20),
            visualDensity: compact
                ? VisualDensity.standard
                : VisualDensity.compact,
          ),
        const SizedBox(width: NoteFlowSpacing.xs),
        Expanded(
          child: compact && actions.length > 2 && inlineActions
              ? const SizedBox.shrink()
              : Text(
                  breadcrumb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
        if (statusLabel != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 48 : 240),
            child: _status(compact),
          ),
        if (inlineActions) ...actions,
      ],
    );
  }

  Widget _status(bool compact) => Semantics(
    key: const ValueKey('note-flow-status-semantics'),
    container: true,
    child: statusIndicator != null
        ? KeyedSubtree(key: statusKey, child: statusIndicator!)
        : NoteFlowStateTransition(
            key: statusKey,
            child: _NoteFlowPageStatus(
              key: ValueKey<String>('$statusLabel-$statusBusy'),
              label: statusLabel!,
              compact: compact,
              busy: statusBusy,
              unavailable: statusUnavailable,
              dirty: statusDirty,
              error: statusError,
              draft: statusDraft,
            ),
          ),
  );
}

final class _NoteFlowPageStatus extends StatelessWidget {
  const _NoteFlowPageStatus({
    super.key,
    required this.label,
    required this.compact,
    required this.busy,
    required this.unavailable,
    required this.dirty,
    required this.error,
    required this.draft,
  });

  final String label;
  final bool compact;
  final bool busy;
  final bool unavailable;
  final bool dirty;
  final bool error;
  final bool draft;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
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
      container: true,
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
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
