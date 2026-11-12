import 'package:web/web.dart' as web;

/// Flutter Web can detach/reinsert the same semantics ancestor when a popup
/// appears. The browser then drops its focused textarea without a blur() call.
/// Retain only that actual input for one frame; never search or focus a different
/// field, and never take focus from another control or a dialog.
/// A visibility transition can deactivate input handlers while leaving DOM
/// focus intact, so replay its native focus action once in that case.
void Function(void Function() reconnect, bool forceReconnect)?
captureEditorInputFocus() {
  final active = web.document.activeElement;
  if (active?.tagName != 'TEXTAREA' ||
      active?.getAttribute('aria-label') == null) {
    return null;
  }
  final field = active! as web.HTMLTextAreaElement;
  return (reconnect, forceReconnect) {
    if (!field.isConnected) return;
    if (web.document.activeElement == field) {
      if (forceReconnect) {
        field.blur();
        field.focus(web.FocusOptions(preventScroll: true));
        reconnect();
      }
      return;
    }
    final current = web.document.activeElement;
    if (current != web.document.body && current?.tagName != 'FLUTTER-VIEW') {
      return;
    }
    field.focus(web.FocusOptions(preventScroll: true));
    reconnect();
  };
}
