import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../domain/note_intelligence/rag_models.dart';

/// Presentation-only copy for the RAG (ask-my-notes) screen and consent tile.
///
/// The language follows the locale [MaterialApp] already resolves from the
/// user's existing language preference: there is no separate RAG language
/// setting. [of] prefers a registered [RagCopy] localizations delegate and falls
/// back to the resolved locale, so the copy is correct even before the
/// composition root registers [delegate].
///
/// Every user-facing string here is safe by construction: no exception text,
/// endpoint, model id, provider payload, token, note body, question, or answer
/// is ever interpolated. The failure table is exhaustive over
/// [RagFailureCode], so a new code cannot ship without copy.
final class RagCopy {
  const RagCopy._(this._isVietnamese);

  /// Registers the VI/EN copy with the ambient [Localizations].
  static const LocalizationsDelegate<RagCopy> delegate =
      _RagCopyLocalizationsDelegate();

  /// Resolves the copy for the current locale.
  ///
  /// Read inside `build` (or after an awaited dialog) so a locale change
  /// retranslates the same state instead of freezing the language captured
  /// when a dialog opened.
  static RagCopy of(BuildContext context) {
    final RagCopy? copy = Localizations.of<RagCopy>(context, RagCopy);
    if (copy != null) {
      return copy;
    }
    final Locale? locale = Localizations.maybeLocaleOf(context);
    return RagCopy._(locale?.languageCode == 'vi');
  }

  final bool _isVietnamese;

  String get pageTitle => _isVietnamese ? 'Hỏi ghi chú' : 'Ask your notes';

  String get scopeLabel => _isVietnamese ? 'Phạm vi tìm' : 'Search scope';

  String get scopeAccountLabel =>
      _isVietnamese ? 'Tất cả ghi chú' : 'All notes';

  String get scopeNoteLabel => _isVietnamese ? 'Ghi chú này' : 'This note';

  String get questionLabel =>
      _isVietnamese ? 'Câu hỏi của bạn' : 'Your question';

  String get questionHint => _isVietnamese
      ? 'Hỏi về ghi chú của bạn…'
      : 'Ask about your own notes…';

  String get ask => _isVietnamese ? 'Hỏi' : 'Ask';

  String get asking => _isVietnamese ? 'Đang hỏi…' : 'Asking…';

  String get cancel => _isVietnamese ? 'Hủy' : 'Cancel';

  String get answerQuestionLabel => _isVietnamese ? 'Câu hỏi' : 'Question';

  String get sourcesLabel => _isVietnamese ? 'Nguồn' : 'Sources';

  String get notEnoughContextTitle =>
      _isVietnamese ? 'Không đủ ngữ cảnh' : 'Not enough context';

  String get notEnoughContextBody => _isVietnamese
      ? 'Ghi chú của bạn không có đủ bằng chứng để trả lời câu hỏi này.'
      : 'Your notes do not contain enough evidence to answer this question.';

  /// Accessible label of one source button.
  ///
  /// [sourceId] is the exact backend source identity (for example `S3`) and is
  /// rendered verbatim, never as a position in the citations array.
  String sourceOpenSemantics(String sourceId, String title) => _isVietnamese
      ? 'Mở nguồn $sourceId: $title'
      : 'Open source $sourceId: $title';

  String get consentTitle =>
      _isVietnamese ? 'Quyền hỏi ghi chú' : 'Ask-notes permission';

  String get consentStatusAllowed => _isVietnamese
      ? 'Đã cho phép cho tài khoản và phiên bản này. Tắt để thu hồi ngay.'
      : 'Allowed for this account and version. Turn off to revoke immediately.';

  String get consentStatusDenied => _isVietnamese
      ? 'Chưa cho phép. Nút Hỏi bị tắt cho đến khi bạn cho phép.'
      : 'Not allowed. Ask stays disabled until you allow.';

  String get consentStatusUnknown => _isVietnamese
      ? 'Chưa xác minh quyền. Làm mới để kiểm tra.'
      : 'Permission is not verified. Refresh to check.';

  String get consentStatusLoading =>
      _isVietnamese ? 'Đang kiểm tra quyền…' : 'Checking permission…';

