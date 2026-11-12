import 'package:flutter/material.dart';

import '../../application/notes/sharing_gateway.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';

final class SharingCopy {
  SharingCopy(BuildContext context)
    : vi = Localizations.localeOf(context).languageCode == 'vi';
  final bool vi;
  String get remoteChanged => vi
      ? 'Note đã đổi ở thiết bị khác. Bản nháp vẫn được giữ; chọn bản cloud hoặc chủ động lưu bản local trên phiên bản mới.'
      : 'This note changed on another device. Your draft stays here; choose cloud or explicitly save local against the new version.';
  String get useCloud => vi ? 'Dùng bản cloud' : 'Use cloud';
  String get useLocal => vi ? 'Giữ và lưu bản local' : 'Keep and save local';
  String get sharedWithMe => vi ? 'Được chia sẻ với tôi' : 'Shared with me';
  String get manage => vi ? 'Quản lý chia sẻ' : 'Manage sharing';
  String get email =>
      vi ? 'Email tài khoản đã xác minh' : 'Verified account email';
  String get share => vi ? 'Chia sẻ' : 'Share';
  String get revoke => vi ? 'Thu hồi' : 'Revoke';
  String get retry => vi ? 'Thử lại' : 'Retry';
  String get close => vi ? 'Đóng' : 'Close';
  String get loading =>
      vi ? 'Đang chờ máy chủ xác nhận…' : 'Waiting for server confirmation…';
  String get noRecipients => vi ? 'Chưa chia sẻ với ai.' : 'No recipients yet.';
  String get onlineOnly => vi
      ? 'Cần kết nối và đồng bộ note trước khi quản lý chia sẻ.'
      : 'Connect and sync this note before managing sharing.';
  String get retained => vi
      ? 'Bản nháp được giữ mã hóa; không tự gửi khi quyền thay đổi.'
      : 'Draft retained encrypted; never submitted automatically after access changes.';
  String role(NoteRole role) => role == NoteRole.viewer
      ? (vi ? 'Chỉ xem' : 'Viewer')
      : (vi ? 'Chỉnh sửa' : 'Editor');
  String metadata(NoteShareGrant grant) =>
      '${role(grant.role)} · ${grant.sharerLabel ?? grant.note.ownerId} · ${grant.sharedAt.toLocal().toIso8601String().split('.').first}';
  String status(NoteShareGrant grant) =>
      grant.isActive ? role(grant.role) : (vi ? 'Đã thu hồi' : 'Revoked');
  String failure(ShareFailureCode code) => switch (code) {
    ShareFailureCode.selfShare =>
      vi ? 'Không thể chia sẻ cho chính mình.' : 'Cannot share with yourself.',
    ShareFailureCode.duplicate =>
      vi ? 'Tài khoản này đã có quyền.' : 'This account already has access.',
    ShareFailureCode.recipientUnavailable =>
      vi
          ? 'Không tìm thấy tài khoản đã xác minh phù hợp.'
          : 'No matching verified account is available.',
    ShareFailureCode.invalidInput =>
      vi ? 'Kiểm tra email và vai trò.' : 'Check the email and role.',
    ShareFailureCode.staleAccess =>
      vi
          ? 'Quyền đã đổi. Tải lại danh sách trước khi thử lại.'
          : 'Access changed. Refresh the list before retrying.',
    ShareFailureCode.network =>
      vi
          ? 'Mất kết nối. Thử lại để xác nhận cùng yêu cầu.'
          : 'Connection lost. Retry to confirm the same request.',
    ShareFailureCode.pendingSync => onlineOnly,
    ShareFailureCode.denied =>
      vi
          ? 'Không có quyền quản lý hoặc note đang khóa.'
          : 'Management denied or the note is locked.',
    ShareFailureCode.limit =>
      vi ? 'Đã đạt giới hạn người nhận.' : 'Recipient limit reached.',
    ShareFailureCode.sessionChanged =>
      vi ? 'Phiên tài khoản đã đổi.' : 'Account session changed.',
    _ =>
      vi
          ? 'Chia sẻ chưa khả dụng. Thử lại sau.'
          : 'Sharing unavailable. Try again later.',
  };
}
