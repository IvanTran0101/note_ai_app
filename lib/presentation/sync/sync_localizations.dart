import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../application/sync/note_sync_status.dart';
import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_status.dart';

/// Shared English/Vietnamese copy for sync status and conflict interactions.
final class SyncCopy {
  const SyncCopy._(this._isVietnamese);

  static const LocalizationsDelegate<SyncCopy> delegate =
      _SyncCopyLocalizationsDelegate();

  static SyncCopy of(BuildContext context) {
    final SyncCopy? copy = Localizations.of<SyncCopy>(context, SyncCopy);
    if (copy != null) return copy;
    return SyncCopy._(
      Localizations.maybeLocaleOf(context)?.languageCode == 'vi',
    );
  }

  final bool _isVietnamese;

  String get allSynced => _isVietnamese ? 'Đã đồng bộ' : 'All synced';
  String get checking =>
      _isVietnamese ? 'Đang kiểm tra trạng thái…' : 'Checking sync status…';
  String get pending => _isVietnamese ? 'Đang chờ đồng bộ' : 'Sync pending';
  String get offline => _isVietnamese ? 'Đang ngoại tuyến' : 'Offline';
  String get syncing => _isVietnamese ? 'Đang đồng bộ…' : 'Syncing…';
  String get failed => _isVietnamese ? 'Đồng bộ thất bại' : 'Sync failed';
  String get conflictsNeedReview =>
      _isVietnamese ? 'Có xung đột cần xử lý' : 'Conflicts need review';
  String get retry => _isVietnamese ? 'Thử lại' : 'Retry';
  String get syncNow => _isVietnamese ? 'Đồng bộ ngay' : 'Sync now';
  String get pendingChanges =>
      _isVietnamese ? 'thay đổi đang chờ' : 'changes pending';
  String conflictCount(int count) => _isVietnamese
      ? '$count xung đột cần xử lý'
      : '$count ${count == 1 ? 'conflict' : 'conflicts'} to review';
  String get invalidMutationHint => _isVietnamese
      ? 'Hãy chỉnh sửa và lưu ghi chú bị từ chối để thử lại.'
      : 'Edit and save the rejected note to try it again.';
  String get localStoreError => _isVietnamese
      ? 'Không thể đọc trạng thái đồng bộ trên thiết bị.'
      : 'Couldn’t read sync state on this device.';
  String get conflictChanged => _isVietnamese
      ? 'Xung đột đã thay đổi. Hãy xem lại phiên bản mới nhất.'
      : 'The conflict changed. Review the latest versions.';
  String get conflictTitle =>
      _isVietnamese ? 'Xung đột ghi chú' : 'Note conflict';
  String get resolveConflict => _isVietnamese ? 'Giải quyết' : 'Resolve';
  String get localVersion =>
      _isVietnamese ? 'Bản trên thiết bị' : 'On this device';
  String get remoteVersion =>
      _isVietnamese ? 'Bản trên máy chủ' : 'On the server';
  String get remoteMissing => _isVietnamese
      ? 'Máy chủ không còn bản ghi chú này.'
      : 'The server no longer has this note.';
  String get remoteDeleted => _isVietnamese
      ? 'Ghi chú đã bị xóa trên máy chủ.'
      : 'The note was deleted on the server.';
  String get useLocal => _isVietnamese ? 'Dùng bản trên thiết bị' : 'Use local';
  String get useRemote => _isVietnamese ? 'Dùng bản máy chủ' : 'Use remote';
  String get later => _isVietnamese ? 'Để sau' : 'Later';
  String get draftConflictTitle =>
      _isVietnamese ? 'Bạn có bản nháp chưa lưu' : 'You have an unsaved draft';
  String get draftConflictMessage => _isVietnamese
      ? 'Hãy lưu bản nháp thành ghi chú mới, bỏ bản nháp rồi tiếp tục, hoặc hủy.'
      : 'Save the draft as a new note, discard it and continue, or cancel.';
  String get saveAsNew =>
      _isVietnamese ? 'Lưu thành ghi chú mới' : 'Save as new note';
  String get discardDraftAndContinue =>
      _isVietnamese ? 'Bỏ bản nháp và tiếp tục' : 'Discard draft and continue';
  String get cancel => _isVietnamese ? 'Hủy' : 'Cancel';
  String noteStatus(NoteSyncStatus status) => switch (status) {
    NoteSyncStatus.synced => _isVietnamese ? 'Đã đồng bộ' : 'Synced',
    NoteSyncStatus.pending => _isVietnamese ? 'Đang chờ' : 'Pending',
    NoteSyncStatus.failed => _isVietnamese ? 'Cần thử lại' : 'Failed',
    NoteSyncStatus.conflict => _isVietnamese ? 'Xung đột' : 'Conflict',
  };

  String status(SyncStatus value) => switch (value) {
    SyncStatus.idle => allSynced,
    SyncStatus.offline => offline,
    SyncStatus.syncing => syncing,
    SyncStatus.failed => failed,
  };

  String failure(SyncFailure? failure) {
    if (failure == null) return failed;
    return switch (failure.code) {
      SyncErrorCode.networkUnavailable => offline,
      SyncErrorCode.timeout =>
        _isVietnamese
            ? 'Máy chủ phản hồi quá lâu.'
            : 'The server took too long to respond.',
      SyncErrorCode.serverUnavailable =>
        _isVietnamese
            ? 'Máy chủ tạm thời không khả dụng.'
            : 'The server is temporarily unavailable.',
      SyncErrorCode.throttled =>
        _isVietnamese
            ? 'Máy chủ đang bận. Hãy thử lại sau.'
            : 'The server is busy. Try again shortly.',
      SyncErrorCode.unauthorized =>
        _isVietnamese
            ? 'Phiên đăng nhập cần được làm mới.'
            : 'Your sign-in session needs to be refreshed.',
      SyncErrorCode.forbidden =>
        _isVietnamese
            ? 'Tài khoản hiện tại không thể đồng bộ dữ liệu này.'
            : 'The current account cannot sync this data.',
      SyncErrorCode.invalidMutation =>
        _isVietnamese
            ? 'Máy chủ từ chối thay đổi của ghi chú.'
            : 'The server rejected a note change.',
      SyncErrorCode.documentRequiresUpgrade =>
        _isVietnamese
            ? 'Máy chủ cần cập nhật để đồng bộ định dạng. Thay đổi đã lưu trên thiết bị.'
            : 'The server needs an update to sync formatting. Changes are saved on this device.',
      SyncErrorCode.unexpected => failed,
    };
  }
}

final class _SyncCopyLocalizationsDelegate
    extends LocalizationsDelegate<SyncCopy> {
  const _SyncCopyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<SyncCopy> load(Locale locale) =>
      SynchronousFuture<SyncCopy>(SyncCopy._(locale.languageCode == 'vi'));

  @override
  bool shouldReload(_SyncCopyLocalizationsDelegate old) => false;
}
