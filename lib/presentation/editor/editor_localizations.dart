import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

/// The copied engine has no Vietnamese catalog. NoteFlow's own block menus,
/// toolbar and dialogs use editorText; engine internals retain English fallback
/// while the surrounding app and Material controls keep their selected locale.
final class NoteFlowEditorLocalizationsDelegate
    extends LocalizationsDelegate<AppFlowyEditorLocalizations> {
  const NoteFlowEditorLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<AppFlowyEditorLocalizations> load(Locale locale) =>
      AppFlowyEditorLocalizations.delegate.load(
        AppFlowyEditorLocalizations.delegate.isSupported(locale)
            ? locale
            : const Locale('en'),
      );

  @override
  bool shouldReload(NoteFlowEditorLocalizationsDelegate old) => false;
}
