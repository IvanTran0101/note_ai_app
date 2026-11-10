import 'package:flutter/material.dart';

/// Preserve the caller's actions while keeping touch targets at least 48dp.
final class NoteFlowSettingsAccountActions extends StatelessWidget {
  const NoteFlowSettingsAccountActions({super.key, required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ListTileTheme(
    data: ListTileTheme.of(context)
        .copyWith(minTileHeight: 48, visualDensity: VisualDensity.standard),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: actions,
    ),
  );
}
