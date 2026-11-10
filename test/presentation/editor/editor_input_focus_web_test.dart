@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:note_ai_app/presentation/editor/editor_input_focus.dart';

void main() {
  web.HTMLTextAreaElement field() {
    final node = web.HTMLTextAreaElement()
      ..setAttribute('aria-label', 'Text block');
    web.document.body!.append(node);
    addTearDown(() => node.remove());
    node.focus();
    return node;
  }

  test('restores only the captured connected editor field', () {
    final node = field();
    final restore = captureEditorInputFocus();
    expect(restore, isNotNull);
    node.blur();
    var reconnects = 0;
    restore!(() => reconnects++, false);
    expect(web.document.activeElement, node);
    expect(reconnects, 1);
  });

  test('does not steal another field or reconnect a removed block', () {
    final node = field();
    final restore = captureEditorInputFocus()!;
    final other = field();
    var reconnects = 0;
    restore(() => reconnects++, true);
    expect(web.document.activeElement, other);
    expect(reconnects, 0);
    node.remove();
    other.blur();
    restore(() => reconnects++, true);
    expect(reconnects, 0);
  });

  test('a menu transition replays native focus on the same active field', () {
    final node = field();
    final restore = captureEditorInputFocus()!;
    var reconnects = 0;
    restore(() => reconnects++, false);
    expect(reconnects, 0);
    restore(() => reconnects++, true);
    expect(web.document.activeElement, node);
    expect(reconnects, 1);
  });
}
