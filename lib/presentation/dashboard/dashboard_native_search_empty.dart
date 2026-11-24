import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';

/// Native compact Search empty state using the existing clear-search action.
///
/// This is a finite-width child of its caller's scroll view. It deliberately
/// owns no scrolling or search state.
final class DashboardNativeSearchEmpty extends StatelessWidget {
  const DashboardNativeSearchEmpty({
    super.key,
    required this.copy,
    required this.onClear,
  });

  final DashboardCopy copy;
  final VoidCallback onClear;

  // 60dp, composed from the shared spacing scale to match the captured native
  // Search reference after its existing labels and parent-owned gap.
  static const double _referenceTopPadding =
      NoteFlowSpacing.xxxl + NoteFlowSpacing.md;

  @override
  Widget build(BuildContext context) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final TextStyle bodyStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    return Padding(
      padding: const EdgeInsets.only(
        top: _referenceTopPadding,
        left: NoteFlowSpacing.md,
        right: NoteFlowSpacing.md,
        bottom: NoteFlowSpacing.md,
      ),
      child: Column(
        key: const ValueKey<String>('dashboard-native-search-empty'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            copy.noMatches,
            textAlign: TextAlign.center,
            style: bodyStyle.copyWith(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w500,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: NoteFlowSpacing.xs),
          Center(
            child: TextButton(
              key: const ValueKey<String>('dashboard-clear-search-action'),
              onPressed: onClear,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              child: Text(copy.clearSearch),
            ),
          ),
        ],
      ),
    );
  }
}
