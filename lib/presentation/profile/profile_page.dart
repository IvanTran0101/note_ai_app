import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/users/profile_app_service.dart';
import '../../application/users/profile_snapshot.dart';
import '../../domain/users/profile_avatar_gateway.dart';
import '../../domain/users/profile_failure.dart';
import '../../domain/users/user_profile.dart';
import '../common/note_flow_primitives.dart';
import '../notes/notes_theme_tokens.dart';
import 'profile_copy.dart';

part 'profile_page_sections.dart';

/// Test-visible identities of the states and controls on the Profile screen.
abstract final class ProfilePageKeys {
  static const Key loading = ValueKey<String>('profile-loading');
  static const Key loadError = ValueKey<String>('profile-load-error');
  static const Key retry = ValueKey<String>('profile-retry');
  static const Key setup = ValueKey<String>('profile-setup');
  static const Key nameField = ValueKey<String>('profile-name-field');
  static const Key saveName = ValueKey<String>('profile-save-name');
  static const Key avatarPreview = ValueKey<String>('profile-avatar-preview');
  static const Key pickAvatar = ValueKey<String>('profile-pick-avatar');
  static const Key removeAvatar = ValueKey<String>('profile-remove-avatar');
  static const Key saving = ValueKey<String>('profile-saving');
  static const Key saved = ValueKey<String>('profile-saved');
  static const Key actionError = ValueKey<String>('profile-action-error');
}

/// The signed-in account's profile screen: display name and avatar.
///
/// The screen is a passive renderer of [ProfileAppService] state. It never
/// decides what the profile is: the service loads the canonical snapshot, saves
/// the name, and owns avatar staging. This widget owns only the presentation
/// lifecycle — loading, busy, saved, and localized failure — plus the fence that
/// discards a response belonging to a superseded request or account binding.
///
/// A failed save or replacement never rewrites what is on screen: the previous
/// snapshot is kept until the service returns a new one, so an account keeps its
/// avatar when a replacement is refused. Overlapping actions are disabled while
/// one is in flight, and only a successful name save writes back to the name
/// field, so a slower avatar result can never revert a committed name.
final class ProfilePage extends StatefulWidget {
  /// Creates the Profile screen over the application service.
  ///
  /// [pickAvatar] is the platform chooser port: it returns uploadable bytes or
  /// `null` when the user cancelled, and it is only called from an explicit
  /// user action.
  const ProfilePage({
    super.key,
    required this.service,
    required this.pickAvatar,
    required this.onChanged,
    this.onBack,
    this.initialDisplayName,
  });

  /// Account-scoped profile use cases.
  final ProfileAppService service;

  /// Opens the platform image chooser; `null` means the user cancelled.
  final Future<Uint8List?> Function() pickAvatar;

