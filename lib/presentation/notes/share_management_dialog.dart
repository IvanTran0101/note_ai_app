import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_sharing_app_service.dart';
import '../../application/notes/sharing_gateway.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';
import 'sharing_localizations.dart';
import 'notes_theme_tokens.dart';

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

  Widget _recipient(NoteShareGrant share, SharingCopy copy) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(share.recipientId, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(
          '${copy.status(share)} · ${share.updatedAt.toLocal().toIso8601String().split('.').first}',
        ),
        if (share.isActive)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy || _retry != null
                    ? null
                    : () => unawaited(
                        _apply(
                          widget.service.change(
                            share,
                            share.role == NoteRole.viewer
                                ? NoteRole.editor
                                : NoteRole.viewer,
                          ),
                        ),
                      ),
                child: Text(
                  copy.role(
                    share.role == NoteRole.viewer
                        ? NoteRole.editor
                        : NoteRole.viewer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy || _retry != null
                    ? null
                    : () =>
                          unawaited(_apply(widget.service.change(share, null))),
                child: Text(copy.revoke),
              ),
            ],
          )
        else
          TextButton(
            onPressed: _busy || _retry != null
                ? null
                : () => setState(() {
                    _reactivate = share;
                    _role = share.role;
                    _error = null;
                  }),
            child: Text(copy.share),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final copy = SharingCopy(context);
    final tokens = NoteFlowUiTokens.of(context);
    final compact = NoteFlowLayout.isCompact(context);
    return AlertDialog(
      alignment: compact ? Alignment.bottomCenter : Alignment.topRight,
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
          : const EdgeInsets.fromLTRB(24, 76, 20, 24),
      backgroundColor: tokens.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 20 : 12),
        side: BorderSide(color: tokens.divider),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      title: Row(
        children: [
          Icon(Icons.people_outline, size: 20, color: tokens.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              copy.manage,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy || _error != null) Text(copy.onlineOnly),
              if (_reactivate != null)
                Text('${copy.share}: ${_reactivate!.recipientId}'),
              _inviteForm(copy, tokens),
              const SizedBox(height: 16),
              if (_busy) ...[
                const LinearProgressIndicator(),
                Text(copy.loading),
              ],
              if (_error != null)
                Text(copy.failure(_error!), key: const ValueKey('share-error')),
              if (_shares.isEmpty && !_busy) Text(copy.noRecipients),
              ..._shares.map((share) => _recipient(share, copy)),
            ],
          ),
        ),
      ),
      actions: [
        if (_error != null)
          TextButton(
            key: const ValueKey('share-retry'),
            onPressed: _busy
                ? null
                : () => unawaited(_retry == null ? _load() : _apply(_retry!)),
            child: Text(copy.retry),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.close),
        ),
      ],
    );
  }

  Widget _inviteForm(SharingCopy copy, NoteFlowUiTokens tokens) {
    final email = _inviteEmail(copy, tokens);
    final role = _inviteRole(copy);
    final submit = FilledButton(
      key: const ValueKey('share-recipient-submit'),
      onPressed: _busy || _retry != null ? null : _create,
      child: Text(copy.share),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 400 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        if (narrow) {
          return Column(
            children: [
              email,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: role),
                  submit,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: email),
            const SizedBox(width: 12),
            role,
            const SizedBox(width: 12),
            submit,
          ],
        );
      },
    );
  }

  Widget _inviteEmail(SharingCopy copy, NoteFlowUiTokens tokens) => TextField(
    key: const ValueKey('share-recipient-email'),
    controller: _email,
    enabled: !_busy && _retry == null,
    keyboardType: TextInputType.emailAddress,
    decoration: InputDecoration(
      labelText: copy.email,
      filled: true,
      fillColor: tokens.subtleSurface,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: tokens.divider),
      ),
    ),
  );

  Widget _inviteRole(SharingCopy copy) => DropdownButtonHideUnderline(
    child: DropdownButton<NoteRole>(
      key: const ValueKey('share-recipient-role'),
      value: _role,
      items: NoteRole.values
          .map((r) => DropdownMenuItem(value: r, child: Text(copy.role(r))))
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
