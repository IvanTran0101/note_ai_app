part of 'profile_page.dart';

/// Presentation-only views of the Profile screen.
///
/// Split from the stateful screen along the state/render boundary: nothing here
/// reads the service, starts an operation, or decides what the profile is; every
/// value and callback arrives from [_ProfilePageState].

final class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.copy});

  final ProfileCopy copy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: copy.loading,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(key: ProfilePageKeys.loading),
            const SizedBox(height: NoteFlowSpacing.md),
            Text(
              copy.loading,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: NoteFlowUiTokens.of(context).textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

final class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.copy, required this.onRetry});

  final ProfileCopy copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NoteFlowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, size: 32, color: tokens.textMuted),
            const SizedBox(height: NoteFlowSpacing.md),
            Text(
              copy.loadError,
              key: ProfilePageKeys.loadError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: NoteFlowSpacing.lg),
            FilledButton(
              key: ProfilePageKeys.retry,
              onPressed: onRetry,
              child: Text(copy.retry),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.copy,
    required this.name,
    required this.snapshot,
    required this.loading,
    required this.saving,
    required this.loadFailed,
    required this.saved,
    required this.actionError,
    required this.actionRetryable,
    required this.liveNameError,
    required this.onRetry,
    required this.onSaveName,
    required this.onChangeAvatar,
    required this.onRemoveAvatar,
    required this.onNameChanged,
  });

  final ProfileCopy copy;
  final TextEditingController name;
  final ProfileSnapshot snapshot;
  final bool loading;
  final bool saving;
  final bool loadFailed;
  final bool saved;
  final String? actionError;
  final bool actionRetryable;
  final String? liveNameError;
  final VoidCallback onRetry;
  final VoidCallback onSaveName;
  final VoidCallback onChangeAvatar;
  final VoidCallback onRemoveAvatar;
  final ValueChanged<String> onNameChanged;

  bool get _busy => loading || saving;

  @override
  Widget build(BuildContext context) {
    final UserProfile? profile = snapshot.profile;
    return ListView(
      padding: const EdgeInsets.all(NoteFlowSpacing.xl),
      children: <Widget>[
        if (loadFailed) ...<Widget>[
          _StatusRow(
            key: ProfilePageKeys.loadError,
            icon: Icons.cloud_off_outlined,
            message: copy.loadError,
            actionLabel: copy.retry,
            onAction: _busy ? null : onRetry,
            error: true,
          ),
          const SizedBox(height: NoteFlowSpacing.lg),
        ],
        if (profile == null) ...<Widget>[
          _setupCard(context),
          const SizedBox(height: NoteFlowSpacing.xl),
        ],
        _avatarSection(context, profile: profile),
        const SizedBox(height: NoteFlowSpacing.xl),
        _nameField(context),
        const SizedBox(height: NoteFlowSpacing.lg),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            key: ProfilePageKeys.saveName,
            onPressed: _busy ? null : onSaveName,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(profile == null ? copy.createProfile : copy.saveName),
          ),
        ),
        if (saving) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.lg),
          Semantics(
            liveRegion: true,
            label: copy.saving,
            child: const LinearProgressIndicator(key: ProfilePageKeys.saving),
          ),
        ],
        if (saved && !saving) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.lg),
          Semantics(
            liveRegion: true,
            child: Text(
              copy.saved,
              key: ProfilePageKeys.saved,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: NoteFlowUiTokens.of(context).success),
            ),
          ),
        ],
        if (actionError != null && !saving) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.lg),
          _StatusRow(
            key: ProfilePageKeys.actionError,
            icon: Icons.error_outline,
            message: actionError!,
            actionLabel: actionRetryable ? copy.reload : null,
            onAction: actionRetryable && !_busy ? onRetry : null,
            error: true,
          ),
        ],
      ],
    );
  }

  /// Explicit setup state: the account has no stored profile yet, so the screen
  /// says so instead of pretending a blank profile is the canonical one.
  Widget _setupCard(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return NoteFlowSurface(
      key: ProfilePageKeys.setup,
      tone: NoteFlowSurfaceTone.elevated,
      radius: NoteFlowRadius.card,
      bordered: true,
      padding: const EdgeInsets.all(NoteFlowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(copy.setupTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: NoteFlowSpacing.sm),
          Text(
            copy.setupBody,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _avatarSection(BuildContext context, {required UserProfile? profile}) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool hasAvatar = profile?.avatarReference != null;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget preview = _AvatarPreview(
          bytes: snapshot.avatarBytes,
          copy: copy,
        );
        final Widget actions = _avatarActions(
          context,
          tokens,
          hasAvatar,
          profile,
        );
        if (constraints.maxWidth < NoteFlowLayout.compactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              preview,
              const SizedBox(height: NoteFlowSpacing.lg),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            preview,
            const SizedBox(width: NoteFlowSpacing.lg),
            Expanded(child: actions),
          ],
        );
      },
    );
  }

  Widget _avatarActions(
    BuildContext context,
    NoteFlowUiTokens tokens,
    bool hasAvatar,
    UserProfile? profile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NoteFlowSectionLabel(label: copy.avatarLabel, padding: EdgeInsets.zero),
        const SizedBox(height: NoteFlowSpacing.xs),
        Text(
          copy.avatarRules,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: NoteFlowSpacing.sm),
        Wrap(
          spacing: NoteFlowSpacing.sm,
          runSpacing: NoteFlowSpacing.xs,
          children: <Widget>[
            FilledButton.tonalIcon(
              key: ProfilePageKeys.pickAvatar,
              onPressed: _busy || profile == null ? null : onChangeAvatar,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(hasAvatar ? copy.changeAvatar : copy.addAvatar),
            ),
            if (hasAvatar)
              TextButton(
                key: ProfilePageKeys.removeAvatar,
                onPressed: _busy ? null : onRemoveAvatar,
                child: Text(copy.removeAvatar),
              ),
          ],
        ),
        if (profile == null) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.sm),
          Text(
            copy.avatarSetupHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _nameField(BuildContext context) {
    return TextField(
      key: ProfilePageKeys.nameField,
      controller: name,
      enabled: !_busy,
      maxLines: 1,
      textInputAction: TextInputAction.done,
      onChanged: onNameChanged,
      onSubmitted: (_) => onSaveName(),
      decoration: InputDecoration(
        labelText: copy.displayNameLabel,
        helperText: copy.displayNameHelper,
        errorText: liveNameError,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

final class _StatusRow extends StatelessWidget {
  const _StatusRow({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.error = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final Color color = error ? tokens.error : tokens.textSecondary;
    final double bodyFontSize =
        Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;
    final bool useStackedAction =
        MediaQuery.textScalerOf(context).scale(bodyFontSize) > bodyFontSize;
    return Semantics(
      liveRegion: true,
      container: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget status = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: NoteFlowSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: color),
                ),
              ),
            ],
          );
          if (actionLabel == null) {
            return status;
          }
          final Widget action = TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          );
          final bool compact =
              constraints.maxWidth < NoteFlowLayout.compactBreakpoint;
          if (compact || useStackedAction) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                status,
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: action,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: status),
              action,
            ],
          );
        },
      ),
    );
  }
}

final class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.bytes, required this.copy});

  final Uint8List? bytes;
  final ProfileCopy copy;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final Uint8List? avatar = bytes;
    final bool hasImage = avatar != null && avatar.isNotEmpty;
    return Semantics(
      image: hasImage,
      label: copy.avatarLabel,
      child: CircleAvatar(
        key: ProfilePageKeys.avatarPreview,
        radius: 36,
        backgroundColor: tokens.subtleSurface,
        // The avatar is read as bytes through the authenticated route and shown
        // from memory, so Web never needs authorization headers on Image.network.
        foregroundImage: hasImage ? MemoryImage(avatar) : null,
        child: hasImage
            ? null
            : Icon(Icons.person_outline, size: 32, color: tokens.textMuted),
      ),
    );
  }
}
