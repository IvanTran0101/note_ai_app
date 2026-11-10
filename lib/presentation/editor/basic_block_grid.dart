import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'basic_block_commands.dart';

/// Native touch presentation of the existing Basic block choices.
final class BasicBlockGrid extends StatelessWidget {
  static const double topPadding = 4;
  static const double bottomPadding = 16;
  static const double rowSpacing = 4;

  const BasicBlockGrid({
    super.key,
    required this.choices,
    required this.controller,
    this.shrinkWrap = false,
    this.selectedChoice,
    required this.labelFor,
    required this.iconFor,
    required this.onChoose,
  });
  final List<BasicBlockChoice> choices;
  final ScrollController? controller;
  final bool shrinkWrap;
  final BasicBlockChoice? selectedChoice;
  final String Function(BasicBlockChoice) labelFor;
  final IconData Function(BasicBlockChoice) iconFor;
  final ValueChanged<BasicBlockChoice> onChoose;

  static int columnsFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 340 ||
          MediaQuery.textScalerOf(context).scale(14) > 21
      ? 1
      : 2;

  static double rowHeightFor(BuildContext context) => math
      .max(48.0, MediaQuery.textScalerOf(context).scale(14) * 2.4 + 12.0)
      .toDouble();

  @override
  Widget build(BuildContext context) => GridView.builder(
    controller: controller,
    shrinkWrap: shrinkWrap,
    physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
    padding: const EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnsFor(context),
      mainAxisExtent: rowHeightFor(context),
      mainAxisSpacing: rowSpacing,
      crossAxisSpacing: 10,
    ),
    itemCount: choices.length,
    itemBuilder: (context, index) => _tile(context, choices[index]),
  );

  Widget _tile(BuildContext context, BasicBlockChoice choice) {
    final colors = Theme.of(context).colorScheme;
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFAAAAAA)
        : const Color(0xFF686867);
    final selected = choice == selectedChoice;
    final highlight = colors.onSurface.withValues(alpha: 0.075);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChoose(choice),
        borderRadius: BorderRadius.circular(6),
        hoverColor: highlight,
        splashColor: highlight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? highlight : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    width: 28,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _glyph(choice, foreground),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    labelFor(choice),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glyph(BasicBlockChoice choice, Color foreground) {
    if (choice.level != null || choice == basicBlockChoices.first) {
      return Text(
        choice.level == null ? 'T' : 'H${_headingSubscripts[choice.level!]}',
        style: TextStyle(
          fontSize: 22,
          fontFamily: 'serif',
          fontWeight: FontWeight.w400,
          color: foreground,
        ),
      );
    }
    final color = foreground;
    if (choice.alias == 'toggle collapse') {
      return CustomPaint(
        size: const Size(24, 24),
        painter: _ToggleListGlyph(color),
      );
    }
    return Icon(
      choice.alias == 'todo task checkbox' ? Icons.checklist : iconFor(choice),
      size: 24,
      color: color,
    );
  }
}

const _headingSubscripts = ['', '₁', '₂', '₃', '₄'];

/// Two collapsed rows distinguish a toggle list from a single disclosure arrow.
final class _ToggleListGlyph extends CustomPainter {
  const _ToggleListGlyph(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final y in [7.0, 17.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(2, y - 4)
          ..lineTo(8, y)
          ..lineTo(2, y + 4)
          ..close(),
        paint,
      );
      canvas.drawLine(Offset(12, y), Offset(23, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ToggleListGlyph oldDelegate) =>
      oldDelegate.color != color;
}
