import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'slash_command_controller.dart';

/// The + palette's query is temporary UI state, never document content.
final class BlockFilterInput extends StatefulWidget {
  const BlockFilterInput({super.key, required this.controller});
  final SlashCommandController controller;

  @override
  State<BlockFilterInput> createState() => _BlockFilterInputState();
}

final class _BlockFilterInputState extends State<BlockFilterInput> {
  late final text = TextEditingController(text: widget.controller.query);
  final focus = FocusNode(debugLabel: 'Block insertion query');
  bool _focusScheduled = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(_retainFocus);
    _retainFocus();
  }

  void _retainFocus() {
    if (focus.hasFocus || _focusScheduled) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        _focusScheduled = false;
        if (!mounted ||
            !widget.controller.visible ||
            !widget.controller.touchOpen ||
            !widget.controller.adapter.menuOwnsInput.value ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }
        focus.requestFocus();
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    text.dispose();
    focus.removeListener(_retainFocus);
    focus.dispose();
    super.dispose();
  }

  void _chooseSelected() {
    final menu = widget.controller;
    if (menu.choices.isNotEmpty) {
      unawaited(menu.choose(menu.choices[menu.selected]));
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (text.value.composing.isValid && !text.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final menu = widget.controller;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        menu.move(1);
      case LogicalKeyboardKey.arrowUp:
        menu.move(-1);
      case LogicalKeyboardKey.enter:
        _chooseSelected();
      case LogicalKeyboardKey.escape:
        menu.close(cancel: true);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _key,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: TextField(
        key: const ValueKey('block-insert-filter'),
        focusNode: focus,
        controller: text,
        onChanged: widget.controller.filter,
        onSubmitted: (_) => _chooseSelected(),
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: const InputDecoration(
          hintText: 'Type to filter…',
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ),
  );
}
