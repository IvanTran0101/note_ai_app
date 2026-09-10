import 'dart:async';

import 'package:flutter/material.dart';

/// Scrolls the content editor into view after the IME changes the viewport.
void scheduleNoteDetailContentFocus({
  required FocusNode focusNode,
  required GlobalKey fieldKey,
}) {
  if (!focusNode.hasFocus) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final BuildContext? fieldContext = fieldKey.currentContext;
    if (fieldContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          fieldContext,
          alignment: 0.22,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    }
  });
}
