import 'package:flutter/material.dart';

import '../../domain/note_intelligence/rag_models.dart';
import '../common/note_flow_primitives.dart';
import '../notes/notes_theme_tokens.dart';
import 'rag_copy.dart';

/// The answered result of one question: untrusted answer text plus citations.
///
/// The answer and every citation field are rendered as plain, selectable text.
/// Nothing here is interpreted as markup, a URL, or a link, so answer/note text
/// can never navigate or execute. A citation button reports the exact
/// [RagSource] to [onOpenSource]; this card never validates or opens it itself.
final class RagAnswerCard extends StatelessWidget {
  const RagAnswerCard({
    super.key,
    required this.question,
    required this.answer,
    required this.sources,
    required this.openingSourceId,
    required this.sourceFailure,
    required this.onOpenSource,
  });

  /// The exact question that produced this answer.
  final String question;

  /// The answer text, rendered verbatim.
  final String answer;

  /// Approved citations of the displayed result.
  final List<RagSource> sources;

  /// The source id whose open is in flight, or null.
  final String? openingSourceId;

  /// The safe failure of the last refused source open, or null.
  final RagFailureCode? sourceFailure;

  /// Reports a citation open to the owner of the navigation contract.
  final void Function(RagSource source) onOpenSource;

  @override
  Widget build(BuildContext context) {
    final RagCopy copy = RagCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return NoteFlowSurface(
      tone: NoteFlowSurfaceTone.elevated,
      bordered: true,
      radius: NoteFlowRadius.card,
      padding: const EdgeInsets.all(NoteFlowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            copy.answerQuestionLabel,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: NoteFlowSpacing.xs),
          Text(
            question,
            style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: NoteFlowSpacing.md),
          SelectableText(
            answer,
            style: textTheme.bodyLarge?.copyWith(color: tokens.textPrimary),
          ),
          if (sources.isNotEmpty) ...<Widget>[
            const SizedBox(height: NoteFlowSpacing.lg),
            Text(
              copy.sourcesLabel,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: NoteFlowSpacing.sm),
            for (int index = 0; index < sources.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(height: NoteFlowSpacing.sm),
              _RagSourceButton(
                source: sources[index],
                busy: openingSourceId == sources[index].sourceId,
                enabled: openingSourceId == null,
                onPressed: () => onOpenSource(sources[index]),
              ),
            ],
          ],
          if (sourceFailure != null) ...<Widget>[
            const SizedBox(height: NoteFlowSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                copy.failureCodeMessage(sourceFailure!),
                key: const ValueKey<String>('rag-source-error'),
                style: textTheme.bodySmall?.copyWith(color: tokens.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled citation button: `[S#]`, title, and quote.
///
/// The whole row is the button, so the source stays reachable with a keyboard
/// and one tap at narrow widths. The visible label and the accessible name both
/// use the exact [RagSource.sourceId], never the citation's array position.
/// While its open is in flight it shows a semantic busy indicator and every
/// other citation button is disabled.
final class _RagSourceButton extends StatelessWidget {
  const _RagSourceButton({
    required this.source,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final RagSource source;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final RagCopy copy = RagCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: copy.sourceOpenSemantics(source.sourceId, source.title),
      child: OutlinedButton(
        key: ValueKey<String>('rag-source-${source.sourceId}'),
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: NoteFlowSpacing.md,
            vertical: NoteFlowSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NoteFlowRadius.row),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '[${source.sourceId}]',
              style: textTheme.labelMedium?.copyWith(
                color: tokens.link,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: NoteFlowSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    source.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: NoteFlowSpacing.xs),
                  Text(
                    source.quote,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NoteFlowSpacing.sm),
            if (busy)
              Semantics(
                label: copy.asking,
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.textMuted,
                  ),
                ),
              )
            else
              Icon(Icons.open_in_new, size: 16, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The normal `NOT_ENOUGH_CONTEXT` refusal of one question.
///
/// A refusal carries no answer and no citations, so it renders the question and
/// a safe, localized explanation instead of any model text.
final class RagNotEnoughContextCard extends StatelessWidget {
  const RagNotEnoughContextCard({super.key, required this.question});

  /// The exact question that produced the refusal.
  final String question;

  @override
  Widget build(BuildContext context) {
    final RagCopy copy = RagCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return NoteFlowSurface(
      tone: NoteFlowSurfaceTone.subtle,
      bordered: true,
      radius: NoteFlowRadius.card,
      padding: const EdgeInsets.all(NoteFlowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            copy.answerQuestionLabel,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: NoteFlowSpacing.xs),
          Text(
            question,
            style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: NoteFlowSpacing.md),
          Text(
            copy.notEnoughContextTitle,
            style: textTheme.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: NoteFlowSpacing.xs),
          Text(
            copy.notEnoughContextBody,
            style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
