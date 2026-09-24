import 'package:flutter/material.dart';

import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';

/// Keeps the Notes list hierarchy visible while the existing load request runs.
///
/// This is a static, presentation-only placeholder: it does not imply that any
/// note has loaded or add controls that can run before the real data arrives.
final class NotesWorkspaceLoadingView extends StatelessWidget {
  const NotesWorkspaceLoadingView({super.key, required this.copy});

  static const Key loadingKey = ValueKey<String>('notes-workspace-loading');
  static const Key skeletonKey = ValueKey<String>(
    'notes-workspace-loading-skeleton',
  );

  final NotesCopy copy;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool compact =
        MediaQuery.sizeOf(context).width < NoteFlowLayout.compactBreakpoint;

    return Semantics(
      key: loadingKey,
      container: true,
      liveRegion: true,
      label: copy.loadingNotes,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.pageSurface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact
                    ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                    : NoteFlowSpacing.xl,
                compact
                    ? NoteFlowLayout.compactPageTopInset(context)
                    : NoteFlowLayout.editorTopPadding,
                compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xl,
                NoteFlowSpacing.xl,
              ),
              child: Align(
                alignment: compact ? Alignment.topLeft : Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact
                        ? NoteFlowLayout.compactPageMaxWidth
                        : NoteFlowLayout.editorMaxWidth,
                  ),
                  child: KeyedSubtree(
                    key: skeletonKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        LayoutBuilder(
                          builder:
                              (
                                BuildContext context,
                                BoxConstraints constraints,
                              ) {
                                if (constraints.maxWidth < 420) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const _NotesSkeletonBar(
                                        width: 120,
                                        height: 48,
                                      ),
                                      const SizedBox(
                                        height: NoteFlowSpacing.sm,
                                      ),
                                      const _NotesSkeletonBar(
                                        width: 112,
                                        height: 36,
                                        radius: NoteFlowRadius.input,
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  children: <Widget>[
                                    const Expanded(
                                      child: _NotesSkeletonBar(
                                        width: 180,
                                        height: 48,
                                      ),
                                    ),
                                    const SizedBox(width: NoteFlowSpacing.md),
                                    const _NotesSkeletonBar(
                                      width: 112,
                                      height: 36,
                                      radius: NoteFlowRadius.input,
                                    ),
                                  ],
                                );
                              },
                        ),
                        const SizedBox(height: NoteFlowSpacing.sm),
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: 5,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: NoteFlowSpacing.xs),
                            itemBuilder: (BuildContext context, int index) {
                              return _NotesWorkspaceLoadingRow(
                                key: ValueKey<String>(
                                  'notes-workspace-loading-row-$index',
                                ),
                                tokens: tokens,
                              );
                            },
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
      ),
    );
  }
}

final class _NotesWorkspaceLoadingRow extends StatelessWidget {
  const _NotesWorkspaceLoadingRow({super.key, required this.tokens});

  final NoteFlowUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: <Widget>[
          _NotesSkeletonBar(width: 20, height: 20, color: tokens.subtleSurface),
          const SizedBox(width: NoteFlowSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.5,
                  child: _NotesSkeletonBar(
                    height: 12,
                    color: tokens.subtleSurface,
                  ),
                ),
                const SizedBox(height: NoteFlowSpacing.xs),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.82,
                  child: _NotesSkeletonBar(
                    height: 10,
                    color: tokens.subtleSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _NotesSkeletonBar extends StatelessWidget {
  const _NotesSkeletonBar({
    required this.height,
    this.width,
    this.color,
    this.radius = NoteFlowRadius.row,
  });

  final double? width;
  final double height;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? tokens.subtleSurface,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
