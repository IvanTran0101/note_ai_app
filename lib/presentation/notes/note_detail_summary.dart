import 'package:flutter/material.dart';

import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';

/// Keeps the AI result near the top of the note and lets it slide in/out.
final class NoteDetailSummary extends StatefulWidget {
  const NoteDetailSummary({
    super.key,
    required this.copy,
    required this.hasSavedNote,
    required this.summary,
    required this.isStale,
    this.isSummarizing = false,
    this.onCopy,
    this.onRegenerate,
    this.copyLabel,
    this.regenerateLabel,
  });

  final NoteDetailCopy copy;
  final bool hasSavedNote;
  final String? summary;
  final bool isStale;
  final bool isSummarizing;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;
  final String? copyLabel;
  final String? regenerateLabel;

  @override
  State<NoteDetailSummary> createState() => _NoteDetailSummaryState();
}

final class _NoteDetailSummaryState extends State<NoteDetailSummary> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.isSummarizing) {
      // The actual note content is animated by NoteDetailEditorForm.
      return const SizedBox.shrink();
    }

    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final String? value = widget.summary;
    if (value == null) {
      if (!widget.hasSavedNote) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: NoteFlowSpacing.xl),
        child: Text(
          widget.copy.noSummary,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: NoteFlowMotion.duration(context),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (Widget? current, List<Widget> outgoing) => Stack(
        alignment: Alignment.topLeft,
        children: <Widget>[
          for (final Widget previous in outgoing)
            ExcludeFocus(
              child: ExcludeSemantics(child: IgnorePointer(child: previous)),
            ),
          ?current,
        ],
      ),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final Animation<Offset> position = Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: SlideTransition(
            position: position,
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: _expanded
          ? _buildCard(context, tokens, value)
          : _buildPeek(context, tokens),
    );
  }

  Widget _buildCard(
    BuildContext context,
    NoteFlowUiTokens tokens,
    String value,
  ) {
    return Card(
      key: const ValueKey<String>('note-detail-summary'),
      margin: const EdgeInsets.only(top: NoteFlowSpacing.xl),
      color: tokens.subtleSurface,
      child: Padding(
        padding: const EdgeInsets.all(NoteFlowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeading(context, tokens),
            if (widget.isStale) ...<Widget>[
              const SizedBox(height: NoteFlowSpacing.sm),
              Text(
                widget.copy.summaryStale,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: tokens.error),
              ),
            ],
            const SizedBox(height: NoteFlowSpacing.md),
            _SummaryTypewriterText(
              key: ValueKey<String>('summary-text-$value'),
              text: value,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.textPrimary, height: 1.5),
            ),
            if (widget.onCopy != null ||
                widget.onRegenerate != null) ...<Widget>[
              const SizedBox(height: NoteFlowSpacing.md),
              Wrap(
                spacing: NoteFlowSpacing.sm,
                runSpacing: NoteFlowSpacing.sm,
                children: <Widget>[
                  if (widget.onCopy != null && widget.copyLabel != null)
                    TextButton.icon(
                      key: const ValueKey<String>('note-detail-copy-summary'),
                      onPressed: widget.onCopy,
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: Text(widget.copyLabel!),
                    ),
                  if (widget.onRegenerate != null &&
                      widget.regenerateLabel != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>(
                        'note-detail-regenerate-summary',
                      ),
                      onPressed: widget.onRegenerate,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(widget.regenerateLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPeek(BuildContext context, NoteFlowUiTokens tokens) {
    return Padding(
      padding: const EdgeInsets.only(top: NoteFlowSpacing.xl),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey<String>('note-detail-summary-toggle'),
          onPressed: () => setState(() => _expanded = true),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(widget.copy.showSummary),
          style: OutlinedButton.styleFrom(
            foregroundColor: tokens.textSecondary,
            side: BorderSide(color: tokens.divider),
          ),
        ),
      ),
    );
  }

  Widget _buildHeading(BuildContext context, NoteFlowUiTokens tokens) {
    return Row(
      children: <Widget>[
        Icon(Icons.auto_awesome_outlined, size: 16, color: tokens.textMuted),
        const SizedBox(width: NoteFlowSpacing.sm),
        Expanded(
          child: Text(
            widget.copy.summary,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: tokens.textSecondary,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey<String>('note-detail-summary-toggle'),
          tooltip: widget.copy.hideSummary,
          onPressed: () => setState(() => _expanded = false),
          icon: const Icon(Icons.chevron_left, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// Reveals the finished summary one word at a time.
final class _SummaryTypewriterText extends StatefulWidget {
  const _SummaryTypewriterText({
    super.key,
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  State<_SummaryTypewriterText> createState() => _SummaryTypewriterTextState();
}

final class _SummaryTypewriterTextState extends State<_SummaryTypewriterText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<String> _tokens;

  @override
  void initState() {
    super.initState();
    _tokens = _wordTokens(widget.text);
    _createController();
  }

  void _createController() {
    final int milliseconds = (450 + (_tokens.length * 38)).clamp(450, 1800);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: milliseconds),
    )..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _SummaryTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) {
      return;
    }
    _controller.dispose();
    _tokens = _wordTokens(widget.text);
    _createController();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final int visibleCount = (_controller.value * _tokens.length).ceil();
        final String visibleText = _tokens.take(visibleCount).join();
        return Semantics(
          liveRegion: true,
          label: widget.text,
          child: SelectableText(
            visibleText,
            key: const ValueKey<String>('note-detail-summary-text'),
            style: widget.style,
          ),
        );
      },
    );
  }

  static List<String> _wordTokens(String text) {
    return RegExp(r'\S+\s*')
        .allMatches(text)
        .map((RegExpMatch match) => match.group(0)!)
        .toList(growable: false);
  }
}
