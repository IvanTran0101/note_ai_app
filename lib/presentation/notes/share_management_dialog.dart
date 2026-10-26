import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_sharing_app_service.dart';
import '../../application/notes/sharing_gateway.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';
import 'sharing_localizations.dart';
import 'share_management_surface.dart';
import 'notes_theme_tokens.dart';

part 'share_management_desktop.dart';

/// ACL administration is online and confirmed. No optimistic recipient access.
final class ShareManagementDialog extends StatefulWidget {
  const ShareManagementDialog({
    super.key,
    required this.service,
    required this.identity,
    required this.sessionEvents,
    required this.isCurrent,
  });
  final NoteSharingAppService service;
  final NoteIdentity identity;
  final Stream<void> sessionEvents;
  final bool Function() isCurrent;
  @override
  State<ShareManagementDialog> createState() => _ShareManagementState();
}

final class _ShareManagementState extends State<ShareManagementDialog> {
  final _email = TextEditingController();
  List<NoteShareGrant> _shares = const [];
  NoteRole _role = NoteRole.viewer;
  ShareCommand? _retry;
  NoteShareGrant? _reactivate;
  ShareFailureCode? _error;
  bool _busy = true;
  int _request = 0;
  StreamSubscription<void>? _subscription;
  bool get _live => mounted && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    _subscription = widget.sessionEvents.listen((_) {
      if (mounted && !widget.isCurrent()) {
        _request++;
        Navigator.of(context).pop();
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!_live) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final shares = await widget.service.list(widget.identity);
      if (_live && request == _request) setState(() => _shares = shares);
    } on ShareFailure catch (failure) {
      if (_live && request == _request) setState(() => _error = failure.code);
    } on Object {
      if (_live && request == _request) {
        setState(() => _error = ShareFailureCode.unavailable);
      }
    } finally {
      if (_live && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _apply(ShareCommand command) async {
    if (!_live || _busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _retry = command;
    });
    try {
      final share = await widget.service.apply(widget.identity, command);
      if (!_live || request != _request) return;
      setState(() {
        _shares = [
          ..._shares.where((s) => s.recipientId != share.recipientId),
          share,
        ];
        _retry = null;
        _reactivate = null;
        _email.clear();
      });
    } on ShareFailure catch (failure) {
      if (!_live || request != _request) return;
      setState(() {
        _error = failure.code;
        // Only uncertain transport results reuse the exact command/fingerprint.
        if (failure.code != ShareFailureCode.network &&
            failure.code != ShareFailureCode.unavailable) {
          _retry = null;
        }
      });
    } on Object {
      if (_live && request == _request) {
        setState(() => _error = ShareFailureCode.unavailable);
      }
    } finally {
      if (_live && request == _request) setState(() => _busy = false);
    }
  }

  void _create() {
    try {
      unawaited(
        _apply(
          widget.service.create(
            _email.text,
            _role,
            expectedAccessRevision: _reactivate?.accessRevision ?? 0,
          ),
        ),
      );
    } on ShareFailure catch (failure) {
      setState(() => _error = failure.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = SharingCopy(context);
    final tokens = NoteFlowUiTokens.of(context);
    final compact = NoteFlowLayout.isCompact(context);
    final webPanel = !compact && MediaQuery.sizeOf(context).width >= 900;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy || _error != null)
          Text(
            copy.onlineOnly,
            style: TextStyle(fontSize: 13, color: tokens.textSecondary),
          ),
        if (_reactivate != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${copy.share}: ${_reactivate!.recipientId}',
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            ),
          ),
        _inviteForm(copy, tokens),
        const SizedBox(height: 12),
        Divider(height: 1, color: tokens.divider),
        const SizedBox(height: 8),
        if (_busy) ...[const LinearProgressIndicator(), Text(copy.loading)],
        if (_error != null)
          ShareErrorNotice(
            message: copy.failure(_error!),
            tokens: tokens,
            action: compact
                ? Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _retryButton(copy),
                  )
                : null,
          ),
        if (_shares.isEmpty && !_busy) Text(copy.noRecipients),
        ..._shares.map(
          (share) => ShareRecipientRow(
            share: share,
            copy: copy,
            compact: compact,
            enabled: !_busy && _retry == null,
            onChangeRole: () => unawaited(
              _apply(
                widget.service.change(
                  share,
                  share.role == NoteRole.viewer
                      ? NoteRole.editor
                      : NoteRole.viewer,
                ),
              ),
            ),
            onRevoke: () =>
                unawaited(_apply(widget.service.change(share, null))),
            onReactivate: () => setState(() {
              _reactivate = share;
              _role = share.role;
              _error = null;
            }),
          ),
        ),
      ],
    );
    if (compact) {
      return ShareManagementSurface(
        title: copy.manage,
        closeLabel: copy.close,
        onClose: () => Navigator.of(context).pop(),
        content: body,
        tokens: tokens,
      );
    }
    return _desktopDialog(copy, tokens, webPanel: webPanel, body: body);
  }

  Widget _retryButton(SharingCopy copy) => TextButton(
    key: const ValueKey('share-retry'),
    onPressed: _busy
        ? null
        : () => unawaited(_retry == null ? _load() : _apply(_retry!)),
    child: Text(copy.retry),
  );

  Widget _inviteForm(SharingCopy copy, NoteFlowUiTokens tokens) {
    final email = _inviteEmail(copy, tokens);
    final role = _inviteRole(copy);
    final webPanel =
        !NoteFlowLayout.isCompact(context) &&
        MediaQuery.sizeOf(context).width >= 900;
    final submit = FilledButton(
      key: const ValueKey('share-recipient-submit'),
      onPressed: _busy || _retry != null ? null : _create,
      style: FilledButton.styleFrom(
        minimumSize: webPanel ? const Size(64, 32) : const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: webPanel ? 12 : 16),
        textStyle: const TextStyle(fontSize: 14),
        visualDensity: webPanel
            ? VisualDensity.compact
            : VisualDensity.standard,
        tapTargetSize: webPanel
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
      ),
      child: Text(copy.share),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledFont = MediaQuery.textScalerOf(context).scale(14);
        final needsVerticalControls =
            constraints.maxWidth < 280 || scaledFont > 28;
        final inviteRow = Row(
          children: [
            Expanded(child: email),
            const SizedBox(width: 8),
            submit,
          ],
        );
        final roleRow = Align(
          alignment: AlignmentDirectional.centerEnd,
          child: role,
        );
        if (needsVerticalControls) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [email, const SizedBox(height: 8), role, submit],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [inviteRow, const SizedBox(height: 4), roleRow],
        );
      },
    );
  }

  Widget _inviteEmail(SharingCopy copy, NoteFlowUiTokens tokens) =>
      ShareInviteField(
        controller: _email,
        enabled: !_busy && _retry == null,
        label: copy.email,
        compact: NoteFlowLayout.isCompact(context),
        tokens: tokens,
      );

  Widget _inviteRole(SharingCopy copy) => DropdownButtonHideUnderline(
    child: DropdownButton<NoteRole>(
      key: const ValueKey('share-recipient-role'),
      value: _role,
      items: NoteRole.values
          .map(
            (r) => DropdownMenuItem(
              value: r,
              child: Text(copy.role(r), style: const TextStyle(fontSize: 14)),
            ),
          )
          .toList(),
      onChanged: _busy || _retry != null
          ? null
          : (r) => setState(() => _role = r!),
    ),
  );

  @override
  void dispose() {
    _request++;
    unawaited(_subscription?.cancel());
    _email.dispose();
    super.dispose();
  }
}

final class ShareErrorNotice extends StatelessWidget {
  const ShareErrorNotice({
    super.key,
    required this.message,
    required this.tokens,
    this.action,
  });

  final String message;
  final NoteFlowUiTokens tokens;
  final Widget? action;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: tokens.error.withAlpha(16),
      border: Border.all(color: tokens.error.withAlpha(96)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.error_outline, size: 18, color: tokens.error),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const ValueKey('share-error'),
                    style: TextStyle(fontSize: 14, color: tokens.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          ?action,
        ],
      ),
    ),
  );
}
