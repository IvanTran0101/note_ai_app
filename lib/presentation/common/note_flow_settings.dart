import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import 'note_flow_settings_choices.dart';

/// Existing settings share a quiet, sectioned surface on both form factors.
Future<void> showNoteFlowSettings({
  required BuildContext context,
  required WidgetBuilder builder,
}) => NoteFlowLayout.isCompact(context)
    ? showDialog<void>(
        context: context,
        useSafeArea: false,
        builder: (context) => Dialog.fullscreen(child: builder(context)),
      )
    : showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
            child: builder(context),
          ),
        ),
      );

final class NoteFlowSettingsSurface extends StatelessWidget {
  const NoteFlowSettingsSurface({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (NoteFlowLayout.isCompact(context)) {
      return _CompactSettingsSurface(
        title: title,
        subtitle: subtitle,
        children: children,
      );
    }
    final tokens = NoteFlowUiTokens.of(context);
    final wideWeb =
        !NoteFlowLayout.isCompact(context) &&
        MediaQuery.sizeOf(context).width >= 900;
    return Material(
      color: tokens.pageSurface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: NoteFlowLayout.isCompact(context)
              ? MainAxisSize.max
              : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                wideWeb ? 60 : 24,
                wideWeb ? 28 : 16,
                wideWeb ? 64 : 12,
                12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: wideWeb ? 26 : 20,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                        if (subtitle case final value?) ...[
                          const SizedBox(height: 4),
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: wideWeb ? 16 : 14,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.divider),
            Flexible(
              child: SingleChildScrollView(
                padding: wideWeb
                    ? const EdgeInsets.fromLTRB(60, 20, 64, 24)
                    : const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-page compact presentation of the same settings and callbacks.
final class _CompactSettingsSurface extends StatelessWidget {
  const _CompactSettingsSurface({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    return Material(
      color: Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFF9F8F7)
          : tokens.sidebarSurface,
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
    );
  }

  Widget _header(BuildContext context, NoteFlowUiTokens tokens) {
    final vi = Localizations.localeOf(context).languageCode == 'vi';
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            vi ? 'Cài đặt' : 'Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, size: 24),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
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
      ],
    ),
  );
}

/// Changes only the layout of the existing, keyboard-accessible dropdown.
final class NoteFlowSettingsChoice<T> extends StatelessWidget {
  const NoteFlowSettingsChoice({
    super.key,
    required this.label,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    this.helperText,
  });
  final String label;
  final String? helperText;
  final T initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    final compact = NoteFlowLayout.isCompact(context);
    final wideWeb = !compact && MediaQuery.sizeOf(context).width >= 900;
    final outlined = wideWeb || compact;
    final Widget control;
    if (!kIsWeb && compact) {
      control = NoteFlowNativeSettingsChoice<T>(
        label: label,
        initialValue: initialValue,
        items: items,
        onChanged: onChanged,
      );
    } else {
      control = DropdownButtonFormField<T>(
        initialValue: initialValue,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        alignment: AlignmentDirectional.centerEnd,
        icon: Icon(
          outlined ? Icons.keyboard_arrow_down : Icons.unfold_more,
          size: compact ? 20 : 18,
          color: tokens.textMuted,
        ),
        style: TextStyle(
          fontSize: outlined ? 14 : 15,
          fontWeight: compact ? FontWeight.w600 : FontWeight.w400,
          color: tokens.textSecondary,
        ),
        dropdownColor: tokens.pageSurface,
        decoration: InputDecoration(
          filled: false,
          isDense: true,
          visualDensity: wideWeb ? VisualDensity.standard : null,
          constraints: BoxConstraints(minHeight: wideWeb ? 28 : 48),
          border: outlined
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: tokens.divider),
                )
              : InputBorder.none,
          enabledBorder: outlined
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: tokens.divider),
                )
              : InputBorder.none,
          focusedBorder: outlined
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: tokens.textSecondary),
                )
              : InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: outlined ? 8 : 12,
            vertical: wideWeb
                ? 2
                : compact
                ? 6
                : 8,
          ),
        ),
      );
    }
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: wideWeb ? 10 : 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: wideWeb ? 14 : 16,
                    fontWeight: compact && !kIsWeb
                        ? FontWeight.w400
                        : compact
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: tokens.textPrimary,
                  ),
                ),
                if (helperText case final helper?) ...[
                  const SizedBox(height: 2),
                  Text(
                    helper,
                    style: TextStyle(
                      fontSize: wideWeb ? 13 : 14,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ],
            );
            if (constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(16) > 24) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: 4),
                  wideWeb
                      ? Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: SizedBox(width: 150, child: control),
                        )
                      : control,
                ],
              );
            }
            if (wideWeb) {
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  SizedBox(width: 150, child: control),
                ],
              );
            }
            if (compact) {
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  kIsWeb
                      ? SizedBox(width: 160, child: control)
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: IntrinsicWidth(child: control),
                        ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 4, child: title),
                Expanded(flex: 6, child: control),
              ],
            );
          },
        ),
      ),
    );
  }
}
