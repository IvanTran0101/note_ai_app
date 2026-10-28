import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';

/// Keeps the search controls mounted as the query's result body changes.
final class DashboardSearchViewport extends StatelessWidget {
  const DashboardSearchViewport({
    super.key,
    required this.header,
    required this.body,
    this.centerBody = false,
    this.footer,
  });

  final Widget header;
  final Widget body;
  final bool centerBody;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CustomScrollView(
          key: const ValueKey('dashboard-content'),
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: header),
            SliverLayoutBuilder(
              builder: (context, constraints) => SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: centerBody
                        ? (constraints.viewportMainAxisExtent -
                                  constraints.precedingScrollExtent)
                              .clamp(0.0, double.infinity)
                              .toDouble()
                        : 0,
                  ),
                  child: Align(
                    alignment: centerBody
                        ? Alignment.center
                        : Alignment.topLeft,
                    child: body,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ?footer,
    ],
  );
}

/// The existing no-match message and Clear search action, restyled for Web.
final class DashboardSearchEmptyState extends StatelessWidget {
  const DashboardSearchEmptyState({
    super.key,
    required this.copy,
    required this.onClear,
  });

  final DashboardCopy copy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowWorkspaceTokens.of(context);
    return Column(
      key: const ValueKey('dashboard-filtered-empty'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          copy.noMatches,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w500,
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: NoteFlowSpacing.xs),
        TextButton(
          key: const ValueKey('dashboard-clear-search-action'),
          onPressed: onClear,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            visualDensity: VisualDensity.standard,
          ),
          child: Text(copy.clearSearch),
        ),
      ],
    );
  }
}