  /// Reports every snapshot this screen successfully applied, so the shell and
  /// Home can render the same account's name and avatar.
  final ValueChanged<ProfileSnapshot> onChanged;
  final VoidCallback? onBack;
  final String? initialDisplayName;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

final class _ProfilePageState extends State<ProfilePage>
    with WidgetsBindingObserver {
  final TextEditingController _name = TextEditingController();

  ProfileSnapshot? _snapshot;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  bool _actionSaved = false;
  String? _actionError;
  bool _actionRetryable = false;

  /// Fences a load response that a newer load (or account binding) replaced.
  int _loadSequence = 0;

  /// Fences a mutation response that a newer mutation replaced, so a slow avatar
  /// upload cannot overwrite a name that was committed after it started.
  int _actionSequence = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.service, widget.service)) {
      return;
    }
    // A different service is a different account binding: drop what is on
    // screen and fence whatever the previous binding still has in flight.
    _loadSequence++;
    _actionSequence++;
    _snapshot = null;
    _name.clear();
    _saving = false;
    _actionError = null;
    _actionSaved = false;
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final committedName = _snapshot?.profile?.displayName ?? '';
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        !_saving &&
        _name.text.trim() == committedName) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    super.dispose();
  }

  bool _isCurrentLoad(int sequence) => mounted && sequence == _loadSequence;

  bool _isCurrentAction(int sequence) => mounted && sequence == _actionSequence;

  Future<void> _load() async {
    final int sequence = ++_loadSequence;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _actionSaved = false;
      // A reload supersedes whatever the last refused write reported.
      _actionError = null;
      _actionRetryable = false;
    });
    try {
      final ProfileSnapshot snapshot = await widget.service.load();
      if (!_isCurrentLoad(sequence)) {
        return;
      }
      setState(() {
        _loading = false;
        _snapshot = snapshot;
        _syncName(
          snapshot.profile?.displayName ?? widget.initialDisplayName ?? '',
        );
      });
      widget.onChanged(snapshot);
    } on Object {
      if (!_isCurrentLoad(sequence)) {
        return;
      }
      // A refresh that fails keeps the profile that is already on screen; only
      // a first load leaves the screen without data.
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Runs one account mutation: busy state, stale fence, typed failures, and
  /// snapshot application all live here.
  ///
  /// The operation returns `null` when the user cancelled a chooser, which
  /// changes nothing and makes no request.
  Future<void> _runMutation(
    Future<ProfileSnapshot?> Function() operation, {
    required bool syncName,
    bool avatar = false,
  }) async {
    if (_loading || _saving) {
      return;
    }
    final ProfileCopy copy = ProfileCopy.of(context);
    final int sequence = ++_actionSequence;
    setState(() {
      _saving = true;
      _actionSaved = false;
      _actionError = null;
      _actionRetryable = false;
    });
    final ProfileSnapshot? snapshot;
    try {
      snapshot = await operation();
    } on ProfileFailure catch (failure) {
      if (!_isCurrentAction(sequence)) {
        return;
      }
      setState(() {
        _saving = false;
        _actionError = _messageFor(copy, failure.code, avatar: avatar);
        _actionRetryable =
            failure.code == ProfileFailureCode.conflict ||
            failure.code == ProfileFailureCode.unavailable;
      });
      return;
    } on Object {
      if (!_isCurrentAction(sequence)) {
        return;
      }
      setState(() {
        _saving = false;
        _actionError = avatar ? copy.avatarError : copy.saveError;
      });
      return;
    }
    if (!_isCurrentAction(sequence)) {
      return;
    }
    if (snapshot == null) {
      // Cancelled: no request was made and the visible state already matches.
      setState(() => _saving = false);
      return;
    }
    final ProfileSnapshot applied = snapshot;
    setState(() {
      _saving = false;
      _actionSaved = true;
      _snapshot = applied;
      if (syncName) {
        _syncName(applied.profile?.displayName ?? '');
      }
    });
    widget.onChanged(applied);
  }

  Future<void> _saveName() async {
    if (_loading || _saving) {
      return;
    }
    final ProfileCopy copy = ProfileCopy.of(context);
    final String name = _name.text.trim();
    // Local guard for immediate feedback; the domain object and the server
    // still validate the committed value.
    if (name.isEmpty) {
      _rejectName(copy.nameRequired);
      return;
    }
    if (name.runes.length > UserProfile.maxDisplayNameRunes) {
      _rejectName(copy.nameTooLong);
      return;
    }
    await _runMutation(
      () async => widget.service.saveName(name),
      syncName: true,
    );
  }

  Future<void> _changeAvatar() async {
    // No stored profile means the account is in explicit setup: a name has to
    // be committed before an avatar can be associated with it.
    if (_snapshot?.profile == null) {
      return;
    }
    final service = widget.service;
    final generation = service.session.sessionGeneration;
    final actor = service.session.userId;
    await _runMutation(
      () async {
        final sequence = _actionSequence;
        final Uint8List? picked = await widget.pickAvatar();
        if (picked == null ||
            !_isCurrentAction(sequence) ||
            !identical(service, widget.service) ||
            service.session.sessionGeneration != generation ||
            service.session.userId != actor) {
          return null;
        }
        // The picker always returns a re-encoded PNG, so the declared type is
        // fixed here instead of being guessed from the original file.
        return service.uploadAvatar(picked, ProfileAvatarRules.pngMime);
      },
      syncName: false,
      avatar: true,
    );
  }

  Future<void> _removeAvatar() async {
    if (_snapshot?.profile?.avatarReference == null) {
      return;
    }
    await _runMutation(
      () async => widget.service.removeAvatar(),
      syncName: false,
      avatar: true,
    );
  }

  void _rejectName(String message) {
    setState(() {
      _actionSaved = false;
      _actionError = message;
      _actionRetryable = false;
    });
  }

  void _syncName(String displayName) {
    if (_name.text == displayName) {
      return;
    }
    _name.text = displayName;
  }

  String _messageFor(
    ProfileCopy copy,
    ProfileFailureCode code, {
    required bool avatar,
  }) {
    return switch (code) {
      ProfileFailureCode.invalid =>
        avatar ? copy.avatarInvalid : copy.invalidInput,
      ProfileFailureCode.conflict => copy.conflict,
      ProfileFailureCode.unavailable => copy.unavailable,
      ProfileFailureCode.unauthorized => copy.sessionChanged,
    };
  }

  String? _liveNameError(ProfileCopy copy) {
    final String text = _name.text.trim();
    if (text.isEmpty) {
      // An empty field is reported when the user asks to save it, not while the
      // field is still being filled in.
      return null;
    }
    return text.runes.length > UserProfile.maxDisplayNameRunes
        ? copy.nameTooLong
        : null;
  }

  void _onNameChanged(String value) {
    setState(() {
      _actionSaved = false;
      if (_actionError != null) {
        _actionError = null;
        _actionRetryable = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ProfileCopy copy = ProfileCopy.of(context);
    final ProfileSnapshot? snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
        title: Text(copy.title),
        actions: [
          IconButton(
            tooltip: copy.reload,
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: NoteFlowLayout.dashboardContentMaxWidth,
            ),
            child: switch (snapshot) {
              null when _loading => _LoadingView(copy: copy),
              null => _LoadErrorView(copy: copy, onRetry: _load),
              final ProfileSnapshot loaded => _ProfileBody(
                copy: copy,
                name: _name,
                snapshot: loaded,
                loading: _loading,
                saving: _saving,
                loadFailed: _loadFailed,
                saved: _actionSaved,
                actionError: _actionError,
                actionRetryable: _actionRetryable,
                liveNameError: _liveNameError(copy),
                onRetry: _load,
                onSaveName: _saveName,
                onChangeAvatar: _changeAvatar,
                onRemoveAvatar: _removeAvatar,
                onNameChanged: _onNameChanged,
              ),
            },
          ),
        ),
      ),
    );
  }
}