  String get consentRefresh => _isVietnamese ? 'Làm mới' : 'Refresh';

  String get consentDialogTitle => _isVietnamese
      ? 'Cho phép hỏi ghi chú?'
      : 'Allow asking your notes?';

  String get consentDialogAllow => _isVietnamese ? 'Cho phép' : 'Allow';

  String get consentDialogCancel => _isVietnamese ? 'Hủy' : 'Cancel';

  String get consentScopeLabel =>
      _isVietnamese ? 'Phạm vi của quyền này' : 'Scope of this permission';

  String get consentScopeDescription => _isVietnamese
      ? 'Văn bản đã đồng bộ, chưa bảo vệ, thuộc sở hữu của bạn trên tài khoản và phiên bản này, trên mọi thiết bị.'
      : 'Your own synced, unprotected text on this account and version, across devices.';

  /// Full, truthful disclosure shown before an explicit Allow.
  ///
  /// It names the processors (the NoteFlow backend on AWS, the self-hosted
  /// NoteFlow embedding reached through Cloudflare, TypeSafe JEV, and DeepSeek),
  /// the included scope, the excluded inputs, the account/version binding, the
  /// default-off state, the logout/revoke semantics, and the cancellation
  /// caveat. It promises neither zero retention nor exclusion from provider
  /// training, and it never implies that this grants cloud summaries.
  String get consentDisclosure => _isVietnamese
      ? 'Chỉ dùng văn bản đã đồng bộ, chưa bảo vệ và thuộc sở hữu của bạn. Ghi chú được chia sẻ đến bạn, tệp đính kèm và bản nháp cục bộ đều bị loại trừ. Nội dung được gửi đến máy chủ NoteFlow trên AWS, sau đó đến mô hình embedding NoteFlow tự vận hành qua Cloudflare và xử lý bằng TypeSafe JEV và DeepSeek. Quyền này gắn với tài khoản và phiên bản rag-consent.v2, áp dụng trên mọi thiết bị và mặc định tắt. Đăng xuất xóa phiên chạy cục bộ nhưng không thu hồi quyền. Thu hồi rõ ràng sẽ chặn yêu cầu mới và xóa câu trả lời đang hiển thị. Hủy một câu hỏi đã gửi đi có thể không dừng được yêu cầu đã bị tính phí.'
      : 'Only your own synced, unprotected text is used. Notes shared with you, attachments, and local drafts are excluded. Content is sent to the NoteFlow backend on AWS, then to the self-hosted NoteFlow embedding model reached through Cloudflare, and processed with TypeSafe JEV and DeepSeek. This permission is bound to your account and to version rag-consent.v2, applies across devices, and is off by default. Logging out clears the local run but does not revoke the grant. An explicit revoke stops new requests and clears the displayed answer. Cancelling a question that was already dispatched may not stop an already-billed request.';

  /// Formats the bounded wait derived from a rate-limit hint.
  ///
  /// [seconds] is already sanitized by [RagFailure.retryAfterSeconds]; a
  /// nonsensical value is floored at one second instead of being shown raw.
  String retryAfter(int seconds) {
    final int bounded = seconds < 1 ? 1 : seconds;
    if (_isVietnamese) {
      return 'Thử lại sau $bounded giây.';
    }
    return bounded == 1
        ? 'Try again in 1 second.'
        : 'Try again in $bounded seconds.';
  }

  /// Safe, localized message for one typed failure, including any bounded hint.
  String failureMessage(RagFailure failure) {
    final String base = failureCodeMessage(failure.code);
    final int? hint = failure.retryAfterSeconds;
    if (hint == null) {
      return base;
    }
    return '$base ${retryAfter(hint)}';
  }

