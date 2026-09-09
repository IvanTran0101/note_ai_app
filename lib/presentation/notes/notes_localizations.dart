import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Presentation-only copy helper for the Notes feature, backed by a
/// [LocalizationsDelegate] so it follows the locale resolved by MaterialApp
/// (en / vi).
final class NotesCopy {
  const NotesCopy._(this._isVietnamese);

  /// Resolves the [NotesCopy] registered for the current locale.
  ///
  /// Falls back to reading the ambient locale when no delegate is registered
  /// (widget tests, previews), so Notes remains usable everywhere.
  static NotesCopy of(BuildContext context) {
    final NotesCopy? copy = Localizations.of<NotesCopy>(context, NotesCopy);
    if (copy != null) {
      return copy;
    }
    final Locale? locale = Localizations.maybeLocaleOf(context);
    return NotesCopy._(locale?.languageCode == 'vi');
  }

  /// Delegate that makes [NotesCopy] available through `Localizations`.
  static const LocalizationsDelegate<NotesCopy> delegate =
      _NotesCopyLocalizationsDelegate();

  final bool _isVietnamese;

  String get title => _isVietnamese ? 'NoteFlow · Ghi chú' : 'NoteFlow · Notes';
  String get notes => _isVietnamese ? 'Ghi chú' : 'Notes';
  String get newNote => _isVietnamese ? 'Ghi chú mới' : 'New note';
  String get noNotes => _isVietnamese ? 'Chưa có ghi chú' : 'No notes yet';
  String get createFirstNote =>
      _isVietnamese ? 'Tạo ghi chú đầu tiên' : 'Create your first note';
  String get noContent => _isVietnamese ? 'Không có nội dung' : 'No content';
  String get untitled => _isVietnamese ? '(Chưa đặt tên)' : '(Untitled)';
  String get retry => _isVietnamese ? 'Thử lại' : 'Retry';
  String get loadingNotes =>
      _isVietnamese ? 'Đang tải ghi chú' : 'Loading notes';
  String get actionInProgress =>
      _isVietnamese ? 'Đang xử lý' : 'Action in progress';
  String get diagnostics => _isVietnamese ? 'Chẩn đoán' : 'Diagnostics';
  String get editor => _isVietnamese ? 'Trình soạn thảo' : 'Note editor';
  String get save => _isVietnamese ? 'Lưu ghi chú' : 'Save note';
  String get delete => _isVietnamese ? 'Xóa ghi chú' : 'Delete note';
  String get summarize => _isVietnamese ? 'Tóm tắt ghi chú' : 'Summarize note';
  String get summarizing => _isVietnamese ? 'Đang tóm tắt…' : 'Summarizing…';
  String get titleLabel => _isVietnamese ? 'Tiêu đề' : 'Title';
  String get contentLabel => _isVietnamese ? 'Nội dung' : 'Content';
  String get unsavedChanges => _isVietnamese
      ? 'Có thay đổi chưa lưu. Hãy lưu trước khi tóm tắt hoặc chuyển ghi chú.'
      : 'Unsaved changes. Save before summarizing or switching notes.';
  String get summary => _isVietnamese ? 'Tóm tắt' : 'Summary';
  String get deleted => _isVietnamese ? 'Đã xóa ghi chú.' : 'Note deleted.';
  String get undo => _isVietnamese ? 'Hoàn tác' : 'Undo';
  String get saved => _isVietnamese ? 'Đã lưu ghi chú.' : 'Note saved.';
  String get summarized => _isVietnamese ? 'Đã tạo tóm tắt.' : 'Summary ready.';
  String get loadError => _isVietnamese
      ? 'Không thể tải ghi chú. Vui lòng thử lại.'
      : 'Couldn’t load notes. Please try again.';
  String get saveError => _isVietnamese
      ? 'Không thể lưu ghi chú. Vui lòng thử lại.'
      : 'Couldn’t save the note. Please try again.';
  String get deleteError => _isVietnamese
      ? 'Không thể xóa ghi chú. Vui lòng thử lại.'
      : 'Couldn’t delete the note. Please try again.';
  String get summarizeError => _isVietnamese
      ? 'Không thể tạo tóm tắt. Vui lòng thử lại.'
      : 'Couldn’t create a summary. Please try again.';
  String get detailPrefix => _isVietnamese ? 'Chi tiết: ' : 'Details: ';
}

final class _NotesCopyLocalizationsDelegate
    extends LocalizationsDelegate<NotesCopy> {
  const _NotesCopyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<NotesCopy> load(Locale locale) =>
      SynchronousFuture<NotesCopy>(NotesCopy._(locale.languageCode == 'vi'));

  @override
  bool shouldReload(_NotesCopyLocalizationsDelegate old) => false;
}
