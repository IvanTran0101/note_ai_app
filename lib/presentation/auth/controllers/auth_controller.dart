import 'package:flutter/foundation.dart';

import '../../../application/auth/auth_models.dart';
import '../../../application/auth/authentication_app_service.dart';
import '../../../application/auth/current_user.dart';
import '../../../domain/auth/authentication_failure.dart';
import 'auth_state.dart';

/// Presentation controller for the provider-neutral authentication use cases.
///
/// This class knows only [IAuthenticationAppService]. It owns UI lifecycle
/// state, maps failures to safe Presentation codes, and never stores a
/// password or provider exception.
final class AuthController extends ChangeNotifier {
  AuthController({
    required this.authenticationAppService,
    AuthUserDto? initialUser,
  }) : assert(
         authenticationAppService != null || initialUser != null,
         'Provide an app service or an initial compatibility user.',
       ),
       _state = initialUser == null
           ? const AuthState.initializing()
           : AuthState.authenticated(user: initialUser),
       _initializationCompleted = initialUser != null;

  /// Null only for the local compatibility bootstrap, where [initialUser]
  /// already represents the authenticated demo session.
  final IAuthenticationAppService? authenticationAppService;

  AuthState _state;
  bool _disposed = false;
  bool _initializationCompleted;

  AuthState get state => _state;

  IAuthenticationAppService get _service {
    final IAuthenticationAppService? service = authenticationAppService;
    if (service == null) {
      throw StateError('Authentication is unavailable in local mode.');
    }
    return service;
  }

