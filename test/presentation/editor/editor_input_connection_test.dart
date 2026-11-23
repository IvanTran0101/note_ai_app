import 'package:appflowy_editor/src/editor/editor_component/service/ime/non_delta_input_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

NonDeltaTextInputService _client() => NonDeltaTextInputService(
  onInsert: (_) async => true,
  onDelete: (_) async => true,
  onReplace: (_) async => true,
  onNonTextUpdate: (_) async => true,
  onPerformAction: (_) async {},
);

void main() {
  testWidgets('unchanged editor value reconnects after another input client', (
    tester,
  ) async {
    final editor = _client(), title = _client();
    addTearDown(editor.close);
    addTearDown(title.close);
    const value = TextEditingValue(
      text: 'body',
      selection: TextSelection.collapsed(offset: 4),
    );
    final configuration = TextInputConfiguration(viewId: tester.view.viewId);
    editor.attach(value, configuration);
    expect(editor.attached, isTrue);
    final formatted = editor.currentTextEditingValue;
    title.attach(value, configuration);
    expect(editor.attached, isFalse);
    editor.attach(value, configuration);
    expect(editor.attached, isTrue);
    expect(title.attached, isFalse);
    expect(editor.currentTextEditingValue, formatted);
  });
}
