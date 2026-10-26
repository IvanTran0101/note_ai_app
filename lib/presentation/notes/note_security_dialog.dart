import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_access.dart';
import '../../application/notes/note_security_gateway.dart';
import '../../application/notes/note_security_service.dart';
import 'note_security_localizations.dart';
import 'notes_theme_tokens.dart';

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
      case NoteSecurityAction.syncProtection:
        await s.authorizePendingSync(id, _current.text);
      case NoteSecurityAction.lock:
        s.lock(id);
    }
  }

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    bool confirm = false,
    String? helperText,
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
        decoration: _fieldDecoration(label, helperText: helperText),
        validator: (v) => confirm
            ? (v == _password.text ? null : copy.mismatch)
            : (v != null && v.length >= 8 ? null : copy.minimum),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, {String? helperText}) {
    final tokens = NoteFlowUiTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    OutlineInputBorder outline(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
      errorMaxLines: 3,
      counterText: '',
      filled: true,
      fillColor: tokens.subtleSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: outline(tokens.divider),
      enabledBorder: outline(tokens.divider),
      focusedBorder: outline(scheme.primary, width: 1.5),
      errorBorder: outline(scheme.error),
      focusedErrorBorder: outline(scheme.error, width: 1.5),
    );
  }

  Widget _supportingText(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: NoteFlowUiTokens.of(context).textSecondary),
    ),
  );

  Widget _failureRow(NoteSecurityCopy copy, NoteSecurityFailureCode code) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.error_outline,
                size: 18,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                copy.failure(code),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = NoteSecurityCopy(context);
    final tokens = NoteFlowUiTokens.of(context);
    final narrow = MediaQuery.of(context).size.width < 360;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 8 : 16,
          vertical: 12,
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        buttonPadding: EdgeInsets.zero,
        actionsOverflowButtonSpacing: 8,
        backgroundColor: tokens.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: tokens.divider),
        ),
        title: Row(
          children: [
            Icon(Icons.lock_outline, size: 22, color: tokens.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                copy.label(widget.action),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.service.localFirst)
                  _supportingText(copy.localFirstHint),
                if (_recovery) ...[
                  _supportingText(copy.recoveryHint),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextFormField(
                      controller: _otp,
                      enabled: !_busy,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: _fieldDecoration(copy.otp),
                      validator: (v) =>
                          v != null && RegExp(r'^\d{6}$').hasMatch(v)
                          ? null
                          : copy.otp,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: _busy ? null : _requestCode,
                      child: Text(copy.resend),
                    ),
                  ),
                ],
                if (widget.action == NoteSecurityAction.change ||
                    widget.action == NoteSecurityAction.disable ||
                    widget.action == NoteSecurityAction.syncProtection)
                  _passwordField(
                    _current,
                    widget.action == NoteSecurityAction.syncProtection
                        ? copy.cloudPassword
                        : copy.current,
                  ),
                if (widget.action != NoteSecurityAction.disable &&
                    widget.action != NoteSecurityAction.syncProtection)
                  _passwordField(
                    _password,
                    _newPassword ? copy.next : copy.password,
                    helperText: _newPassword ? copy.minimum : null,
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
                  _supportingText(copy.offlineHint),
                ],
                if (_failure case final code?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _failureRow(copy, code),
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
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(copy.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
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
