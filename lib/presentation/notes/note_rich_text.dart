import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../domain/notes/note_body.dart';
import 'notes_theme_tokens.dart';

Color _textColor(String hex, BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final display = dark
      ? <String, String>{
              '#D32F2F': '#EF9A9A',
              '#2E7D32': '#A5D6A7',
              '#1565C0': '#90CAF9',
              '#8E24AA': '#CE93D8',
            }[hex.toUpperCase()] ??
            hex
      : hex;
  return Color(int.parse(display.substring(1), radix: 16) | 0xFF000000);
}

/// Bridges rich edits into the page's existing autosave/security controller.
final class NoteRichTextScope extends StatefulWidget {
  const NoteRichTextScope({
    super.key,
    required this.controller,
    this.focusNode,
    required this.readOnly,
    required this.child,
  });
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool readOnly;
  final Widget child;

  static NoteRichTextScopeState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RichTextScope>()?.state;

  @override
  State<NoteRichTextScope> createState() => NoteRichTextScopeState();
}

final class NoteRichTextScopeState extends State<NoteRichTextScope> {
  late final quill.QuillController editor;
  final ScrollController scroll = ScrollController();
  final ScrollController toolbarScroll = ScrollController();
  late final FocusNode focusNode = widget.focusNode ?? FocusNode();
  bool rich = false;
  bool _syncing = false;
  late String _stored;

  @override
  void initState() {
    super.initState();
    _stored = widget.controller.text;
    rich = NoteBody.delta(_stored) != null;
    editor = quill.QuillController(
      document: _document(_stored),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: widget.readOnly,
      config: const quill.QuillControllerConfig(
        // Text-only paste keeps binary data in the secured attachment flow.
        // ignore: experimental_member_use
        clipboardConfig: quill.QuillClipboardConfig(
          // ignore: experimental_member_use
          enableExternalRichPaste: false,
        ),
      ),
    )..addListener(_edited);
    widget.controller.addListener(_externalChanged);
  }

  quill.Document _document(String text) => quill.Document.fromJson(
    NoteBody.delta(text) ??
        <Map<String, dynamic>>[
          {'insert': '$text\n'},
        ],
  );

  @override
  void didUpdateWidget(NoteRichTextScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_externalChanged);
      widget.controller.addListener(_externalChanged);
      _stored = '\u0000';
      _externalChanged();
    }
    editor.readOnly = widget.readOnly;
  }

  void _externalChanged() {
    if (_syncing) return;
    if (_stored != widget.controller.text) {
      final wasPlain = !rich;
      _stored = widget.controller.text;
      _syncing = true;
      rich = NoteBody.delta(_stored) != null;
      final document = _document(_stored);
      if (wasPlain && !rich) {
        editor.compose(
          editor.document.toDelta().diff(document.toDelta()),
          widget.controller.selection.isValid
              ? widget.controller.selection
              : const TextSelection.collapsed(offset: 0),
          quill.ChangeSource.local,
        );
      } else {
        editor.document = document;
      }
      _syncing = false;
      if (mounted) setState(() {});
    }
    if (!rich && widget.controller.selection.isValid) {
      _syncing = true;
      editor.updateSelection(
        widget.controller.selection,
        quill.ChangeSource.local,
      );
      _syncing = false;
      if (mounted) setState(() {});
    }
  }

  void _edited() {
    if (_syncing || !rich) return;
    final next = NoteBody.encode(editor.document.toDelta().toJson());
    if (_stored != next) {
      _syncing = true;
      _stored = next;
      widget.controller.text = next;
      _syncing = false;
    }
    if (mounted) setState(() {});
  }

  void format(quill.Attribute attribute) {
    if (widget.readOnly) return;
    setState(() => rich = true);
    editor.formatSelection(attribute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.readOnly) focusNode.requestFocus();
    });
  }

  void history({required bool undo}) {
    if (widget.readOnly) return;
    setState(() => rich = true);
    undo ? editor.undo() : editor.redo();
    focusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChanged);
    editor.removeListener(_edited);
    editor.dispose();
    scroll.dispose();
    toolbarScroll.dispose();
    if (widget.focusNode == null) focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    delegates: const [quill.FlutterQuillLocalizations.delegate],
    child: _RichTextScope(state: this, child: widget.child),
  );
}

final class _RichTextScope extends InheritedWidget {
  const _RichTextScope({required this.state, required super.child});
  final NoteRichTextScopeState state;
  @override
  bool updateShouldNotify(_RichTextScope oldWidget) => true;
}

final class NoteRichBody extends StatelessWidget {
  const NoteRichBody({
    super.key,
    required this.plainEditor,
    required this.fieldKey,
    required this.placeholder,
    required this.style,
  });
  final Widget plainEditor;
  final Key fieldKey;
  final String placeholder;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final state = NoteRichTextScope.maybeOf(context);
    // Retain native plain-text editing until formatting is used.
    if (state == null || !state.rich) return plainEditor;
    return quill.QuillEditor(
      key: fieldKey,
      controller: state.editor,
      focusNode: state.focusNode,
      scrollController: state.scroll,
      config: quill.QuillEditorConfig(
        scrollable: false,
        minHeight: 96,
        placeholder: placeholder,
        padding: const EdgeInsets.symmetric(vertical: 8),
        customStyles: quill.DefaultStyles(
          paragraph: quill.DefaultTextBlockStyle(
            style,
            quill.HorizontalSpacing.zero,
            quill.VerticalSpacing.zero,
            quill.VerticalSpacing.zero,
            null,
          ),
        ),
        customStyleBuilder: (attribute) =>
            attribute.key == 'color' && attribute.value is String
            ? TextStyle(color: _textColor(attribute.value as String, context))
            : const TextStyle(),
      ),
    );
  }
}

