part of 'share_management_dialog.dart';

/// A bounded popup avoids intrinsic measurement of responsive invite content.
extension _ShareManagementDesktop on _ShareManagementState {
  Widget _desktopDialog(
    SharingCopy copy,
    NoteFlowUiTokens tokens, {
    required bool webPanel,
    required Widget body,
  }) => Dialog(
    alignment: Alignment.topRight,
    insetPadding: EdgeInsets.fromLTRB(24, 44, webPanel ? 100 : 20, 24),
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF252525)
        : tokens.elevatedSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: tokens.divider),
    ),
    child: SizedBox(
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
                  Padding(
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
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: webPanel ? 16 : 20,
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
                  child: Text(copy.close),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