  /// Safe, localized message for every [RagFailureCode].
  ///
  /// Exhaustive on purpose: a new code must be given copy before the app can
  /// compile. It never shows a raw enum, exception, endpoint, or provider id.
  String failureCodeMessage(RagFailureCode code) {
    return switch (code) {
      RagFailureCode.cancelled => _isVietnamese
          ? 'Đã hủy câu hỏi. Yêu cầu đã gửi trước đó vẫn có thể được xử lý.'
          : 'Question cancelled. A request already sent may still be processed.',
      RagFailureCode.sessionChanged => _isVietnamese
          ? 'Tài khoản hoặc phiên đã thay đổi. Hãy thử lại.'
          : 'The account or session changed. Please try again.',
      RagFailureCode.network => _isVietnamese
          ? 'Không có kết nối mạng. Hãy kiểm tra rồi thử lại.'
          : 'No network connection. Check your connection and try again.',
      RagFailureCode.alreadyRunning => _isVietnamese
          ? 'Một câu hỏi khác đang chạy. Hãy đợi hoàn tất.'
          : 'Another question is already running. Wait for it to finish.',
      RagFailureCode.consentUnknown => _isVietnamese
          ? 'Chưa xác minh được quyền. Hãy làm mới quyền.'
          : 'Permission is not verified. Refresh the permission.',
      RagFailureCode.consentRequired => _isVietnamese
          ? 'Cần quyền hỏi ghi chú.'
          : 'Permission to ask your notes is required.',
      RagFailureCode.sourceChanged => _isVietnamese
          ? 'Nguồn đã thay đổi và không thể mở.'
          : 'The source changed and can no longer be opened.',
      RagFailureCode.sourceUnavailable => _isVietnamese
          ? 'Không thể mở nguồn này.'
          : 'This source could not be opened.',
      RagFailureCode.localStateUnavailable => _isVietnamese
          ? 'Không đọc được trạng thái ghi chú cục bộ.'
          : 'Local note state could not be read.',
      RagFailureCode.invalidInput => _isVietnamese
          ? 'Không thể gửi câu hỏi này.'
          : 'This question cannot be sent.',
      RagFailureCode.inputTooLong => _isVietnamese
          ? 'Câu hỏi quá dài.'
          : 'The question is too long.',
      RagFailureCode.unauthorized => _isVietnamese
          ? 'Hãy đăng nhập lại để hỏi ghi chú.'
          : 'Sign in again to ask your notes.',
      RagFailureCode.scopeDenied => _isVietnamese
          ? 'Phạm vi này không được phép.'
          : 'This scope is not allowed.',
      RagFailureCode.indexNotReady => _isVietnamese
          ? 'Chỉ mục ghi chú chưa sẵn sàng. Hãy thử lại sau.'
          : 'The note index is not ready yet. Try again later.',
      RagFailureCode.rateLimited => _isVietnamese
          ? 'Bạn đã gửi quá nhiều yêu cầu. Hãy thử lại sau.'
          : 'Too many requests. Please try again later.',
      RagFailureCode.evidenceValidationUnavailable => _isVietnamese
          ? 'Không xác minh được bằng chứng. Hãy thử lại.'
          : 'Evidence could not be verified. Please try again.',
      RagFailureCode.providerUnavailable => _isVietnamese
          ? 'Dịch vụ hỏi ghi chú tạm thời không khả dụng. Hãy thử lại.'
          : 'The ask-notes service is temporarily unavailable. Please try again.',
      RagFailureCode.invalidProviderOutput => _isVietnamese
          ? 'Không đọc được kết quả. Hãy thử lại.'
          : 'The result could not be read. Please try again.',
      RagFailureCode.timeout => _isVietnamese
          ? 'Câu hỏi mất quá nhiều thời gian. Hãy thử lại.'
          : 'The question took too long. Please try again.',
      RagFailureCode.livePolicyNotConfigured => _isVietnamese
          ? 'Tính năng hỏi ghi chú chưa được bật cho tài khoản này.'
          : 'Ask-notes is not enabled for this account.',
      RagFailureCode.unexpected => _isVietnamese
          ? 'Đã xảy ra lỗi khi hỏi ghi chú. Hãy thử lại.'
          : 'Something went wrong while asking your notes. Please try again.',
    };
  }
}

final class _RagCopyLocalizationsDelegate
    extends LocalizationsDelegate<RagCopy> {
  const _RagCopyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<RagCopy> load(Locale locale) =>
      SynchronousFuture<RagCopy>(RagCopy._(locale.languageCode == 'vi'));

  @override
  bool shouldReload(_RagCopyLocalizationsDelegate old) => false;
}
