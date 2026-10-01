/// In-memory identity and storage doubles for the offline Summary runs.
///
/// Provider-neutral replacements for the auth application service and the
/// account-bound local sync store. No SDK, no network, no persistence, and no
/// credential: the tool and the widget tests share these doubles.
library;

import 'dart:async';

import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';

/// The mock account this environment signs in by default.
const String summaryMockAccountId = 'account-mock-1';

/// The id of the synthetic note seeded into every mock account store.
const String summaryMockNoteId = 'note-mock-1';

/// The body of the synthetic note; short enough for a direct stage call.
const String summaryMockNoteContent =
    'Phase 4.5 offline mock note: one saved revision, no real storage.';

/// Provider-neutral [IAuthenticationAppService] fake with no SDK behind it.
///
/// It keeps [session] in step the way the real service does: a sign-in records
/// the identity and announces it, and a sign-out clears the session and
/// announces `null`. Signing in after a sign-out advances the session
/// generation, exactly like a real account switch.
final class SummaryMockAuth implements IAuthenticationAppService {
  /// Creates a fake bound to [session].
  SummaryMockAuth({
    required this.session,
    this.accountUserId = summaryMockAccountId,
    this.email = 'mock@noteflow.local',
  });

  /// The application session this fake keeps in step.
  final CurrentUserSession session;

  /// The account the next sign-in uses.
  String accountUserId;

  /// The email the next sign-in uses.
  String email;

  /// Successful sign-ins; a smoke run reads it as evidence.
  int signInCount = 0;

  /// Successful sign-outs.
  int signOutCount = 0;

  final StreamController<AuthUserDto?> _events =
      StreamController<AuthUserDto?>.broadcast();
  bool _disposed = false;

  /// The identity this fake would record right now.
  AuthIdentity get identity =>
      AuthIdentity(userId: accountUserId, email: email, isEmailVerified: true);

  /// Signs an account in and advances the session generation.
  Future<AuthUserDto> signIn({String? email, String? userId}) async {
    final AuthIdentity next = AuthIdentity(
      userId: userId ?? accountUserId,
      email: email ?? this.email,
      isEmailVerified: true,
    );
    accountUserId = next.userId;
    this.email = next.email;
    session.setIdentity(next);
    signInCount++;
    final AuthUserDto dto = AuthUserDto.fromIdentity(next);
    if (!_disposed) {
      _events.add(dto);
    }
    return dto;
  }

  @override
  Future<AuthUserDto> login(LoginInput input) => signIn(email: input.email);

  @override
  Future<RegistrationResult> register(RegisterInput input) async {
    final AuthUserDto user = await signIn(email: input.email);
    return RegistrationResult(
      user: user,
      verificationDispatchStatus: VerificationDispatchStatus.notRequired,
    );
  }

  @override
  Future<void> logout() async {
    signOutCount++;
    session.clear();
    if (!_disposed) {
      _events.add(null);
    }
  }

  @override
  Future<AuthUserDto?> restoreSession() async {
    final AuthIdentity? current = session.identity;
    return current == null ? null : AuthUserDto.fromIdentity(current);
  }

  @override
  Stream<AuthUserDto?> observeAuthState() => _events.stream;

  @override
  Future<AuthUserDto> refreshIdentity() async =>
      AuthUserDto.fromIdentity(session.identity ?? identity);

  @override
  Future<void> resendEmailVerification() async {}

  @override
  Future<AuthUserDto> confirmEmailVerification({required String code}) async =>
      AuthUserDto.fromIdentity(session.identity ?? identity);

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {}

  /// Stops announcing auth events; the app owns the session lifetime.
  void dispose() {
    _disposed = true;
    _events.close();
  }
}

/// Account-bound, in-memory [ILocalSyncStore] seeded with one saved note.
final class SummaryMockSyncStore implements ILocalSyncStore {
  /// Creates a store for [accountUserId], seeded with [initial].
  SummaryMockSyncStore({required this.accountUserId, LocalSyncState? initial})
    : _state = initial ?? summaryMockLocalState(accountUserId: accountUserId);

  /// The account this store is bound to.
  final String accountUserId;

  LocalSyncState _state;

  /// Reads served; the tool overlay reads it as evidence.
  int readCount = 0;

  /// Writes accepted; the tool overlay reads it as evidence.
  int writeCount = 0;

  /// The live state, for assertions that need the persisted projection.
  LocalSyncState get state => _state;

  @override
  Future<LocalSyncState> read() async {
    readCount++;
    return _state;
  }

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async {
    writeCount++;
    return _state = transform(_state);
  }

  @override
  Future<void> replace(LocalSyncState state) async {
    writeCount++;
    _state = state;
  }
}

/// Builds the one-note account state the mock stores start from.
LocalSyncState summaryMockLocalState({
  required String accountUserId,
  String noteId = summaryMockNoteId,
  String noteTitle = 'Mock note',
  String noteContent = summaryMockNoteContent,
  DateTime? timestamp,
}) {
  final DateTime time = timestamp ?? DateTime.utc(2026, 10, 1);
  return LocalSyncState(
    accountUserId: accountUserId,
    notes: <LocalNoteState>[
      LocalNoteState(
        id: noteId,
        ownerId: accountUserId,
        title: noteTitle,
        content: noteContent,
        createdAt: time,
        updatedAt: time,
        serverRevision: 1,
      ),
    ],
  );
}

/// Account-keyed registry of the in-memory stores one run may touch.
///
/// The root app and the Summary run guard both resolve the store through the
/// same factory, so both must observe the same instance for one account.
final class SummaryMockStoreRegistry {
  final Map<String, SummaryMockSyncStore> _stores =
      <String, SummaryMockSyncStore>{};

  /// Returns the account store, seeding it with one synthetic note.
  SummaryMockSyncStore storeFor({required String accountUserId}) {
    return _stores.putIfAbsent(
      accountUserId,
      () => SummaryMockSyncStore(accountUserId: accountUserId),
    );
  }
}
