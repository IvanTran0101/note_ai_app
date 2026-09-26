import 'package:flutter/material.dart';

import '../common/note_flow_primitives.dart';
import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';

/// Loading state for Dashboard content.
final class DashboardLoadingView extends StatelessWidget {
  const DashboardLoadingView({super.key, required this.copy});

  final DashboardCopy copy;

  @override
  Widget build(BuildContext context) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    return _DashboardStatePage(
      copy: copy,
      child: Semantics(
        liveRegion: true,
        container: true,
        label: copy.loadingNotes,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _DashboardSkeletonBar(
                        color: tokens.subtleSurface,
                        width: 180,
                        height: 48,
                      ),
                      const SizedBox(height: NoteFlowSpacing.sm),
                      _DashboardSkeletonBar(
                        color: tokens.subtleSurface,
                        width: 260,
                        height: 12,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NoteFlowSpacing.md),
                _DashboardSkeletonBar(
                  color: tokens.subtleSurface,
                  width: 120,
                  height: 44,
                  radius: NoteFlowRadius.input,
                ),
              ],
            ),
            const SizedBox(height: NoteFlowSpacing.xl),
            Row(
              children: <Widget>[
                _DashboardSkeletonBar(
                  color: tokens.subtleSurface,
                  width: 104,
                  height: 48,
                  radius: NoteFlowRadius.input,
                ),
                const SizedBox(width: NoteFlowSpacing.sm),
                _DashboardSkeletonBar(
                  color: tokens.subtleSurface,
                  width: 128,
                  height: 48,
                  radius: NoteFlowRadius.input,
                ),
              ],
            ),
            const SizedBox(height: NoteFlowSpacing.xl),
            _DashboardSkeletonBar(
              color: tokens.subtleSurface,
              width: 144,
              height: 18,
            ),
            const SizedBox(height: NoteFlowSpacing.sm),
            for (int index = 0; index < 4; index++) ...<Widget>[
              _DashboardLoadingNoteRow(color: tokens.subtleSurface),
              if (index < 3)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NoteFlowSpacing.xl,
                  ),
                  child: Divider(height: 1, color: tokens.divider),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _DashboardLoadingNoteRow extends StatelessWidget {
  const _DashboardLoadingNoteRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: <Widget>[
          _DashboardSkeletonBar(color: color, width: 20, height: 20),
          const SizedBox(width: NoteFlowSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DashboardSkeletonBar(color: color, width: 180, height: 12),
                const SizedBox(height: NoteFlowSpacing.xs),
                _DashboardSkeletonBar(color: color, width: 320, height: 10),
              ],
            ),
          ),
          const SizedBox(width: NoteFlowSpacing.md),
          _DashboardSkeletonBar(color: color, width: 64, height: 10),
        ],
      ),
    );
  }
}

final class _DashboardSkeletonBar extends StatelessWidget {
  const _DashboardSkeletonBar({
    required this.color,
    required this.width,
    required this.height,
    this.radius = NoteFlowRadius.row,
  });

  final Color color;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Empty state for an owner who has no notes.
final class DashboardEmptyView extends StatelessWidget {
  const DashboardEmptyView({
    super.key,
    required this.copy,
    required this.onCreateNote,
  });

  final DashboardCopy copy;
  final VoidCallback onCreateNote;

  @override
  Widget build(BuildContext context) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    return _DashboardStatePage(
      copy: copy,
      child: Semantics(
        key: const ValueKey<String>('dashboard-empty'),
        container: true,
        label: copy.noNotes,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NoteFlowSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  copy.recents,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: NoteFlowSpacing.md),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: tokens.textSecondary,
                  ),
                  const SizedBox(width: NoteFlowSpacing.md),
                  Expanded(
                    child: Text(
                      copy.noNotes,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NoteFlowSpacing.sm),
              FilledButton.icon(
                key: const ValueKey<String>('dashboard-empty-create'),
                onPressed: onCreateNote,
                icon: const Icon(Icons.add),
                label: Text(copy.createFirstNote),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.selectedSurface,
                  foregroundColor: tokens.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NoteFlowRadius.input),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state for a Dashboard overview query failure.
final class DashboardErrorView extends StatelessWidget {
  const DashboardErrorView({
    super.key,
    required this.copy,
    required this.onRetry,
  });

  final DashboardCopy copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _DashboardStatePage(
      copy: copy,
      child: _DashboardLoadError(
        copy: copy,
        onRetry: onRetry,
        stateKey: const ValueKey<String>('dashboard-error'),
        retryKey: const ValueKey<String>('dashboard-retry'),
      ),
    );
  }
}

/// Error state for the full-note projection when overview data is still valid.
final class DashboardNotesErrorView extends StatelessWidget {
  const DashboardNotesErrorView({
    super.key,
    required this.copy,
    this.onRetry,
    this.message,
  });

