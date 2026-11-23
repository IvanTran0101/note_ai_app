import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../domain/notes/note_document.dart';
import 'rich_editor_adapter.dart';
import 'editor_popup_guard.dart';
import 'editor_copy.dart';

/// Validates before returning; Cancel and invalid input never mutate a note.
Future<String?> editorValueDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required String label,
  required void Function(String) validate,
  bool equation = false,
  RichEditorAdapter? adapter,
  RichSelectionSnapshot? snapshot,
}) {
  Widget build(BuildContext context) => _ValueDialog(
    title: title,
    initial: initial,
    label: label,
    validate: validate,
    equation: equation,
  );
  return adapter != null && snapshot != null
      ? guardedEditorDialog<String>(context, adapter, snapshot, build)
      : showDialog<String>(context: context, builder: build);
}

final class _ValueDialog extends StatefulWidget {
  const _ValueDialog({
    required this.title,
    required this.initial,
    required this.label,
    required this.validate,
    required this.equation,
  });
  final String title, initial, label;
  final void Function(String) validate;
  final bool equation;
  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

final class _ValueDialogState extends State<_ValueDialog> {
  late final text = TextEditingController(text: widget.initial);
  String? error;
  void check(String value) {
    try {
      widget.validate(value);
      error = null;
    } on Object {
      error = widget.equation
          ? 'Enter a valid equation (up to 512 characters).'
          : 'Enter a valid value.';
    }
    setState(() {});
  }

  void submit() {
    check(text.text.trim());
    if (error == null) Navigator.pop(context, text.text.trim());
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(editorText(context, widget.title)),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: text,
            autofocus: true,
            maxLines: widget.equation ? 3 : 1,
            decoration: InputDecoration(
              labelText: editorText(context, widget.label),
              errorText: error == null ? null : editorText(context, error!),
            ),
            onChanged: check,
            onSubmitted: (_) => submit(),
          ),
          if (widget.equation && text.text.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                text.text.trim(),
                onErrorFallback: (_) =>
                    Text(editorText(context, 'Invalid equation')),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(editorText(context, 'Cancel')),
      ),
      FilledButton(
        onPressed: submit,
        child: Text(editorText(context, 'Apply')),
      ),
    ],
  );
}

void validateEditorSize(String text) {
  final value = double.tryParse(text);
  if (value == null) throw ArgumentError('Invalid size');
  DocumentMarks(fontSize: value);
}

void validateEditorLink(String text) =>
    DocumentMarks(link: text.isEmpty ? null : text);
void validateEditorEquation(String text) {
  DocumentMath(text);
  if (Math.tex(text).parseError != null) {
    throw ArgumentError('Invalid equation syntax');
  }
}
