import 'package:flutter/material.dart';

import 'dashboard_localizations.dart';

/// Loading state for Dashboard content.
final class DashboardLoadingView extends StatelessWidget {
  const DashboardLoadingView({super.key, required this.copy});

  final DashboardCopy copy;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20.0),
      children: <Widget>[
        Semantics(
          liveRegion: true,
          label: copy.loadingNotes,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                height: 34.0,
                width: 180.0,
                color: colors.surfaceContainerHighest,
              ),
              const SizedBox(height: 12.0),
              Container(
                height: 18.0,
                width: 120.0,
                color: colors.surfaceContainerHighest,
              ),
              const SizedBox(height: 24.0),
              for (int index = 0; index < 4; index++) ...<Widget>[
                Container(
                  height: 136.0,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
                if (index < 3) const SizedBox(height: 12.0),
              ],
            ],
          ),
        ),
      ],
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Semantics(
          container: true,
          label: copy.noNotes,
          child: Column(
            key: const ValueKey<String>('dashboard-empty'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.note_alt_outlined, size: 56.0, color: colors.primary),
              const SizedBox(height: 16.0),
              Text(
                copy.noNotes,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              FilledButton.icon(
                key: const ValueKey<String>('dashboard-empty-create'),
                onPressed: onCreateNote,
                icon: const Icon(Icons.add),
                label: Text(copy.createFirstNote),
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Semantics(
          liveRegion: true,
          container: true,
          label: copy.loadError,
          child: Column(
            key: const ValueKey<String>('dashboard-error'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_off_outlined, size: 48.0, color: colors.error),
              const SizedBox(height: 16.0),
              Text(copy.loadError, textAlign: TextAlign.center),
              const SizedBox(height: 16.0),
              FilledButton.icon(
                key: const ValueKey<String>('dashboard-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(copy.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state for the full-note projection when overview data is still valid.
final class DashboardNotesErrorView extends StatelessWidget {
  const DashboardNotesErrorView({
    super.key,
    required this.copy,
    required this.onRetry,
  });

  final DashboardCopy copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Semantics(
          liveRegion: true,
          container: true,
          label: copy.loadError,
          child: Column(
            key: const ValueKey<String>('dashboard-notes-error'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.folder_off_outlined, size: 48.0, color: colors.error),
              const SizedBox(height: 16.0),
              Text(copy.loadError, textAlign: TextAlign.center),
              const SizedBox(height: 16.0),
              FilledButton.icon(
                key: const ValueKey<String>('dashboard-notes-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(copy.retry),
              ),
            ],
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
