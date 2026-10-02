import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_sharing_app_service.dart';
import '../../application/notes/sharing_gateway.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';
import 'sharing_localizations.dart';

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
    return AlertDialog(
      title: Text(copy.manage),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(copy.onlineOnly),
              if (_reactivate != null)
                Text('${copy.share}: ${_reactivate!.recipientId}'),
              TextField(
                key: const ValueKey('share-recipient-email'),
                controller: _email,
                enabled: !_busy && _retry == null,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: copy.email),
              ),
              DropdownButton<NoteRole>(
                key: const ValueKey('share-recipient-role'),
                value: _role,
                items: NoteRole.values
                    .map(
                      (r) =>
                          DropdownMenuItem(value: r, child: Text(copy.role(r))),
                    )
                    .toList(),
                onChanged: _busy || _retry != null
                    ? null
                    : (r) => setState(() => _role = r!),
              ),
              FilledButton(
                key: const ValueKey('share-recipient-submit'),
                onPressed: _busy || _retry != null ? null : _create,
                child: Text(copy.share),
              ),
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

  @override
  void dispose() {
    _request++;
    unawaited(_subscription?.cancel());
    _email.dispose();
    super.dispose();
  }
}
