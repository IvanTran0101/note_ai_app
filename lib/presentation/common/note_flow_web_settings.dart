import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';

/// Web framing of the existing settings; the caller retains every callback.
Future<void> showNoteFlowWebSettings({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<void>(
  context: context,
  useSafeArea: false,
  builder: (context) => LayoutBuilder(
    builder: (context, available) {
      // This route is Web-only: a short desktop window is still a wide window.
      if (available.maxWidth < NoteFlowLayout.compactBreakpoint) {
        return Dialog.fullscreen(child: builder(context));
      }
      final height =
          (available.maxHeight -
                  MediaQuery.viewInsetsOf(context).vertical -
                  100)
              .clamp(0.0, double.infinity)
              .toDouble();
      return Dialog(
        alignment: Alignment.topCenter,
        insetPadding: EdgeInsets.symmetric(
          horizontal: available.maxWidth * .05,
          vertical: 50,
        ),
        constraints: const BoxConstraints(maxWidth: 1512),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          key: const ValueKey('settings-web-frame'),
          width: (available.maxWidth * .9).clamp(0.0, 1512.0),
          height: height,
          child: builder(context),
        ),
      );
    },
  ),
);

/// Preferences and existing account actions share a quiet two-pane surface.
/// No navigation state, settings values, or account operation is owned here.
final class NoteFlowWebSettingsSurface extends StatelessWidget {
  const NoteFlowWebSettingsSurface({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.accountActions = const [],
  });

  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> accountActions;

  @override
  Widget build(BuildContext context) {
    final tokens = _referenceTokens(context);
    final vi = Localizations.localeOf(context).languageCode == 'vi';
    final preferences = title ?? (vi ? 'Tùy chọn' : 'Preferences');
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [
          ...Theme.of(context).extensions.values
              .where((value) => value is! NoteFlowUiTokens),
          tokens,
        ],
        dividerTheme: DividerThemeData(color: tokens.divider),
      ),
      child: Material(
        color: tokens.pageSurface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 240,
              child: _accountPane(context, preferences, tokens, vi),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SingleChildScrollView(
                    key: const ValueKey('settings-web-preferences-scroll'),
                    // The reference reserves its scrollbar in the end gutter.
                    padding: const EdgeInsets.fromLTRB(60, 36, 76, 40),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              preferences,
                              key: const ValueKey('settings-web-title'),
                              style: TextStyle(
                                fontFamily: 'NoteFlowHeading',
                                fontSize: 26,
                                height: 32 / 26,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                            if (subtitle case final value?) ...[
                              const SizedBox(height: 8),
                              Text(
                                value,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 24 / 16,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 44),
                            ...children,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      visualDensity: VisualDensity.standard,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  NoteFlowUiTokens _referenceTokens(BuildContext context) {
    final base = NoteFlowUiTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = dark ? const Color(0xFF202020) : base.pageSurface;
    final sidebar = dark ? page : const Color(0xFFF9F8F7);
    // Scoped to this Web surface; the app's other semantic colors stay intact.
    return base.copyWith(
      pageSurface: page,
      sidebarSurface: sidebar,
      textPrimary: dark ? const Color(0xFFF0EFED) : const Color(0xFF2C2C2B),
      textMuted: dark ? const Color(0xFFADA9A3) : const Color(0xFF7D7A75),
      selectedSurface: Color.alphaBlend(
        dark
            ? const Color.fromRGBO(255, 255, 255, .055)
            : const Color.fromRGBO(33, 27, 23, .05),
        sidebar,
      ),
      divider: Color.alphaBlend(
        dark
            ? const Color.fromRGBO(255, 255, 243, .082)
            : const Color.fromRGBO(42, 28, 0, .07),
        page,
      ),
    );
  }

  Widget _accountPane(
    BuildContext context,
    String preferences,
    NoteFlowUiTokens tokens,
    bool vi,
  ) => Material(
    color: tokens.sidebarSurface,
    shape: Border(right: BorderSide(color: tokens.divider)),
    child: ListTileTheme(
      data: _accountStyle(tokens),
      child: SingleChildScrollView(
        key: const ValueKey('settings-web-account-scroll'),
        padding: const EdgeInsets.fromLTRB(8, 24, 8, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Text(
                vi ? 'Tài khoản' : 'Account',
                style: TextStyle(
                  fontSize: 12,
                  height: 18 / 12,
                  color: tokens.textMuted,
                ),
              ),
            ),
            if (accountActions.isNotEmpty) accountActions.first,
            _selectedPreferences(preferences, tokens),
            const SizedBox(height: 8),
            ...accountActions.skip(1),
          ],
        ),
      ),
    ),
  );

  ListTileThemeData _accountStyle(NoteFlowUiTokens tokens) => ListTileThemeData(
    dense: true,
    minTileHeight: 28,
    visualDensity: VisualDensity.standard,
    minLeadingWidth: 20,
    horizontalTitleGap: 10,
    titleTextStyle: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      color: tokens.textPrimary,
    ),
    iconColor: tokens.textSecondary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
  );

  Widget _selectedPreferences(String preferences, NoteFlowUiTokens tokens) =>
      Semantics(
        selected: true,
        label: preferences,
        child: ExcludeSemantics(
          child: Container(
            key: const ValueKey('settings-web-preferences-selection'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.selectedSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: 18,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    preferences,
                    style: TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Heading for an existing settings group, with the reference's fine divider.
final class NoteFlowSettingsSectionTitle extends StatelessWidget {
  const NoteFlowSettingsSectionTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    return Semantics(
      header: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.divider, width: .8)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w500,
              color: tokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
