import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'controllers/auth_state.dart';

/// Localized copy for the Phase 5 authentication forms.
final class AuthCopy {
  const AuthCopy._(this._isVietnamese);

  static AuthCopy of(BuildContext context) {
    final AuthCopy? copy = Localizations.of<AuthCopy>(context, AuthCopy);
    if (copy != null) {
      return copy;
    }
    final Locale? locale = Localizations.maybeLocaleOf(context);
    return AuthCopy._(locale?.languageCode == 'vi');
  }

  static const LocalizationsDelegate<AuthCopy> delegate =
      _AuthCopyLocalizationsDelegate();

  final bool _isVietnamese;

  String get loginTitle => _isVietnamese ? 'Chào mừng trở lại' : 'Welcome back';
  String get loginSubtitle => _isVietnamese
      ? 'Đăng nhập để tiếp tục với ghi chú của bạn.'
      : 'Log in to continue to your notes.';
  String get registerTitle =>
      _isVietnamese ? 'Tạo tài khoản' : 'Create your account';
  String get registerSubtitle => _isVietnamese
      ? 'Lưu ghi chú và truy cập chúng trên các thiết bị của bạn.'
      : 'Save your notes and access them across your devices.';
  String get forgotTitle =>
      _isVietnamese ? 'Đặt lại mật khẩu' : 'Reset your password';
  String get forgotSubtitle => _isVietnamese
      ? 'Nhập email để nhận mã đặt lại mật khẩu.'
      : 'Enter your email to receive a reset code.';
  String get resetTitle =>
      _isVietnamese ? 'Tạo mật khẩu mới' : 'Create a new password';
  String get resetSubtitle => _isVietnamese
      ? 'Nhập mã đã nhận và mật khẩu mới của bạn.'
      : 'Enter the code you received and your new password.';

  String get email => _isVietnamese ? 'Email' : 'Email';
  String get displayName => _isVietnamese ? 'Tên hiển thị' : 'Display name';
  String get password => _isVietnamese ? 'Mật khẩu' : 'Password';
  String get confirmPassword =>
      _isVietnamese ? 'Xác nhận mật khẩu' : 'Confirm password';
  String get verificationCode =>
      _isVietnamese ? 'Mã xác nhận' : 'Verification code';

  String get loginAction => _isVietnamese ? 'Đăng nhập' : 'Log in';
  String get registerAction =>
      _isVietnamese ? 'Tạo tài khoản' : 'Create account';
  String get sendResetCode =>
      _isVietnamese ? 'Gửi mã đặt lại' : 'Send reset code';
  String get resetPasswordAction =>
      _isVietnamese ? 'Đặt lại mật khẩu' : 'Reset password';
  String get forgotPassword =>
      _isVietnamese ? 'Quên mật khẩu?' : 'Forgot password?';
  String get createAccount =>
      _isVietnamese ? 'Tạo tài khoản mới' : 'Create an account';
  String get alreadyHaveAccount =>
      _isVietnamese ? 'Đã có tài khoản?' : 'Already have an account?';
  String get backToLogin => _isVietnamese ? 'Về đăng nhập' : 'Back to log in';

  String get emailRequired =>
      _isVietnamese ? 'Vui lòng nhập email.' : 'Email is required.';
  String get displayNameRequired => _isVietnamese
      ? 'Vui lòng nhập tên hiển thị.'
      : 'Display name is required.';
  String get passwordRequired =>
      _isVietnamese ? 'Vui lòng nhập mật khẩu.' : 'Password is required.';
  String get passwordConfirmationMismatch => _isVietnamese
      ? 'Mật khẩu xác nhận không khớp.'
      : 'Passwords do not match.';
  String get verificationCodeRequired => _isVietnamese
      ? 'Vui lòng nhập mã xác nhận.'
      : 'Verification code is required.';
  String get genericError => _isVietnamese
      ? 'Đã xảy ra lỗi. Vui lòng thử lại.'
      : 'Something went wrong. Please try again.';

  String? errorMessage(AuthPresentationError? error) {
    final AuthPresentationErrorCode? code = error?.code;
    if (code == null) {
      return null;
    }
    return switch (code) {
      AuthPresentationErrorCode.emailRequired => emailRequired,
      AuthPresentationErrorCode.displayNameRequired => displayNameRequired,
      AuthPresentationErrorCode.passwordRequired => passwordRequired,
      AuthPresentationErrorCode.passwordConfirmationMismatch =>
        passwordConfirmationMismatch,
      AuthPresentationErrorCode.verificationCodeRequired =>
        verificationCodeRequired,
      AuthPresentationErrorCode.currentPasswordRequired => passwordRequired,
      AuthPresentationErrorCode.invalidCredentials =>
        _isVietnamese
            ? 'Email hoặc mật khẩu không đúng.'
            : 'Email or password is incorrect.',
      AuthPresentationErrorCode.accountAlreadyExists =>
        _isVietnamese
            ? 'Email này đã được đăng ký.'
            : 'An account with this email already exists.',
      AuthPresentationErrorCode.passwordRejected =>
        _isVietnamese
            ? 'Mật khẩu không đáp ứng yêu cầu.'
            : 'The password does not meet the requirements.',
      AuthPresentationErrorCode.invalidVerificationCode =>
        _isVietnamese
            ? 'Mã xác nhận không đúng.'
            : 'The verification code is invalid.',
      AuthPresentationErrorCode.expiredVerificationCode =>
        _isVietnamese
            ? 'Mã xác nhận đã hết hạn.'
            : 'The verification code has expired.',
      AuthPresentationErrorCode.temporarilyUnavailable =>
        _isVietnamese
            ? 'Dịch vụ tạm thời không khả dụng.'
            : 'The service is temporarily unavailable.',
      AuthPresentationErrorCode.unauthenticated =>
        _isVietnamese
            ? 'Phiên đăng nhập đã hết hạn.'
            : 'Your session has expired.',
      AuthPresentationErrorCode.unsupportedChallenge => genericError,
      AuthPresentationErrorCode.identityUnavailable => genericError,
      AuthPresentationErrorCode.unknown => genericError,
    };
  }
}

final class _AuthCopyLocalizationsDelegate
    extends LocalizationsDelegate<AuthCopy> {
  const _AuthCopyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<AuthCopy> load(Locale locale) =>
      SynchronousFuture<AuthCopy>(AuthCopy._(locale.languageCode == 'vi'));

  @override
  bool shouldReload(_AuthCopyLocalizationsDelegate old) => false;
}
