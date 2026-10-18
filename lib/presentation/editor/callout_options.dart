import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';

import '../../domain/notes/note_document.dart';
import 'callout_commands.dart';
import 'document_palette.dart';
import 'editor_popup_guard.dart';
import 'rich_editor_adapter.dart';
import 'rich_inline_codec.dart';
import 'editor_icon_button.dart';

Future<void> showCalloutOptions(
  BuildContext context,
  engine.Node node,
  RichEditorAdapter adapter,
) async {
  final command = CalloutCommands(adapter),
      snapshot = CalloutCommands(adapter).capture(node);
  if (snapshot == null) return;
  var icon = node.attributes['m09_icon'] as String? ?? '💡';
  var tone =
      RichInlineCodec.color(node.attributes['m09_tone']) ?? DocumentColor.gray;
  final chosen = await guardedEditorDialog<bool>(
    context,
    adapter,
    snapshot,
    (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Callout style'),
        scrollable: true,
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Icon'),
              Wrap(
                children: [
                  for (final value in [
                    '💡',
                    '📝',
                    '📌',
                    '⭐',
                    '✅',
                    '⚠️',
                    '💬',
                    '🎯',
                  ])
                    Semantics(
                      selected: value == icon,
                      child: EditorIconButton(
                        label: 'Use $value',
                        onPressed: () => update(() => icon = value),
                        selected: value == icon,
                        icon: Text(value, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Background'),
              Wrap(
                children: [
                  for (final value in DocumentColor.values)
                    Semantics(
                      selected: value == tone,
                      child: EditorIconButton(
                        label: value.name,
                        selected: value == tone,
                        onPressed: () => update(() => tone = value),
                        icon: Icon(
                          value == tone ? Icons.check_circle : Icons.circle,
                          color: DocumentPalette.text(
                            value,
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  );
  if (chosen == true) {
    await command.change(node, snapshot, icon: icon, tone: tone);
  }
}
