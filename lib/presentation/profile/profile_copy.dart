import 'package:flutter/widgets.dart';

/// Presentation-only copy for the Profile screen, resolved from the locale the
/// app already runs in (vi / en).
///
/// Unlike the Notes/Auth copy helpers there is no [LocalizationsDelegate]: the
/// delegate list lives in `main.dart`, which this lane does not own, and the
/// screen only needs the ambient locale. [maybeLocaleOf] resolves that locale
/// when a `Localizations` ancestor exists and stays quiet in a bare widget test.
final class ProfileCopy {
  const ProfileCopy._(this._isVietnamese);

  /// Resolves the copy for the ambient locale.
  static ProfileCopy of(BuildContext context) {
    return ProfileCopy._(
      Localizations.maybeLocaleOf(context)?.languageCode == 'vi',
    );
  }

  final bool _isVietnamese;

  String get title => _isVietnamese ? 'Hồ sơ' : 'Profile';
  String get loading => _isVietnamese ? 'Đang tải hồ sơ' : 'Loading profile';
  String get loadError => _isVietnamese
      ? 'Chưa tải được hồ sơ.'
      : 'The profile could not be loaded.';
  String get retry => _isVietnamese ? 'Thử lại' : 'Retry';
  String get reload => _isVietnamese ? 'Tải lại' : 'Reload';

  String get setupTitle =>
      _isVietnamese ? 'Thiết lập hồ sơ' : 'Set up your profile';
  String get setupBody => _isVietnamese
      ? 'Tài khoản này chưa có hồ sơ NoteFlow. Nhập tên hiển thị để tạo hồ sơ.'
      : 'This account has no NoteFlow profile yet. Enter a display name to create one.';

  String get displayNameLabel =>
      _isVietnamese ? 'Tên hiển thị' : 'Display name';
  String get displayNameHelper =>
      _isVietnamese ? 'Tối đa 100 ký tự.' : 'Up to 100 characters.';
  String get nameRequired => _isVietnamese
      ? 'Tên hiển thị không được để trống.'
      : 'Display name must not be blank.';
  String get nameTooLong => _isVietnamese
      ? 'Tên hiển thị tối đa 100 ký tự.'
      : 'Display name must be at most 100 characters.';
  String get saveName => _isVietnamese ? 'Lưu tên' : 'Save name';
  String get createProfile => _isVietnamese ? 'Tạo hồ sơ' : 'Create profile';
  String get saving => _isVietnamese ? 'Đang lưu…' : 'Saving…';
  String get saved => _isVietnamese ? 'Đã lưu.' : 'Saved.';

  String get avatarLabel => _isVietnamese ? 'Ảnh đại diện' : 'Avatar';
  String get avatarRules => _isVietnamese
      ? 'PNG hoặc JPEG, tối đa 1 MiB, mỗi cạnh tối đa 2048 px.'
      : 'PNG or JPEG, up to 1 MiB and 2048 px per edge.';
  String get addAvatar => _isVietnamese ? 'Thêm ảnh' : 'Add image';
  String get changeAvatar => _isVietnamese ? 'Đổi ảnh' : 'Change image';
  String get removeAvatar => _isVietnamese ? 'Xóa ảnh' : 'Remove image';
  String get avatarSetupHint => _isVietnamese
      ? 'Lưu tên hiển thị trước khi thêm ảnh đại diện.'
      : 'Save a display name before adding an avatar.';

  String get invalidInput => _isVietnamese
      ? 'Tên hoặc ảnh không hợp lệ.'
      : 'That name or image is not valid.';
  String get avatarInvalid => _isVietnamese
      ? 'Ảnh không hợp lệ: chỉ nhận PNG/JPEG tối đa 1 MiB, mỗi cạnh tối đa 2048 px.'
      : 'Invalid image: PNG or JPEG only, up to 1 MiB and 2048 px per edge.';
  String get avatarError => _isVietnamese
      ? 'Chưa chọn hoặc lưu được ảnh đại diện. Hãy thử lại.'
      : 'The avatar could not be selected or saved. Please try again.';
  String get conflict => _isVietnamese
      ? 'Hồ sơ đã thay đổi trên thiết bị khác. Hãy tải lại rồi thử lại.'
      : 'The profile changed on another device. Reload and try again.';
  String get unavailable => _isVietnamese
      ? 'Chưa kết nối được dịch vụ hồ sơ. Hãy thử lại.'
      : 'The profile service could not be reached. Please try again.';
  String get sessionChanged => _isVietnamese
      ? 'Phiên đăng nhập đã thay đổi. Hãy đăng nhập lại.'
      : 'Your session changed. Please sign in again.';
  String get saveError => _isVietnamese
      ? 'Chưa lưu được hồ sơ. Hãy thử lại.'
      : 'The profile was not saved. Please try again.';
}
