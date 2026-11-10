import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';
import 'nested_block_commands.dart';
import 'selection_formatting_controller.dart';
import 'slash_command_controller.dart';
import 'table_navigation.dart';
import 'editor_clipboard.dart';

List<engine.CommandShortcutEvent> richEditorShortcuts(
  RichEditorAdapter adapter,
  SlashCommandController slash,
) => [
  for (final command in ['arrow down', 'arrow up', 'enter', 'escape'])
    engine.CommandShortcutEvent(
      key: 'm09 $command',
      command: command,
      getDescription: () => command,
      handler: (_) {
        if (adapter.composing) return KeyEventResult.ignored;
        if (command == 'enter' && !slash.visible && adapter.editable) {
          final selection = adapter.editor.selection;
          if (selection?.isCollapsed == true) {
            final node = adapter.editor.document.nodeAtPath(
              selection!.start.path,
            );
            if (node?.type == 'm09_toggle' &&
                node?.delta != null &&
                selection.start.offset == node!.delta!.length) {
              unawaited(NestedBlockCommands(adapter).addChild(node));
              return KeyEventResult.handled;
            }
          }
        }
        if (!slash.visible) return KeyEventResult.ignored;
        if (command == 'escape') {
          slash.close(cancel: true);
        } else if (command == 'enter') {
          if (slash.choices.isNotEmpty) {
            unawaited(slash.choose(slash.choices[slash.selected]));
          }
        } else {
          slash.move(command == 'arrow down' ? 1 : -1);
        }
        return KeyEventResult.handled;
      },
    ),
  for (final binding in const {
    'ctrl+b': 'bold',
    'ctrl+i': 'italic',
    'ctrl+u': 'underline',
    'ctrl+shift+s': 'strikethrough',
    'ctrl+e': 'code',
  }.entries)
    engine.CommandShortcutEvent(
      key: 'm09 ${binding.value}',
      command: binding.key,
      macOSCommand: binding.key.replaceFirst('ctrl', 'cmd'),
      getDescription: () => binding.value,
      handler: (_) {
        final snapshot = adapter.capture();
        if (snapshot != null) {
          unawaited(
            SelectionFormattingController(adapter)
                .toggle(snapshot, binding.value),
          );
        }
        return KeyEventResult.handled;
      },
    ),
  ...tableNavigationShortcuts,
  ...EditorClipboard(adapter).shortcuts,
  ...engine.standardCommandShortcutEvents.where(
    (event) => !{
      ...engine.toggleMarkdownCommands,
      engine.toggleHighlightCommand,
      engine.showLinkMenuCommand,
      ...engine.pasteCommands,
      engine.copyCommand,
      engine.cutCommand,
    }.contains(event),
  ),
];
