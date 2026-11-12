import 'package:flutter/material.dart';

/// A short catalog stays compact while a large/scaled catalog remains lazy.
double labelChooserBodyHeight(BuildContext context, int count) {
  final maximum = labelDialogBodyHeight(context, .4, minimum: 120);
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  final preferred = (count == 0 ? 1 : count) * 56 * scale;
  return preferred.clamp(48.0, maximum).toDouble();
}

/// Bounds dialog list content around safe areas, the IME, and text scaling.
double labelDialogBodyHeight(
  BuildContext context,
  double preferredFraction, {
  required double minimum,
}) {
  final media = MediaQuery.of(context);
  final safeHeight =
      (media.size.height - media.padding.vertical - media.viewInsets.vertical)
          .clamp(0.0, media.size.height)
          .toDouble();
  final textScale = (media.textScaler.scale(16) / 16)
      .clamp(1.0, 3.0)
      .toDouble();
  // Reserve the title, actions, and dialog inset before sizing the list.
  final reservedHeight = 120 * textScale + 80;
  final available = (safeHeight - reservedHeight)
      .clamp(0.0, safeHeight)
      .toDouble();
  final preferred = media.size.height * preferredFraction;
  final bounded = preferred < available ? preferred : available;
  // The outer AlertDialog scrolls if even this minimum cannot fit.
  return bounded < minimum ? minimum : bounded;
}
