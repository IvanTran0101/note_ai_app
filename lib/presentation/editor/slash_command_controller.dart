import 'package:flutter/foundation.dart';

import 'basic_block_commands.dart';
import 'block_search.dart';
import 'rich_editor_adapter.dart';

/// Menu state is ephemeral. Esc cancels without deleting the literal slash.
final class SlashCommandController extends ChangeNotifier {
  SlashCommandController(this.adapter) {
    adapter.addListener(refresh);
  }
  final RichEditorAdapter adapter;
  RichSelectionSnapshot? snapshot;
  int? slashStart;
  String query = '', _suppressed = '';
  int selected = 0;
  bool touchOpen = false;
  bool get visible => snapshot != null;
  List<BasicBlockChoice> get choices => [
    for (var i = 0; i < basicBlockChoices.length; i++)
      if (foldBlockSearch(
        '${basicBlockChoices[i].label} '
        '${basicBlockChoices[i].alias} ${vietnameseBlockAliases[i]}',
      ).contains(foldBlockSearch(query)))
        basicBlockChoices[i],
    for (final choice in mediaBlockChoices)
      if (foldBlockSearch('${choice.label} ${choice.alias} tệp đính kèm')
          .contains(foldBlockSearch(query)))
        choice,
  ];
  String get _signature =>
      '${adapter.revision}:${adapter.editor.selection?.toJson()}:$query';
  void refresh() {
    if (snapshot != null && (touchOpen || adapter.editor.selection == null)) {
      if (!adapter.accepts(snapshot!, popupOwnsFocus: true)) close();
      return;
    }
    final current = adapter.capture(range: false);
    if (current == null || !current.selection.isCollapsed) {
      close();
      return;
    }
    final node = adapter.editor.document.nodeAtPath(
      current.selection.start.path,
    );
    if (node?.delta == null || BasicBlockCommands(adapter).inCell(node!)) {
      close();
      return;
    }
    final text = node.delta!.toPlainText(),
        end = current.selection.start.offset;
    if (end < 0 || end > text.length) {
      close();
      return;
    }
    final match = RegExp(r'(?:^|\s)/([^\n\r/]{0,32})$')
        .firstMatch(text.substring(0, end));
    if (match == null) {
      close();
      return;
    }
    query = match[1]!.trim();
    if (_signature == _suppressed) return;
    slashStart = text.substring(0, end).lastIndexOf('/');
    snapshot = current;
    if (selected >= choices.length) selected = 0;
    notifyListeners();
  }

  void openTouch() {
    final current = adapter.capture(range: false);
    if (current == null) return;
    final node = adapter.editor.document.nodeAtPath(
      current.selection.start.path,
    );
    if (node == null || BasicBlockCommands(adapter).inCell(node)) return;
    touchOpen = true;
    query = '';
    selected = 0;
    slashStart = null;
    snapshot = current;
    adapter.setMenuInput(kIsWeb);
    notifyListeners();
  }

  void move(int amount) {
    if (choices.isEmpty) return;
    selected = (selected + amount) % choices.length;
    notifyListeners();
  }

  void filter(String value) {
    final current = snapshot;
    if (!touchOpen ||
        current == null ||
        !adapter.accepts(current, popupOwnsFocus: true)) {
      return;
    }
    query = value;
    selected = 0;
    notifyListeners();
  }

  Future<bool> choose(BasicBlockChoice choice) async {
    final captured = snapshot;
    if (captured == null) return false;
    final start = slashStart;
    close();
    return BasicBlockCommands(adapter)
        .choose(choice, captured, slashStart: start, popupOwnsFocus: true);
  }

  void close({bool cancel = false}) {
    if (cancel) _suppressed = _signature;
    if (!visible) return;
    snapshot = null;
    touchOpen = false;
    slashStart = null;
    query = '';
    selected = 0;
    adapter.setMenuInput(false);
    notifyListeners();
  }

  @override
  void dispose() {
    adapter.removeListener(refresh);
    adapter.setMenuInput(false);
    super.dispose();
  }
}