  /// Restores the provider session once. A failed initialization can be
  /// retried; a completed initialization is idempotent.
  Future<AuthUserDto?> initialize() async {
    _ensureActive();
    if (_initializationCompleted) {
      return _state.user;
    }
    _emit(const AuthState.initializing(isBusy: true));
    try {
      final AuthUserDto? user = await _service.restoreSession();
      _initializationCompleted = true;
      _emit(
        user == null
            ? const AuthState.unauthenticated()
            : AuthState.authenticated(user: user),
      );
      return user;
    } on Object catch (error, stackTrace) {
      _emit(AuthState.initializing(error: _mapError(error)));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<AuthUserDto> login(LoginInput input) {
    return _execute(
      operation: () => _service.login(input),
      onSuccess: (AuthUserDto user) {
        _initializationCompleted = true;
        return AuthState.authenticated(user: user);
      },
    );
  }

  Future<RegistrationResult> register(RegisterInput input) {
    return _execute(
      operation: () => _service.register(input),
      onSuccess: (RegistrationResult result) {
        _initializationCompleted = true;
        return AuthState.authenticated(user: result.user);
      },
    );
  }

  Future<void> logout() async {
    _ensureActive();
    _ensureNotBusy();
    _emit(_busyState());
    try {
      await _service.logout();
      _emit(const AuthState.unauthenticated());
    } on Object catch (error, stackTrace) {
      // AuthenticationAppService clears its local session in finally, even
      // when the provider sign-out fails.
      _emit(AuthState.unauthenticated(error: _mapError(error)));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<AuthUserDto> refreshIdentity() {
    return _execute(
      operation: _service.refreshIdentity,
      onSuccess: (AuthUserDto user) => AuthState.authenticated(user: user),
    );
  }

  Future<void> resendVerification() {
    return _executeVoid(_service.resendEmailVerification);
  }

  Future<AuthUserDto> confirmVerification({required String code}) {
    return _execute(
      operation: () => _service.confirmEmailVerification(code: code),
      onSuccess: (AuthUserDto user) => AuthState.authenticated(user: user),
    );
  }

  Future<void> requestPasswordReset({required String email}) {
    return _executeVoid(() => _service.requestPasswordReset(email: email));
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _executeVoid(
      () => _service.confirmPasswordReset(
        email: email,
        code: code,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      ),
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _executeVoid(
      () => _service.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      ),
    );
  }

  Future<T> _execute<T>({
    required Future<T> Function() operation,
    required AuthState Function(T result) onSuccess,
  }) async {
    _ensureActive();
    _ensureNotBusy();
    _emit(_busyState());
    try {
      final T result = await operation();
      _emit(onSuccess(result));
      return result;
    } on Object catch (error, stackTrace) {
      _emit(_failureState(error));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _executeVoid(Future<void> Function() operation) async {
    _ensureActive();
    _ensureNotBusy();
    _emit(_busyState());
    try {
      await operation();
      _emit(_stableState());
    } on Object catch (error, stackTrace) {
      _emit(_failureState(error));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  AuthState _busyState() {
    return switch (_state.status) {
      AuthStatus.initializing => const AuthState.initializing(isBusy: true),
      AuthStatus.unauthenticated => const AuthState.unauthenticated(
        isBusy: true,
      ),
      AuthStatus.authenticated => AuthState.authenticated(
        user: _state.user!,
        isBusy: true,
      ),
    };
  }

  AuthState _stableState() {
    return switch (_state.status) {
      AuthStatus.initializing => const AuthState.initializing(),
      AuthStatus.unauthenticated => const AuthState.unauthenticated(),
      AuthStatus.authenticated => AuthState.authenticated(user: _state.user!),
    };
  }

  AuthState _failureState(Object error) {
    final AuthPresentationError mapped = _mapError(error);
    if (_isUnauthenticated(error)) {
      return AuthState.unauthenticated(error: mapped);
    }
    return switch (_state.status) {
      AuthStatus.initializing => AuthState.initializing(error: mapped),
      AuthStatus.unauthenticated => AuthState.unauthenticated(error: mapped),
      AuthStatus.authenticated => AuthState.authenticated(
        user: _state.user!,
        error: mapped,
      ),
    };
  }

  AuthPresentationError _mapError(Object error) {
    if (error is AuthValidationException) {
      return AuthPresentationError(switch (error.reason) {
        AuthValidationReason.emailRequired =>
          AuthPresentationErrorCode.emailRequired,
        AuthValidationReason.displayNameRequired =>
          AuthPresentationErrorCode.displayNameRequired,
        AuthValidationReason.passwordRequired =>
          AuthPresentationErrorCode.passwordRequired,
        AuthValidationReason.passwordConfirmationMismatch =>
          AuthPresentationErrorCode.passwordConfirmationMismatch,
        AuthValidationReason.verificationCodeRequired =>
          AuthPresentationErrorCode.verificationCodeRequired,
        AuthValidationReason.currentPasswordRequired =>
          AuthPresentationErrorCode.currentPasswordRequired,
      });
    }
    if (error is AuthenticationFailure) {
      return AuthPresentationError(switch (error.code) {
        AuthenticationFailureCode.invalidCredentials =>
          AuthPresentationErrorCode.invalidCredentials,
        AuthenticationFailureCode.accountAlreadyExists =>
          AuthPresentationErrorCode.accountAlreadyExists,
        AuthenticationFailureCode.passwordRejected =>
          AuthPresentationErrorCode.passwordRejected,
        AuthenticationFailureCode.invalidVerificationCode =>
          AuthPresentationErrorCode.invalidVerificationCode,
        AuthenticationFailureCode.expiredVerificationCode =>
          AuthPresentationErrorCode.expiredVerificationCode,
        AuthenticationFailureCode.temporarilyUnavailable =>
          AuthPresentationErrorCode.temporarilyUnavailable,
        AuthenticationFailureCode.unauthenticated =>
          AuthPresentationErrorCode.unauthenticated,
        AuthenticationFailureCode.unsupportedChallenge =>
          AuthPresentationErrorCode.unsupportedChallenge,
        AuthenticationFailureCode.identityUnavailable =>
          AuthPresentationErrorCode.identityUnavailable,
        AuthenticationFailureCode.unknown => AuthPresentationErrorCode.unknown,
      });
    }
    if (error is UnauthenticatedException) {
      return const AuthPresentationError(
        AuthPresentationErrorCode.unauthenticated,
      );
    }
    return const AuthPresentationError(AuthPresentationErrorCode.unknown);
  }

  bool _isUnauthenticated(Object error) {
    return error is UnauthenticatedException ||
        (error is AuthenticationFailure &&
            error.code == AuthenticationFailureCode.unauthenticated);
  }

  void _ensureNotBusy() {
    if (_state.isBusy) {
      throw StateError('Authentication operation already in progress.');
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('AuthController is disposed.');
    }
  }

  void _emit(AuthState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
