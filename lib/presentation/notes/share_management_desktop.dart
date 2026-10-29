part of 'share_management_dialog.dart';

/// A bounded popup avoids intrinsic measurement of responsive invite content.
extension _ShareManagementDesktop on _ShareManagementState {
  void _requestInitialInviteFocus() {
    if (!kIsWeb ||
        _initialInviteFocusRequested ||
        !_live ||
        _busy ||
        _error != null) {
      return;
    }
    _initialInviteFocusRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_live || _busy || _error != null) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      final focused = FocusManager.instance.primaryFocus;
      final focusedContext = focused?.context;
      // Respect a user who has already moved focus within this dialog.
      if (focused != null &&
          focused is! FocusScopeNode &&
          focusedContext != null &&
          ModalRoute.of(focusedContext) == route) {
        return;
      }
      _emailFocus.requestFocus();
    });
  }

  Widget _desktopDialog(
    SharingCopy copy,
    NoteFlowUiTokens tokens, {
    required bool webPanel,
    required Widget body,
  }) => Dialog(
    alignment: Alignment.topRight,
    insetPadding: kIsWeb
        ? _webShareInsets()
        : EdgeInsets.fromLTRB(24, 44, webPanel ? 100 : 20, 24),
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF252525)
        : tokens.elevatedSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: tokens.divider),
    ),
    child: SizedBox(
      key: const ValueKey('share-popup-frame'),
      width: webPanel ? 456 : 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (kIsWeb && webPanel)
                    _webShareHeader(copy, tokens)
                  else
                    _accountShareHeader(copy, tokens, webPanel: webPanel),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      webPanel ? 16 : 20,
                      kIsWeb && webPanel ? 16 : 0,
                      webPanel ? 16 : 20,
                      0,
                    ),
                    child: body,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (_error != null) _retryButton(copy),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: kIsWeb && NoteFlowLayout.isCompact(context)
                      ? TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          visualDensity: VisualDensity.standard,
                        )
                      : null,
                  child: Text(copy.close),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  EdgeInsets _webShareInsets() {
    final width = MediaQuery.sizeOf(context).width;
    final popupWidth = (width - 24).clamp(0.0, 456.0);
    final maxRight = (width - popupWidth - 12).clamp(12.0, double.infinity);
    final right = (widget.webAnchorInset ?? (width >= 900 ? 100.0 : 12.0))
        .clamp(12.0, maxRight)
        .toDouble();
    return EdgeInsets.fromLTRB(12, 44, right, 24);
  }

  /// A single existing section; unsupported Notion tabs are not interactive UI.
  Widget _webShareHeader(SharingCopy copy, NoteFlowUiTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: IntrinsicWidth(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: tokens.textPrimary, width: 1.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 11.6, 8, 11.6),
                child: Semantics(
                  header: true,
                  child: Text(
                    copy.share,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Divider(height: .8, thickness: .8, color: tokens.divider),
    ],
  );

  Widget _accountShareHeader(
    SharingCopy copy,
    NoteFlowUiTokens tokens, {
    required bool webPanel,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Row(
      children: [
        Icon(
          Icons.people_outline,
          size: webPanel ? 18 : 20,
          color: tokens.textSecondary,
        ),
        SizedBox(width: webPanel ? 8 : 10),
        Expanded(
          child: Text(
            copy.manage,
            style: TextStyle(
              fontSize: webPanel ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}
