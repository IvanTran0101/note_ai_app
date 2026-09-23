import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Presentation-only copy helper for the workspace shell, backed by a
/// [LocalizationsDelegate] so it follows the locale resolved by MaterialApp
/// (en / vi).
///
/// The shell owns no business copy; this class only supplies the navigation
/// labels and the workspace title. The root composition registers
/// [WorkspaceCopy.delegate] alongside the other app delegates.
final class WorkspaceCopy {
  const WorkspaceCopy._(this._isVietnamese);

  /// Resolves the [WorkspaceCopy] registered for the current locale.
  ///
  /// Falls back to reading the ambient locale when no delegate is registered
  /// (widget tests, previews), so the shell stays usable everywhere.
  static WorkspaceCopy of(BuildContext context) {
    final WorkspaceCopy? copy = Localizations.of<WorkspaceCopy>(
      context,
      WorkspaceCopy,
    );
    if (copy != null) {
      return copy;
    }
    final Locale? locale = Localizations.maybeLocaleOf(context);
    return WorkspaceCopy._(locale?.languageCode == 'vi');
  }

  /// Delegate that makes [WorkspaceCopy] available through `Localizations`.
  static const LocalizationsDelegate<WorkspaceCopy> delegate =
      _WorkspaceCopyLocalizationsDelegate();

  final bool _isVietnamese;

  /// Label for the Dashboard destination.
  String get dashboard => _isVietnamese ? 'Trang chủ' : 'Home';

  /// Label for the Notes destination.
  String get notes => _isVietnamese ? 'Ghi chú' : 'Notes';

  /// Visible title for the expanded workspace sidebar.
  String get workspaceTitle => 'NoteFlow';

  /// Visible section for the two existing top-level destinations.
  String get pagesSection => _isVietnamese ? 'Trang' : 'Pages';

  /// Existing Dashboard search action.
  String get search => _isVietnamese ? 'Tìm kiếm' : 'Search';

  /// Existing create-note action.
  String get newNote => _isVietnamese ? 'Ghi chú mới' : 'New note';

  /// Accessible label describing the shell's primary navigation region.
  String get navigationLabel =>
      _isVietnamese ? 'Điều hướng chính' : 'Primary navigation';

  /// Tooltip for the compact navigation menu button.
  String get openMenu => _isVietnamese ? 'Mở điều hướng' : 'Open navigation';

  /// Tooltip for the sidebar collapse toggle.
  String get collapseSidebar => _isVietnamese ? 'Ẩn thanh bên' : 'Hide sidebar';

  /// Tooltip for the control that reopens the hidden sidebar.
  String get expandSidebar => _isVietnamese ? 'Mở thanh bên' : 'Open sidebar';

  /// Tooltip for the appearance/settings action.
  String get settings => _isVietnamese ? 'Cài đặt' : 'Settings';

  /// Tooltip for the local-AI diagnostics action.
  String get diagnostics => _isVietnamese ? 'Chẩn đoán' : 'Diagnostics';
}

/// Alias matching the file name; [WorkspaceCopy] remains the canonical name.
typedef WorkspaceLocalizations = WorkspaceCopy;

final class _WorkspaceCopyLocalizationsDelegate
    extends LocalizationsDelegate<WorkspaceCopy> {
  const _WorkspaceCopyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<WorkspaceCopy> load(Locale locale) => SynchronousFuture<WorkspaceCopy>(
    WorkspaceCopy._(locale.languageCode == 'vi'),
  );

  @override
  bool shouldReload(_WorkspaceCopyLocalizationsDelegate old) => false;
}
