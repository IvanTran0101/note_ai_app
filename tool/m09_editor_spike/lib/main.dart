import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'container_block.dart';
import 'math_span.dart';
import 'proof_document.dart';
import 'accessible_builders.dart';
import 'table_navigation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  AppFlowyLogConfiguration()
    ..level = AppFlowyEditorLogLevel.off
    ..handler = null;
  runApp(const ProofApp());
}

class ProofApp extends StatelessWidget {
  const ProofApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'M09 engine proof',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const [
      AppFlowyEditorLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff37352f),
      useMaterial3: true,
    ),
    home: const ProofPage(),
  );
}

class ProofPage extends StatefulWidget {
  const ProofPage({super.key});
  @override
  State<ProofPage> createState() => _ProofPageState();
}

class _ProofPageState extends State<ProofPage> {
  late EditorState editor = EditorState(document: proofDocument());
  late EditorScrollController scroll = EditorScrollController(
    editorState: editor,
  );
  String receipt = 'Synthetic data only · 13 blocks';
  bool readOnly = false;
  final editorFocus = FocusNode(debugLabel: 'M09 proof editor');

  @override
  void dispose() {
    scroll.dispose();
    editor.dispose();
    editorFocus.dispose();
    super.dispose();
  }

  void _roundTrip() {
    final raw = editor.document.toJson();
    final next = Document.fromJson(jsonDecode(jsonEncode(raw)));
    final equal = jsonEncode(raw) == jsonEncode(next.toJson());
    setState(() => receipt = equal ? 'Round trip PASS' : 'Round trip FAIL');
  }

  Future<void> _size24() async {
    final selected = editor.selection;
    if (selected == null || selected.isCollapsed) {
      setState(() => receipt = 'Select text first');
      return;
    }
    await editor.formatDelta(selected, {'font_size': 24.0});
  }

  Widget _controls() => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(onPressed: _roundTrip, child: const Text('Round trip')),
        IconButton(
          tooltip: 'Undo',
          onPressed: readOnly ? null : editor.undoManager.undo,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Redo',
          onPressed: readOnly ? null : editor.undoManager.redo,
          icon: const Icon(Icons.redo),
        ),
        TextButton(
          onPressed: readOnly ? null : _size24,
          child: const Text('Size24'),
        ),
        FilterChip(
          label: const Text('Readonly'),
          selected: readOnly,
          onSelected: (value) => setState(() => readOnly = value),
        ),
        Text(receipt, key: const ValueKey('receipt')),
      ],
    ),
  );

  Widget _editor() {
    final body = AppFlowyEditor(
      editorState: editor,
      editorScrollController: scroll,
      editable: !readOnly,
      focusNode: editorFocus,
      commandShortcutEvents: [
        ...tableNavigationShortcuts,
        ...standardCommandShortcutEvents,
      ],
      editorStyle: const EditorStyle.desktop().copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textSpanDecorator: mathSpan,
      ),
      blockComponentBuilders: accessibleBuilders(
        {
          ...standardBlockComponentBuilderMap,
          QuoteBlockKeys.type: QuoteBlockComponentBuilder(),
          'm09_toggle': ContainerBlockBuilder(
            toggle: true,
            editable: !readOnly,
          ),
          'm09_callout': ContainerBlockBuilder(
            toggle: false,
            editable: !readOnly,
          ),
        },
        editor,
        editorFocus,
        !readOnly,
      ),
    );
    if (readOnly) return body;
    return FloatingToolbar(
      editorState: editor,
      editorScrollController: scroll,
      textDirection: TextDirection.ltr,
      items: markdownFormatItems,
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('M09 editor engine proof')),
    body: SafeArea(
      child: Column(
        children: [
          _controls(),
          Expanded(child: _editor()),
        ],
      ),
    ),
  );
}
