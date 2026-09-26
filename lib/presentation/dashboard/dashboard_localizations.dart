import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Presentation copy for the Dashboard surface in English and Vietnamese.
final class DashboardCopy {
  const DashboardCopy._(this._isVietnamese);

  /// Resolves the copy registered for the current locale.
  static DashboardCopy of(BuildContext context) {
    final DashboardCopy? copy = Localizations.of<DashboardCopy>(
      context,
      DashboardCopy,
    );
    if (copy != null) {
      return copy;
    }
    final Locale? locale = Localizations.maybeLocaleOf(context);
    return DashboardCopy._(locale?.languageCode == 'vi');
  }

  /// Delegate that makes Dashboard copy available through Localizations.
  static const LocalizationsDelegate<DashboardCopy> delegate =
      _DashboardCopyLocalizationsDelegate();

  final bool _isVietnamese;

  String get title => _isVietnamese ? 'Trang chủ' : 'Home';
  String get workspaceLabel => 'NoteFlow';
  String get workspaceHint => _isVietnamese
      ? 'Lưu ý tưởng, sắp xếp công việc và để AI tổng hợp phần quan trọng.'
      : 'Capture ideas, organize work, and let AI surface what matters.';
  String get recentlyUpdated =>
      _isVietnamese ? 'Cập nhật gần đây' : 'Recently updated';
  String get recents => _isVietnamese ? 'Gần đây' : 'Recents';
  String get allNotes => _isVietnamese ? 'Tất cả ghi chú' : 'All notes';
  String get today => _isVietnamese ? 'Hôm nay' : 'Today';
  String get yesterday => _isVietnamese ? 'Hôm qua' : 'Yesterday';
  String get results => _isVietnamese ? 'Kết quả' : 'Results';
  String notesCount(int count) => _isVietnamese
      ? '$count ghi chú'
      : '$count ${count == 1 ? 'note' : 'notes'}';

  /// Alias used by Dashboard widgets and their contract tests.
  String noteCount(int count) => notesCount(count);
  String get search => _isVietnamese ? 'Tìm kiếm' : 'Search';
  String get closeSearch => _isVietnamese ? 'Đóng tìm kiếm' : 'Close search';
  String get searchNotes => _isVietnamese ? 'Tìm kiếm ghi chú' : 'Search notes';
  String get sort => _isVietnamese ? 'Sắp xếp' : 'Sort';
  String get sortUpdated => _isVietnamese ? 'Cập nhật' : 'Updated';
  String get sortCreated => _isVietnamese ? 'Tạo lúc' : 'Created';
  String get list => _isVietnamese ? 'Danh sách' : 'List';
  String get grid => _isVietnamese ? 'Lưới' : 'Grid';
  String get newNote => _isVietnamese ? 'Ghi chú mới' : 'New note';
  String get noNotes => _isVietnamese ? 'Chưa có ghi chú' : 'No notes yet';
  String get createFirstNote =>
      _isVietnamese ? 'Tạo ghi chú đầu tiên' : 'Create your first note';
  String get loadingNotes =>
      _isVietnamese ? 'Đang tải ghi chú' : 'Loading notes';
  String get loadError => _isVietnamese
      ? 'Không thể tải ghi chú. Vui lòng thử lại.'
      : 'Couldn’t load notes. Please try again.';
  String get storageUnavailable => _isVietnamese
      ? 'Phiên bản Web này không hỗ trợ tải hoặc lưu ghi chú. Hãy dùng ứng dụng đã cài đặt để tiếp tục.'
      : 'This Web build cannot load or save notes. Use the installed app to continue.';
  String get retry => _isVietnamese ? 'Thử lại' : 'Retry';
  String get noMatches =>
      _isVietnamese ? 'Không tìm thấy ghi chú phù hợp' : 'No matching notes';
  String get clearSearch => _isVietnamese ? 'Xóa tìm kiếm' : 'Clear search';
  String get settings => _isVietnamese ? 'Cài đặt' : 'Settings';
  String get diagnostics => _isVietnamese ? 'Chẩn đoán' : 'Diagnostics';
  String get updatedAt => _isVietnamese ? 'Cập nhật' : 'Updated';
  String get untitled => _isVietnamese ? '(Chưa đặt tên)' : '(Untitled)';
  String get noContent => _isVietnamese ? 'Không có nội dung' : 'No content';

  String updatedOn(String date) =>
      _isVietnamese ? '$updatedAt $date' : '$updatedAt $date';

  String noteSemantics({required String title, required String preview}) {
    return _isVietnamese ? 'Ghi chú $title. $preview' : 'Note $title. $preview';
  }
}

final class _DashboardCopyLocalizationsDelegate
    extends LocalizationsDelegate<DashboardCopy> {
  const _DashboardCopyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<DashboardCopy> load(Locale locale) => SynchronousFuture<DashboardCopy>(
    DashboardCopy._(locale.languageCode == 'vi'),
  );

  @override
  bool shouldReload(_DashboardCopyLocalizationsDelegate old) => false;
}