final class NoteTextToolbar extends StatelessWidget {
  const NoteTextToolbar({super.key, this.attachmentAction});
  final Widget? attachmentAction;

  @override
  Widget build(BuildContext context) {
    final state = NoteRichTextScope.maybeOf(context);
    if (state == null) return const SizedBox.shrink();
    final tokens = NoteFlowUiTokens.of(context);
    final enabled = !state.widget.readOnly;
    final attributes = state.editor.getSelectionStyle().attributes;
    final vietnamese = Localizations.localeOf(context).languageCode == 'vi';
    String label(String en, String vi) => vietnamese ? vi : en;
    Widget toggle(String tooltip, IconData icon, quill.Attribute attribute) {
      final selected = attributes[attribute.key]?.value == attribute.value;
      return IconButton(
        tooltip: tooltip,
        isSelected: selected,
        onPressed: enabled
            ? () => state.format(
                selected ? quill.Attribute.clone(attribute, null) : attribute,
              )
            : null,
        icon: Icon(icon, size: 21),
      );
    }

    Widget menu<T>(
      String tooltip,
      IconData icon,
      List<PopupMenuEntry<T>> items,
      ValueChanged<T> onSelected,
    ) => PopupMenuButton<T>(
      requestFocus: true,
      tooltip: tooltip,
      enabled: enabled,
      popUpAnimationStyle: NoteFlowMotion.dialogStyle(context),
      icon: Icon(icon, size: 21),
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 280),
      onSelected: onSelected,
      itemBuilder: (_) => items,
    );

    return Material(
      key: const ValueKey('note-text-toolbar'),
      color: tokens.pageSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: tokens.divider),
            bottom: BorderSide(color: tokens.divider),
          ),
        ),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style:
                IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: tokens.textSecondary,
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ).copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? tokens.selectedSurface
                        : null,
                  ),
                ),
          ),
          child: Scrollbar(
            controller: state.toolbarScroll,
            thumbVisibility: true,
            thickness: 2,
            child: SingleChildScrollView(
              controller: state.toolbarScroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ?attachmentAction,
                  menu<int>(
                    label('Text style', 'Kiểu văn bản'),
                    Icons.text_fields,
                    [
                      for (final level in [0, 1, 2, 3])
                        CheckedPopupMenuItem(
                          value: level,
                          checked: (attributes['header']?.value ?? 0) == level,
                          child: Text(
                            level == 0
                                ? label('Text', 'Văn bản')
                                : label('Heading $level', 'Tiêu đề $level'),
                            style: TextStyle(
                              fontSize: level == 0 ? 16 : 23 - level * 2.0,
                              fontWeight: level == 0
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                    (value) => state.format(
                      quill.Attribute.clone(
                        quill.Attribute.h1,
                        value == 0 ? null : value,
                      ),
                    ),
                  ),
                  toggle(
                    label('Bold', 'Đậm'),
                    Icons.format_bold,
                    quill.Attribute.bold,
                  ),
                  toggle(
                    label('Italic', 'Nghiêng'),
                    Icons.format_italic,
                    quill.Attribute.italic,
                  ),
                  toggle(
                    label('Underline', 'Gạch chân'),
                    Icons.format_underlined,
                    quill.Attribute.underline,
                  ),
                  menu<String>(
                    label('Font size', 'Cỡ chữ'),
                    Icons.format_size,
                    [
                      for (final value in [
                        'Default',
                        '12',
                        '14',
                        '16',
                        '20',
                        '24',
                        '32',
                      ])
                        CheckedPopupMenuItem(
                          value: value,
                          checked:
                              (attributes['size']?.value ?? 'Default') == value,
                          child: Text(
                            value == 'Default'
                                ? label('Default', 'Mặc định')
                                : value,
                          ),
                        ),
                    ],
                    (value) => state.format(
                      quill.Attribute.clone(
                        quill.Attribute.size,
                        value == 'Default' ? null : value,
                      ),
                    ),
                  ),
                  menu<String>(
                    label('Text color', 'Màu chữ'),
                    Icons.format_color_text,
                    [
                      for (final entry in <String, String>{
                        'Default': label('Default', 'Mặc định'),
                        '#D32F2F': label('Red', 'Đỏ'),
                        '#2E7D32': label('Green', 'Xanh lá'),
                        '#1565C0': label('Blue', 'Xanh dương'),
                        '#8E24AA': label('Purple', 'Tím'),
                      }.entries)
                        CheckedPopupMenuItem(
                          value: entry.key,
                          checked:
                              (attributes['color']?.value ?? 'Default') ==
                              entry.key,
                          child: Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: entry.key == 'Default'
                                      ? tokens.textPrimary
                                      : _textColor(entry.key, context),
                                  border: Border.all(color: tokens.divider),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(entry.value),
                            ],
                          ),
                        ),
                    ],
                    (value) => state.format(
                      quill.Attribute.clone(
                        quill.Attribute.color,
                        value == 'Default' ? null : value,
                      ),
                    ),
                  ),
                  toggle(
                    label('Strikethrough', 'Gạch ngang'),
                    Icons.format_strikethrough,
                    quill.Attribute.strikeThrough,
                  ),
                  IconButton(
                    tooltip: label('Undo', 'Hoàn tác'),
                    onPressed: enabled && state.editor.hasUndo
                        ? () => state.history(undo: true)
                        : null,
                    icon: const Icon(Icons.undo, size: 21),
                  ),
                  IconButton(
                    tooltip: label('Redo', 'Làm lại'),
                    onPressed: enabled && state.editor.hasRedo
                        ? () => state.history(undo: false)
                        : null,
                    icon: const Icon(Icons.redo, size: 21),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
