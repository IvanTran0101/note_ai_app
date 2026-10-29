import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import 'note_flow_settings_account_actions.dart';

/// Full-page compact presentation of the same settings and callbacks.
final class NoteFlowCompactSettingsSurface extends StatelessWidget {
  const NoteFlowCompactSettingsSurface({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.accountActions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> accountActions;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    return Material(
      color: Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFF9F8F7)
          : tokens.sidebarSurface,
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerTheme: DividerThemeData(color: tokens.divider)),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, tokens),
              Divider(height: 1, color: tokens.divider),
              Expanded(child: _body(tokens)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, NoteFlowUiTokens tokens) {
    final vi = Localizations.localeOf(context).languageCode == 'vi';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 24),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
              child: Text(
                vi ? 'Cài đặt' : 'Settings',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _body(NoteFlowUiTokens tokens) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
        ),
        if (subtitle case final value?) ...[
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 14, color: tokens.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        ...children,
        if (accountActions.isNotEmpty)
          NoteFlowSettingsAccountActions(actions: accountActions),
      ],
    ),
  );
}
