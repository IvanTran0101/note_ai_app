import 'package:flutter/material.dart';

import '../../application/notes/note_access.dart';

enum NoteSecurityAction { enable, unlock, change, disable, recover, lock }

final class NoteSecurityCopy {
  NoteSecurityCopy(BuildContext context)
    : vi = Localizations.localeOf(context).languageCode == 'vi';
  final bool vi;
  String choose(String v, String e) => vi ? v : e;
  String get protectedNote => choose('Ghi chú được bảo vệ', 'Protected note');
  String get locked => choose(
    'Ghi chú đang khóa. Mở khóa để đọc hoặc chỉnh sửa.',
    'This note is locked. Unlock to read or edit.',
  );
  String get unavailable => choose(
    'Kết nối dịch vụ để xác minh ghi chú và bật bảo vệ.',
    'Connect to the service to verify this note and enable protection.',
  );
  String get password => choose('Mật khẩu ghi chú', 'Note password');
  String get current => choose('Mật khẩu hiện tại', 'Current password');
  String get next => choose('Mật khẩu mới', 'New password');
  String get confirm => choose('Nhập lại mật khẩu', 'Confirm password');
  String get otp => choose('Mã OTP trong email', 'Email OTP');
  String get minimum =>
      choose('Dùng ít nhất 8 ký tự.', 'Use at least 8 characters.');
  String get mismatch =>
      choose('Hai mật khẩu chưa khớp.', 'The passwords do not match.');
  String get cancel => choose('Hủy', 'Cancel');
  String get apply => choose('Xác nhận', 'Confirm');
  String get resend => choose('Gửi lại mã', 'Resend code');
  String get offline => choose('Mở khóa offline', 'Unlock offline');
  String get offlineHint => choose(
    'Chỉ mở dữ liệu đã lưu trên thiết bị. Đồng bộ và AI cloud cần mở khóa online.',
    'Opens cached data on this device. Sync and cloud AI require online unlock.',
  );
  String get recoveryHint => choose(
    'OTP được gửi đến email tài khoản. Đặt lại mật khẩu không khôi phục nháp mã hóa chưa đồng bộ bằng mật khẩu cũ; nháp đó được giữ lại.',
    'An OTP is sent to your account email. Resetting cannot recover encrypted drafts not synced with the old password; they are retained.',
  );
  String get retained => choose(
    'Có nháp mã hóa từ mật khẩu cũ được giữ lại. Chỉnh sửa bị chặn để tránh ghi đè nháp.',
    'Encrypted drafts from the old password are retained. Editing is blocked to prevent overwriting them.',
  );
  String label(NoteSecurityAction action) => switch (action) {
    NoteSecurityAction.enable => choose('Bật bảo vệ', 'Enable protection'),
    NoteSecurityAction.unlock => choose('Mở khóa', 'Unlock'),
    NoteSecurityAction.change => choose('Đổi mật khẩu', 'Change password'),
    NoteSecurityAction.disable => choose('Tắt bảo vệ', 'Disable protection'),
    NoteSecurityAction.recover => choose(
      'Quên mật khẩu / OTP',
      'Forgot password / OTP',
    ),
    NoteSecurityAction.lock => choose('Khóa ngay', 'Lock now'),
  };
  String failure(NoteSecurityFailureCode code) => switch (code) {
    NoteSecurityFailureCode.invalidPassword => choose(
      'Mật khẩu chưa đúng.',
      'Incorrect password.',
    ),
    NoteSecurityFailureCode.invalidChallenge => choose(
      'OTP không đúng, hết hạn hoặc đã dùng. Hãy lấy mã mới.',
      'The OTP is incorrect, expired or used. Request a new code.',
    ),
    NoteSecurityFailureCode.invalidInput => choose(
      'Kiểm tra mật khẩu và xác nhận.',
      'Check the password and confirmation.',
    ),
    NoteSecurityFailureCode.pendingSync => choose(
      'Lưu và đồng bộ ghi chú, giải quyết xung đột trước khi bật bảo vệ.',
      'Save and sync this note and resolve conflicts before enabling protection.',
    ),
    NoteSecurityFailureCode.rateLimited => choose(
      'Đã thử quá nhiều lần. Hãy đợi rồi thử lại.',
      'Too many attempts. Wait before trying again.',
    ),
    NoteSecurityFailureCode.network => choose(
      'Không kết nối được. Chỉ chọn offline nếu đã lưu khóa trên thiết bị.',
      'Cannot connect. Use offline unlock only if a local key was previously saved.',
    ),
    NoteSecurityFailureCode.staleRevision => choose(
      'Ghi chú đã thay đổi. Đồng bộ và mở khóa online lại.',
      'The note changed. Sync and unlock online again.',
    ),
    NoteSecurityFailureCode.sessionChanged => choose(
      'Phiên đã thay đổi. Đăng nhập và mở lại ghi chú.',
      'The session changed. Sign in and reopen the note.',
    ),
    NoteSecurityFailureCode.locked || NoteSecurityFailureCode.expired => locked,
    NoteSecurityFailureCode.denied => choose(
      'Bạn không có quyền thực hiện thao tác này.',
      'You cannot perform this action.',
    ),
    _ => choose(
      'Bảo vệ ghi chú chưa khả dụng. Dữ liệu đang lưu được giữ lại.',
      'Note security is unavailable. Stored data is retained.',
    ),
  };
}
