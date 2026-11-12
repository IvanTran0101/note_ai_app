/// Stable route paths owned by the Presentation layer.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String home = '/';
  static const String notes = '/notes';
  static const String noteDetails = '/notes/:id';
  static const String profile = '/settings/profile';
  static const String changePassword = '/settings/change-password';

  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String verifyEmail = '/verify-email';
}
