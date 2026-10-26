import 'dart:async';

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
       _initializationCompleted = initialUser != null {
    final IAuthenticationAppService? service = authenticationAppService;
    if (service != null) {
      _authStateSubscription = service.observeAuthState().listen(
        _onAuthStateChanged,
        onError: _onAuthStateError,
      );
    }
  }

  /// Null only for the local compatibility bootstrap, where [initialUser]
  /// already represents the authenticated demo session.
  final IAuthenticationAppService? authenticationAppService;

  AuthState _state;
  bool _disposed = false;
  bool _initializationCompleted;
  StreamSubscription<AuthUserDto?>? _authStateSubscription;

  /// Shared in-flight restore backing [initialize]; see [initialize].
  Future<AuthUserDto?>? _inFlightRestore;

  /// Sequence of the most recently started operation; see [_beginOperation].
  int _operationSeq = 0;

  /// Sequence of the operation currently in flight, `null` when idle.
  ///
  /// Tracked independently of auth-state events, which report the hub's view
  /// without ending an in-flight operation.
  int? _runningOperation;

  AuthState get state => _state;

  String? pendingProfileDisplayName;

  void _onAuthStateChanged(AuthUserDto? user) {
    if (_disposed) {
      return;
    }
    if (user?.userId != _state.user?.userId) pendingProfileDisplayName = null;
    _initializationCompleted = true;
    // An in-flight operation owns the busy flag: the hub event reports the
    // user it saw without ending the operation, so a second operation stays
    // rejected until the running one completes or fails.
    final bool isBusy = _runningOperation != null;
    _emit(
      user == null
          ? AuthState.unauthenticated(isBusy: isBusy)
          : AuthState.authenticated(user: user, isBusy: isBusy),
    );
  }

  void _onAuthStateError(Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }
    _emit(_failureState(error));
  }

  IAuthenticationAppService get _service {
    final IAuthenticationAppService? service = authenticationAppService;
    if (service == null) {
      throw StateError('Authentication is unavailable in local mode.');
    }
    return service;
  }

  /// Restores the provider session once, coalescing concurrent callers.
  ///
  /// Concurrent calls share one in-flight restore:
  /// [IAuthenticationAppService.restoreSession] runs a single time and every
  /// caller awaits the same future with the same terminal state. The shared
  /// future is cleared once it settles, so a failed or superseded restore
  /// stays retryable, while a completed initialization short-circuits
  /// idempotently.
  ///
  /// The restore participates in the operation fence like every other
  /// operation. Before starting a new restore it obeys the same busy admission
  /// as every other operation: a pending login or registration is never
  /// superseded by initialization. A caller that joins an already-running
  /// shared restore is not blocked by that shared operation, and a completed
  /// initialization stays an idempotent no-op.
  ///
  /// When a newer operation — a logout, for example — supersedes a pending
  /// restore, the late result or error still returns or throws to its own
  /// caller, but it no longer overwrites the state the newer operation
  /// published, and initialization stays retryable.
  Future<AuthUserDto?> initialize() async {
    _ensureActive();
    if (_initializationCompleted) {
      return _state.user;
    }
    final Future<AuthUserDto?>? pending = _inFlightRestore;
    if (pending != null) {
      return pending;
    }
    // A completed initialization short-circuits above and coalesced callers
    // join their own in-flight restore above, so only a genuinely new restore
    // reaches this admission check.
    _ensureNotBusy();
    return _inFlightRestore = _startSharedRestore();
  }

  /// Runs the fenced restore shared by every coalesced [initialize] caller.
  ///
  /// Exactly one operation is begun for the shared run, so coalesced callers
  /// neither emit nor fence against each other. Terminal emits and the
  /// completion flag are gated on that sequence; the memo is cleared in
  /// [finally] so both failed and superseded runs leave [initialize]
  /// retryable.
  Future<AuthUserDto?> _startSharedRestore() async {
    final int sequence = _beginOperation();
    _emit(const AuthState.initializing(isBusy: true));
    try {
      final AuthUserDto? user = await _service.restoreSession();
      if (_isCurrentOperation(sequence)) {
        _initializationCompleted = true;
        _emit(
          user == null
              ? const AuthState.unauthenticated()
              : AuthState.authenticated(user: user),
        );
      }
      return user;
    } on Object catch (error, stackTrace) {
      if (_isCurrentOperation(sequence)) {
        // A Hub event may mark completion before this restore fails; keep Retry usable.
        _initializationCompleted = false;
        _emit(AuthState.initializing(error: _mapError(error)));
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _endOperation(sequence);
      // Only this shared future can be memoized while it is in flight, so
      // an unconditional clear keeps failures and superseded runs retryable.
      _inFlightRestore = null;
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
        pendingProfileDisplayName = result.profileSetupPending
            ? input.displayName.trim()
            : null;
        _initializationCompleted = true;
        return AuthState.authenticated(user: result.user);
      },
    );
  }

  Future<void> logout() async {
    pendingProfileDisplayName = null;
    _ensureActive();
    // Sign-out is never blocked by an in-flight operation: it supersedes it,
    // and the superseded operation's completion no longer emits state.
    final int sequence = _beginOperation();
    if (authenticationAppService == null) {
      _emit(const AuthState.unauthenticated());
      _endOperation(sequence);
      return;
    }
    _emit(_busyState());
    try {
      await _service.logout();
      if (_isCurrentOperation(sequence)) {
        _emit(const AuthState.unauthenticated());
      }
    } on Object catch (error, stackTrace) {
      // AuthenticationAppService clears its local session in finally, even
      // when the provider sign-out fails.
      if (_isCurrentOperation(sequence)) {
        _emit(AuthState.unauthenticated(error: _mapError(error)));
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _endOperation(sequence);
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
    final int sequence = _beginOperation();
    _emit(_busyState());
    try {
      final T result = await operation();
      if (_isCurrentOperation(sequence)) {
        _emit(onSuccess(result));
      }
      return result;
    } on Object catch (error, stackTrace) {
      if (_isCurrentOperation(sequence)) {
        _emit(_failureState(error));
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _endOperation(sequence);
    }
  }

  Future<void> _executeVoid(Future<void> Function() operation) async {
    _ensureActive();
    _ensureNotBusy();
    final int sequence = _beginOperation();
    _emit(_busyState());
    try {
      await operation();
      if (_isCurrentOperation(sequence)) {
        _emit(_stableState());
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrentOperation(sequence)) {
        _emit(_failureState(error));
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _endOperation(sequence);
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
    if (_runningOperation != null) {
      throw StateError('Authentication operation already in progress.');
    }
  }

  /// Starts an operation: advances the sequence and marks it in flight.
  ///
  /// Only the latest sequence may emit state on completion or error, so a
  /// superseded operation — for example a login that a logout overtook —
  /// returns or throws to its own caller without overwriting the state the
  /// newer operation published.
  int _beginOperation() {
    _operationSeq++;
    _runningOperation = _operationSeq;
    return _operationSeq;
  }

  bool _isCurrentOperation(int sequence) => sequence == _operationSeq;

  void _endOperation(int sequence) {
    if (_runningOperation == sequence) {
      _runningOperation = null;
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
    final StreamSubscription<AuthUserDto?>? subscription =
        _authStateSubscription;
    _authStateSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
