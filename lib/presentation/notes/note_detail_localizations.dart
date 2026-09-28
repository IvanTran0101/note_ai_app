import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Presentation-only copy for the dedicated Note Detail screen.
final class NoteDetailCopy {
  const NoteDetailCopy._(this._isVietnamese);

  static const LocalizationsDelegate<NoteDetailCopy> delegate =
      _NoteDetailCopyLocalizationsDelegate();

  static NoteDetailCopy of(BuildContext context) {
    final NoteDetailCopy? copy = Localizations.of<NoteDetailCopy>(
      context,
      NoteDetailCopy,
    );
    if (copy != null) {
      return copy;
    }
    final Locale? locale = Localizations.maybeLocaleOf(context);
    return NoteDetailCopy._(locale?.languageCode == 'vi');
  }

  final bool _isVietnamese;

  String get newNote => _isVietnamese ? 'Ghi chú mới' : 'New note';
  String get editNote => _isVietnamese ? 'Chỉnh sửa ghi chú' : 'Edit note';
  String pageBreadcrumb(String pageTitle) => pageTitle;
  String get back => _isVietnamese ? 'Quay lại' : 'Back';
  String get save => _isVietnamese ? 'Lưu' : 'Save';
  String get saving => _isVietnamese ? 'Đang lưu…' : 'Saving…';
  String get summarize => _isVietnamese ? 'Tóm tắt' : 'Summarize';
  String get summarizing => _isVietnamese ? 'Đang tóm tắt…' : 'Summarizing…';
  String get retry => _isVietnamese ? 'Thử lại' : 'Retry';
  String get copySummary => _isVietnamese ? 'Sao chép' : 'Copy';
  String get regenerate => _isVietnamese ? 'Tạo lại' : 'Regenerate';
  String get copied =>
      _isVietnamese ? 'Đã sao chép tóm tắt.' : 'Summary copied.';
  String get more => _isVietnamese ? 'Thêm' : 'More';
  String get delete => _isVietnamese ? 'Xóa' : 'Delete';
  String get titleLabel => _isVietnamese ? 'Tiêu đề' : 'Title';
  String get contentLabel => _isVietnamese ? 'Nội dung' : 'Content';
  String get summary => _isVietnamese ? 'Tóm tắt' : 'Summary';
  String get hideSummary => _isVietnamese ? 'Ẩn tóm tắt' : 'Hide summary';
  String get showSummary => _isVietnamese ? 'Hiện tóm tắt' : 'Show summary';
  String get summaryStale => _isVietnamese
      ? 'Tóm tắt đã cũ vì ghi chú đã thay đổi.'
      : 'This summary is out of date because the note changed.';
  String get saveBeforeSummary => _isVietnamese
      ? kIsWeb
            ? 'Phiên bản Web không hỗ trợ lưu ghi chú nên không thể tạo tóm tắt.'
            : 'Ghi chú sẽ được tạo tự động khi bạn nhập. Sau đó, bạn có thể tạo tóm tắt.'
      : kIsWeb
      ? 'Summaries are unavailable because this Web build cannot save notes.'
      : 'Your note is created automatically as you type. You can summarize it once it is created.';
  String get autoSaveHint => _isVietnamese
      ? kIsWeb
            ? 'Web không hỗ trợ lưu ghi chú'
            : 'Tự động lưu khi bạn nhập'
      : kIsWeb
      ? 'Saving unavailable on Web'
      : 'Saves automatically as you type';
  String get autoSavePending => _isVietnamese
      ? kIsWeb
            ? 'Thay đổi chưa được lưu trên Web'
            : 'Thay đổi sẽ được tự động lưu'
      : kIsWeb
      ? 'Changes are not saved on Web'
      : 'Changes will save automatically';
  String get persistenceUnavailable => _isVietnamese
      ? 'Phiên bản Web này không hỗ trợ lưu ghi chú. Thay đổi trong bản nháp sẽ mất khi bạn rời trang.'
      : 'This Web build cannot save notes. Changes in this draft will be lost when you leave.';
  String get savingUnavailable => _isVietnamese
      ? 'Web không hỗ trợ lưu ghi chú'
      : 'Saving unavailable on Web';
  String get noSummary => _isVietnamese
      ? 'Chưa có tóm tắt. Chọn Tóm tắt để tạo một bản.'
      : 'No summary yet. Select Summarize to create one.';
  String get unsavedChanges =>
      _isVietnamese ? 'Bạn có thay đổi chưa lưu.' : 'You have unsaved changes.';
  String get dirtyBackTitle => _isVietnamese
      ? 'Lưu thay đổi trước khi rời đi?'
      : 'Save changes before leaving?';
  String get dirtyBackMessage => _isVietnamese
      ? 'Thay đổi của bạn sẽ bị mất nếu bạn rời khỏi màn hình này.'
      : 'Your changes will be lost if you leave this screen.';
  String get cancel => _isVietnamese ? 'Hủy' : 'Cancel';
  String get discard => _isVietnamese ? 'Bỏ thay đổi' : 'Discard';
  String get deleteTitle => _isVietnamese ? 'Xóa ghi chú?' : 'Delete note?';
  String get deleteMessage => _isVietnamese
      ? 'Ghi chú này sẽ bị xóa khỏi thiết bị.'
      : 'This note will be deleted from this device.';
  String get deleted => _isVietnamese ? 'Đã xóa ghi chú.' : 'Note deleted.';
  String get saved => _isVietnamese ? 'Đã lưu ghi chú.' : 'Note saved.';
  String get summarized => _isVietnamese ? 'Đã tạo tóm tắt.' : 'Summary ready.';
  String get saveError => _isVietnamese
      ? 'Không thể lưu ghi chú. Vui lòng thử lại.'
      : 'Couldn’t save the note. Please try again.';
  String get deleteError => _isVietnamese
      ? 'Không thể xóa ghi chú. Vui lòng thử lại.'
      : 'Couldn’t delete the note. Please try again.';
  String get summarizeError => _isVietnamese
      ? 'Không thể tạo tóm tắt. Vui lòng thử lại.'
      : 'Couldn’t create a summary. Please try again.';
  String get actionInProgress =>
      _isVietnamese ? 'Đang xử lý ghi chú' : 'Note action in progress';
  String get detailError => _isVietnamese
      ? 'Đã xảy ra lỗi. Vui lòng thử lại.'
      : 'Something went wrong. Please try again.';
}

final class _NoteDetailCopyLocalizationsDelegate
    extends LocalizationsDelegate<NoteDetailCopy> {
  const _NoteDetailCopyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<NoteDetailCopy> load(Locale locale) =>
      SynchronousFuture<NoteDetailCopy>(
        NoteDetailCopy._(locale.languageCode == 'vi'),
      );

  @override
  bool shouldReload(_NoteDetailCopyLocalizationsDelegate old) => false;
}