  final DashboardCopy copy;
  final VoidCallback? onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return _DashboardStatePage(
      copy: copy,
      child: _DashboardLoadError(
        copy: copy,
        onRetry: onRetry,
        message: message,
        informational: message != null,
        stateKey: const ValueKey<String>('dashboard-notes-error'),
        retryKey: const ValueKey<String>('dashboard-notes-retry'),
      ),
    );
  }
}

final class _DashboardStatePage extends StatelessWidget {
  const _DashboardStatePage({required this.copy, required this.child});

  final DashboardCopy copy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final bool compact = viewportWidth < NoteFlowLayout.compactBreakpoint;
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        Align(
          alignment: compact ? Alignment.topLeft : Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact
                  ? NoteFlowLayout.compactPageFrameMaxWidthFor(context)
                  : NoteFlowLayout.dashboardContentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact
                    ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                    : NoteFlowSpacing.xl,
                compact
                    ? NoteFlowLayout.compactPageTopInset(context)
                    : NoteFlowLayout.dashboardTopPadding,
                compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xl,
                NoteFlowSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!compact) ...<Widget>[
                    Text(
                      copy.title,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: 40,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                    ),
                    const SizedBox(height: NoteFlowSpacing.xl),
                  ],
                  child,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _DashboardLoadError extends StatelessWidget {
  const _DashboardLoadError({
    required this.copy,
    required this.onRetry,
    required this.stateKey,
    required this.retryKey,
    this.message,
    this.informational = false,
  });

  final DashboardCopy copy;
  final VoidCallback? onRetry;
  final Key stateKey;
  final Key retryKey;
  final String? message;
  final bool informational;

  @override
  Widget build(BuildContext context) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final String errorMessage = message ?? copy.loadError;
    return Semantics(
      key: stateKey,
      liveRegion: true,
      container: true,
      label: errorMessage,
      child: NoteFlowSurface(
        tone: NoteFlowSurfaceTone.subtle,
        bordered: true,
        radius: NoteFlowRadius.card,
        child: Padding(
          padding: const EdgeInsets.all(NoteFlowSpacing.lg),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget message = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.cloud_off_outlined,
                    color: informational ? tokens.textMuted : tokens.error,
                    size: 20,
                  ),
                  const SizedBox(width: NoteFlowSpacing.md),
                  Expanded(
                    child: Text(
                      errorMessage,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: tokens.textPrimary),
                    ),
                  ),
                ],
              );
              final Widget? retry = onRetry == null
                  ? null
                  : TextButton.icon(
                      key: retryKey,
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(copy.retry),
                    );
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    message,
                    if (retry != null) ...<Widget>[
                      const SizedBox(height: NoteFlowSpacing.sm),
                      Align(alignment: Alignment.centerRight, child: retry),
                    ],
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: message),
                  if (retry != null) ...<Widget>[
                    const SizedBox(width: NoteFlowSpacing.md),
                    retry,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Inline error banner for a loaded note collection.
final class DashboardInlineError extends StatelessWidget {
  const DashboardInlineError({
    super.key,
    required this.copy,
    required this.onRetry,
  });

  final DashboardCopy copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Card(
        key: const ValueKey<String>('dashboard-error'),
        color: colors.errorContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget icon = Icon(
                Icons.info_outline,
                color: colors.onErrorContainer,
              );
              final Widget message = Expanded(
                child: Text(
                  copy.loadError,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              );
              final Widget retry = TextButton(
                key: const ValueKey<String>('dashboard-retry'),
                onPressed: onRetry,
                child: Text(copy.retry),
              );
              if (constraints.maxWidth < 420.0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        icon,
                        const SizedBox(width: 8.0),
                        message,
                      ],
                    ),
                    Align(alignment: Alignment.centerRight, child: retry),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  icon,
                  const SizedBox(width: 8.0),
                  message,
                  retry,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// State shown when a local search query matches no notes.
final class DashboardFilteredEmptyView extends StatelessWidget {
  const DashboardFilteredEmptyView({
    super.key,
    required this.copy,
    required this.onClear,
  });

  final DashboardCopy copy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        key: const ValueKey<String>('dashboard-filtered-empty'),
        children: <Widget>[
          const Icon(Icons.search_off_outlined, size: 48.0),
          const SizedBox(height: 12.0),
          Text(copy.noMatches),
          const SizedBox(height: 4.0),
          TextButton(
            key: const ValueKey<String>('dashboard-clear-search-action'),
            onPressed: onClear,
            child: Text(copy.clearSearch),
          ),
        ],
      ),
    );
  }
}
