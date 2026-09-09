import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import '../../application/note_intelligence/model_provisioning/model_provisioning_state.dart';

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

  String get provisioningStatus =>
      _isVietnamese ? 'Trạng thái thiết lập mô hình' : 'Model setup status';
  String get provisioningModel => _isVietnamese ? 'Mô hình' : 'Model';
  String get provisioningDownloadHint => _isVietnamese
      ? 'Mô hình sẽ được tải một lần vào bộ nhớ riêng của ứng dụng. Nên dùng Wi-Fi.'
      : 'The model is downloaded once into app storage. Wi-Fi is recommended.';
  String get provisioningDownloaded => _isVietnamese ? 'Đã tải' : 'Downloaded';
  String get provisioningRetry => _isVietnamese ? 'Thử tải lại' : 'Retry setup';
  String get provisioningNoDetail => _isVietnamese
      ? 'Vui lòng thử lại hoặc mở Chẩn đoán.'
      : 'Please try again or open Diagnostics.';

  String provisioningPhase(ModelProvisioningPhase phase) {
    return switch (phase) {
      ModelProvisioningPhase.idle => _isVietnamese ? 'Sẵn sàng' : 'Ready',
      ModelProvisioningPhase.detectingDevice =>
        _isVietnamese ? 'Đang kiểm tra thiết bị…' : 'Checking device…',
      ModelProvisioningPhase.selectingModel =>
        _isVietnamese
            ? 'Đang chọn mô hình phù hợp…'
            : 'Selecting a compatible model…',
      ModelProvisioningPhase.checkingExistingModel =>
        _isVietnamese
            ? 'Đang kiểm tra mô hình đã có…'
            : 'Checking for an existing model…',
      ModelProvisioningPhase.downloading =>
        _isVietnamese ? 'Đang tải mô hình…' : 'Downloading model…',
      ModelProvisioningPhase.verifying =>
        _isVietnamese ? 'Đang xác minh mô hình…' : 'Verifying model…',
      ModelProvisioningPhase.committing =>
        _isVietnamese ? 'Đang lưu mô hình…' : 'Saving model…',
      ModelProvisioningPhase.artifactReady =>
        _isVietnamese ? 'Mô hình đã sẵn sàng…' : 'Model artifact ready…',
      ModelProvisioningPhase.loadingRuntime =>
        _isVietnamese ? 'Đang khởi động AI cục bộ…' : 'Starting local AI…',
      ModelProvisioningPhase.ready =>
        _isVietnamese ? 'AI cục bộ đã sẵn sàng' : 'Local AI is ready',
      ModelProvisioningPhase.failed =>
        _isVietnamese ? 'Thiết lập mô hình thất bại' : 'Model setup failed',
    };
  }

  String provisioningFailure(ModelProvisioningFailureCode code) {
    return switch (code) {
      ModelProvisioningFailureCode.hardwareDetectionFailed =>
        _isVietnamese
            ? 'Không thể đọc thông tin thiết bị.'
            : 'Could not read device capabilities.',
      ModelProvisioningFailureCode.noCompatibleModel =>
        _isVietnamese
            ? 'Thiết bị chưa có mô hình tương thích.'
            : 'No compatible model is available for this device.',
      ModelProvisioningFailureCode.storageFailed =>
        _isVietnamese
            ? 'Không thể lưu mô hình vào thiết bị.'
            : 'Could not store the model on this device.',
      ModelProvisioningFailureCode.downloadFailed =>
        _isVietnamese
            ? 'Không thể tải mô hình. Hãy kiểm tra mạng rồi thử lại.'
            : 'The model download failed. Check your connection and try again.',
      ModelProvisioningFailureCode.integrityMismatch =>
        _isVietnamese
            ? 'Mô hình tải xuống không hợp lệ. Hãy thử tải lại.'
            : 'The downloaded model is invalid. Please try downloading again.',
      ModelProvisioningFailureCode.runtimeLoadFailed =>
        _isVietnamese
            ? 'Không thể khởi động AI cục bộ.'
            : 'The local AI runtime could not start.',
      ModelProvisioningFailureCode.unsupportedPlatform =>
        _isVietnamese
            ? 'Nền tảng này chưa hỗ trợ mô hình cục bộ.'
            : 'Local models are not supported on this platform.',
      ModelProvisioningFailureCode.unexpected =>
        _isVietnamese
            ? 'Thiết lập mô hình gặp lỗi không xác định.'
            : 'Model setup failed unexpectedly.',
    };
  }

  String provisioningBytes(String downloaded, String total) {
    return _isVietnamese
        ? '$provisioningDownloaded $downloaded / $total'
        : '$provisioningDownloaded $downloaded of $total';
  }
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
