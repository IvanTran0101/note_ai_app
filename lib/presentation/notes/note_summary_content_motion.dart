import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

/// Gives the note text a gentle breathing effect while the AI reads it.
final class NoteSummaryContentMotion extends StatefulWidget {
  const NoteSummaryContentMotion({
    super.key,
    required this.active,
    required this.controller,
    required this.textStyle,
    required this.child,
  });

  final bool active;
  final TextEditingController controller;
  final TextStyle textStyle;
  final Widget child;

  @override
  State<NoteSummaryContentMotion> createState() =>
      _NoteSummaryContentMotionState();
}

final class _NoteSummaryContentMotionState
    extends State<NoteSummaryContentMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant NoteSummaryContentMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            child!,
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder:
                  (BuildContext context, TextEditingValue value, Widget? _) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final Color baseColor =
                        widget.textStyle.color ?? tokens.textPrimary;
                    final List<TextSpan> words = RegExp(r'\S+\s*')
                        .allMatches(value.text)
                        .toList(growable: false)
                        .asMap()
                        .entries
                        .map((MapEntry<int, RegExpMatch> entry) {
                          final double phase =
                              (_controller.value + (entry.key * 0.13)) % 1;
                          final double wave = phase < 0.5
                              ? phase * 2
                              : 2 - (phase * 2);
                          final double pulse = Curves.easeInOut.transform(wave);
                          return TextSpan(
                            text: entry.value.group(0),
                            style: widget.textStyle.copyWith(
                              color: baseColor.withAlpha(
                                140 + (pulse * 115).round(),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false);
                    return IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NoteFlowSpacing.sm,
                        ),
                        child: RichText(text: TextSpan(children: words)),
                      ),
                    );
                  },
            ),
          ],
        );
      },
    );
  }
}
