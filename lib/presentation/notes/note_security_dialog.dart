import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_access.dart';
import '../../application/notes/note_security_gateway.dart';
import '../../application/notes/note_security_service.dart';
import 'note_security_localizations.dart';

Future<bool?> showNoteSecurityDialog({
  required BuildContext context,
  required NoteSecurityService service,
  required String noteId,
  required NoteSecurityAction action,
  required bool serverAvailable,
  required Stream<void> sessionEvents,
  required bool Function() isCurrent,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SecurityDialog(
    service: service,
    noteId: noteId,
    action: action,
    serverAvailable: serverAvailable,
    sessionEvents: sessionEvents,
    isCurrent: isCurrent,
  ),
);

final class _SecurityDialog extends StatefulWidget {
  const _SecurityDialog({
    required this.service,
    required this.noteId,
    required this.action,
    required this.serverAvailable,
    required this.sessionEvents,
    required this.isCurrent,
  });
  final NoteSecurityService service;
  final String noteId;
  final NoteSecurityAction action;
  final bool serverAvailable;
  final Stream<void> sessionEvents;
  final bool Function() isCurrent;
  @override
  State<_SecurityDialog> createState() => _SecurityDialogState();
}

final class _SecurityDialogState extends State<_SecurityDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(), _password = TextEditingController();
  final _confirmation = TextEditingController(), _otp = TextEditingController();
  StreamSubscription<void>? _sessionSubscription;
  NoteRecoveryChallenge? _challenge;
  NoteSecurityFailureCode? _failure;
  bool _busy = false, _offline = false, _disposed = false;
  bool get _recovery => widget.action == NoteSecurityAction.recover;
  bool get _newPassword =>
      _recovery ||
      widget.action == NoteSecurityAction.enable ||
      widget.action == NoteSecurityAction.change;
  @override
  void initState() {
    super.initState();
    _offline = !widget.serverAvailable;
    _sessionSubscription = widget.sessionEvents.listen((_) {
      if (!widget.isCurrent() && mounted) {
        _clear();
        Navigator.of(context).pop(false);
      }
    });
    if (_recovery) unawaited(_requestCode());
  }

  void _clear() {
    if (_disposed) return;
    for (final c in [_current, _password, _confirmation, _otp]) {
      c.clear();
    }
  }

  Future<void> _requestCode() async {
    setState(() {
      _busy = true;
      _failure = null;
      _challenge = null;
    });
    try {
      final challenge = await widget.service.requestRecovery(widget.noteId);
      if (mounted) setState(() => _challenge = challenge);
    } on NoteSecurityFailure catch (e) {
      if (mounted) setState(() => _failure = e.code);
    } on Object {
      if (mounted) {
        setState(() => _failure = NoteSecurityFailureCode.unavailable);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await _performAction();
      _clear();
      if (mounted) Navigator.of(context).pop(true);
    } on NoteSecurityFailure catch (e) {
      _clear();
      if (mounted) setState(() => _failure = e.code);
    } on Object {
      _clear();
      if (mounted) {
        setState(() => _failure = NoteSecurityFailureCode.unavailable);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _performAction() async {
    final s = widget.service, id = widget.noteId;
    switch (widget.action) {
      case NoteSecurityAction.enable:
        await s.enable(id, _password.text, _confirmation.text);
      case NoteSecurityAction.unlock:
        await s.unlock(id, _password.text, offline: _offline);
      case NoteSecurityAction.change:
        await s.changePassword(
          id,
          _current.text,
          _password.text,
          _confirmation.text,
        );
      case NoteSecurityAction.disable:
        await s.disable(id, _current.text);
      case NoteSecurityAction.recover:
        final challenge = _challenge;
        if (challenge == null || !challenge.expiresAt.isAfter(DateTime.now())) {
          throw const NoteSecurityFailure(
            NoteSecurityFailureCode.invalidChallenge,
          );
        }
        await s.confirmRecovery(
          id,
          challenge.id,
          _otp.text,
          _password.text,
          _confirmation.text,
        );
      case NoteSecurityAction.lock:
        s.lock(id);
    }
  }

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    bool confirm = false,
  }) {
    final copy = NoteSecurityCopy(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        obscureText: true,
        enabled: !_busy,
        maxLength: 512,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(labelText: label, counterText: ''),
        validator: (v) => confirm
            ? (v == _password.text ? null : copy.mismatch)
            : (v != null && v.length >= 8 ? null : copy.minimum),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = NoteSecurityCopy(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Text(copy.label(widget.action)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_recovery) ...[
                    Text(copy.recoveryHint),
                    TextFormField(
                      controller: _otp,
                      enabled: !_busy,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(labelText: copy.otp),
                      validator: (v) =>
                          v != null && RegExp(r'^\d{6}$').hasMatch(v)
                          ? null
                          : copy.otp,
                    ),
                    TextButton(
                      onPressed: _busy ? null : _requestCode,
                      child: Text(copy.resend),
                    ),
                  ],
                  if (widget.action == NoteSecurityAction.change ||
                      widget.action == NoteSecurityAction.disable)
                    _passwordField(_current, copy.current),
                  if (widget.action != NoteSecurityAction.disable)
                    _passwordField(
                      _password,
                      _newPassword ? copy.next : copy.password,
                    ),
                  if (_newPassword)
                    _passwordField(_confirmation, copy.confirm, confirm: true),
                  if (widget.action == NoteSecurityAction.unlock) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(copy.offline),
                      value: _offline,
                      onChanged: _busy || !widget.serverAvailable
                          ? null
                          : (v) => setState(() => _offline = v ?? false),
                    ),
                    Text(copy.offlineHint),
                  ],
                  if (_failure case final code?)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        copy.failure(code),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(copy.cancel),
          ),
          FilledButton(
            onPressed: _busy || (_recovery && _challenge == null)
                ? null
                : _submit,
            child: Text(copy.apply),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    for (final c in [_current, _password, _confirmation, _otp]) {
      c.clear();
      c.dispose();
    }
    _disposed = true;
    super.dispose();
  }
}
