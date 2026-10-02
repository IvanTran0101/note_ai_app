import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../application/note_intelligence/summary_run_context.dart';

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
  String get saved =>
      _isVietnamese ? 'Đã lưu trên thiết bị.' : 'Saved locally.';
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

  /// Title of the cloud-summarization consent dialog and settings tile.
  String get summaryCloudTitle =>
      _isVietnamese ? 'Tóm tắt trên đám mây' : 'Cloud summaries';

  /// Full, truthful disclosure of what enabling cloud summarization does.
  ///
  /// It names the destination (NoteFlow backend), the processor (DeepSeek),
  /// the session-only scope, where to revoke, that cancelling never retracts
  /// content that was already sent, and it promises neither zero retention nor
  /// exclusion from provider training, nor any other feature such as RAG.
  String get summaryCloudDisclosure => _isVietnamese
      ? 'Chỉ ghi chú bạn chọn được gửi đến máy chủ NoteFlow và xử lý bằng DeepSeek để tạo bản tóm tắt. Quyền này chỉ có hiệu lực trong phiên hiện tại và có thể thu hồi trong Cài đặt bất cứ lúc nào. Hủy tóm tắt không thu hồi nội dung đã được gửi đi. NoteFlow không cam kết lưu trữ bằng không hay nội dung không được dùng để huấn luyện, và quyền này không bật tính năng truy xuất ghi chú (RAG).'
      : 'Only the note you choose is sent to the NoteFlow backend and processed with DeepSeek to create a summary. This permission lasts for the current session only and can be revoked in Settings at any time. Cancelling a summary does not retract content that was already sent. NoteFlow does not promise zero retention or that content is excluded from provider training, and this permission does not enable note retrieval (RAG).';

  /// Explicit affirmative action of the consent dialog.
  String get summaryCloudAllow => _isVietnamese ? 'Cho phép' : 'Allow';

  /// Heading of the consent dialog's scope summary.
  String get summaryCloudSessionLabel =>
      _isVietnamese ? 'Phiên hiện tại' : 'This session';

  /// Scope of a cloud-summarization grant: one account, one session.
  String get summaryCloudSessionDescription => _isVietnamese
      ? 'Chỉ áp dụng cho tài khoản và phiên hiện tại.'
      : 'Applies to this account and this session only.';

  /// Generic unavailable notice when no specific reason is known.
  String get summaryCloudUnavailable => _isVietnamese
      ? 'Tóm tắt trên đám mây hiện không khả dụng.'
      : 'Cloud summaries are not available right now.';

  /// The exact account and session lack a current cloud grant.
  String get summaryConsentRequired => _isVietnamese
      ? 'Cần quyền tóm tắt trên đám mây.'
      : 'Cloud summary permission is required.';

  /// The user cancelled a summary run.
  String get summaryCancelled =>
      _isVietnamese ? 'Đã hủy tóm tắt.' : 'Summary cancelled.';

  /// The note must be saved before it can be summarized.
  String get summarySavedRequired => _isVietnamese
      ? 'Hãy lưu ghi chú trước khi tóm tắt.'
      : 'Save the note before summarizing.';

  /// A sync conflict blocks the run until it is resolved.
  String get summaryConflictBlocked => _isVietnamese
      ? 'Xung đột đồng bộ đang chặn tóm tắt. Hãy giải quyết trước.'
      : 'A sync conflict is blocking the summary. Resolve it first.';

  /// The account must authenticate again before summarizing.
  String get summarySignInRequired => _isVietnamese
      ? 'Hãy đăng nhập lại để tóm tắt.'
      : 'Sign in again to summarize.';

  /// Local summarization is unavailable on this device or build.
  String get summaryLocalUnavailable => _isVietnamese
      ? 'Tóm tắt cục bộ không khả dụng trên thiết bị này.'
      : 'Local summaries are not available on this device.';

  /// Explains how far a cancellation reaches.
  ///
  /// [cloud] is true only for a run that may already have sent the chosen note:
  /// cancelling stops the run but never retracts content that was sent.
  String summaryCancelExplanation(bool cloud) {
    if (cloud) {
      return _isVietnamese
          ? 'Đã hủy tóm tắt. Nội dung đã gửi trước đó không được thu hồi.'
          : 'The summary was cancelled. Content already sent is not retracted.';
    }
    return _isVietnamese
        ? 'Đã hủy tóm tắt cục bộ.'
        : 'The local summary was cancelled.';
  }

  /// Formats the bounded wait the application derived from a rate-limit hint.
  ///
  /// The caller supplies whole seconds that are already bounded; this method
  /// never reads a raw header. A nonsensical value is floored at one second
  /// instead of being shown as-is.
  String summaryRetryAfter(int seconds) {
    final int bounded = seconds < 1 ? 1 : seconds;
    if (_isVietnamese) {
      return 'Thử lại sau $bounded giây.';
    }
    return bounded == 1
        ? 'Try again in 1 second.'
        : 'Try again in $bounded seconds.';
  }

  /// Safe, localized user action for every [SummaryRunFailureCode].
  ///
  /// Exhaustive on purpose: a new code must be given copy before the app can
  /// build. It never shows a raw enum, exception, or provider payload.
  String summaryFailureMessage(SummaryRunFailureCode code) {
    return switch (code) {
      SummaryRunFailureCode.cancelled => summaryCancelled,
      SummaryRunFailureCode.alreadyRunning =>
        _isVietnamese
            ? 'Một bản tóm tắt khác đang chạy. Hãy đợi hoàn tất.'
            : 'Another summary is already running. Wait for it to finish.',
      SummaryRunFailureCode.runtimeUnavailable =>
        _isVietnamese
            ? 'Tóm tắt không khả dụng trong thiết lập này.'
            : 'Summaries are not available in this setup.',
      SummaryRunFailureCode.sessionChanged =>
        _isVietnamese
            ? 'Tài khoản hoặc phiên đã thay đổi. Hãy thử lại.'
            : 'The account or session changed. Please try again.',
      SummaryRunFailureCode.consentRequired => summaryConsentRequired,
      SummaryRunFailureCode.noteNotFound =>
        _isVietnamese
            ? 'Không tìm thấy ghi chú này.'
            : 'This note could not be found.',
      SummaryRunFailureCode.noteChanged =>
        _isVietnamese
            ? 'Ghi chú đã thay đổi. Hãy thử lại.'
            : 'The note changed. Please try again.',
      SummaryRunFailureCode.conflict => summaryConflictBlocked,
      SummaryRunFailureCode.deadlineExceeded =>
        _isVietnamese
            ? 'Tóm tắt mất quá nhiều thời gian. Hãy thử lại.'
            : 'The summary took too long. Please try again.',
      SummaryRunFailureCode.invalidInput =>
        _isVietnamese
            ? 'Không thể tóm tắt nội dung này.'
            : 'This content cannot be summarized.',
      SummaryRunFailureCode.inputTooLong =>
        _isVietnamese
            ? 'Ghi chú quá dài để tóm tắt.'
            : 'The note is too long to summarize.',
      SummaryRunFailureCode.pipelineTooLarge =>
        _isVietnamese
            ? 'Ghi chú cần quá nhiều bước để tóm tắt.'
            : 'The note needs too many steps to summarize.',
      SummaryRunFailureCode.unauthorized => summarySignInRequired,
      SummaryRunFailureCode.rateLimited =>
        _isVietnamese
            ? 'Bạn đã gửi quá nhiều yêu cầu. Hãy thử lại sau.'
            : 'Too many requests. Please try again later.',
      SummaryRunFailureCode.serviceUnavailable =>
        _isVietnamese
            ? 'Dịch vụ tóm tắt tạm thời không khả dụng. Hãy thử lại.'
            : 'The summary service is temporarily unavailable. Please try again.',
      SummaryRunFailureCode.invalidOutput =>
        _isVietnamese
            ? 'Không thể đọc kết quả tóm tắt. Hãy thử lại.'
            : 'The summary result could not be read. Please try again.',
      SummaryRunFailureCode.networkUnavailable =>
        _isVietnamese
            ? 'Không có kết nối mạng. Hãy kiểm tra rồi thử lại.'
            : 'No network connection. Check your connection and try again.',
      SummaryRunFailureCode.unexpected =>
        _isVietnamese
            ? 'Đã xảy ra lỗi khi tóm tắt. Hãy thử lại.'
            : 'Something went wrong while summarizing. Please try again.',
    };
  }

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
