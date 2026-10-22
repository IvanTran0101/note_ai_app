import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';

/// Native compact presentation of an existing settings choice.
///
/// The option values and callback remain owned by the caller. This widget only
/// changes how the same choices are presented on a phone or compact window.
final class NoteFlowNativeSettingsChoice<T> extends StatelessWidget {
  const NoteFlowNativeSettingsChoice({
    super.key,
    required this.label,
    required this.initialValue,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  DropdownMenuItem<T>? get _selectedItem {
    for (final DropdownMenuItem<T> item in items) {
      if (item.value == initialValue) {
        return item;
      }
    }
    return null;
  }

  Future<void> _openChoices(BuildContext context) async {
    if (onChanged == null || items.isEmpty) {
      return;
    }

    final T? selectedValue = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x40000000),
      builder: (BuildContext _) => _NoteFlowSettingsChoiceSheet<T>(
        label: label,
        initialValue: initialValue,
        items: items,
      ),
    );

    // A drag, barrier tap, or Done button returns null and leaves the existing
    // value untouched. Invoke the existing setting callback only for a choice.
    if (context.mounted && selectedValue != null) {
      onChanged?.call(selectedValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final DropdownMenuItem<T>? selected = _selectedItem;
    final bool enabled = onChanged != null;

    return OutlinedButton(
      onPressed: enabled ? () => _openChoices(context) : null,
      style: OutlinedButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        foregroundColor: tokens.textSecondary,
        disabledForegroundColor: tokens.textMuted,
        side: BorderSide(color: tokens.divider),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: enabled ? tokens.textSecondary : tokens.textMuted,
              ),
              child: selected?.child ?? const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.keyboard_arrow_down, size: 18, color: tokens.textMuted),
        ],
      ),
    );
  }
}

final class _NoteFlowSettingsChoiceSheet<T> extends StatelessWidget {
  const _NoteFlowSettingsChoiceSheet({
    required this.label,
    required this.initialValue,
    required this.items,
  });

  final String label;
  final T initialValue;
  final List<DropdownMenuItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool isVietnamese =
        Localizations.localeOf(context).languageCode == 'vi';

    return FractionallySizedBox(
      widthFactor: 1,
      heightFactor: 1,
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Material(
          color: tokens.sidebarSurface,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, tokens, isVietnamese),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      8,
                      16,
                      20,
                    ),
                    child: _choiceGroup(context, tokens),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    NoteFlowUiTokens tokens,
    bool isVietnamese,
  ) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 5, 16, 8),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: math.max(
              48,
              MediaQuery.textScalerOf(context).scale(16) * 1.4 + 8,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(76, 3, 76, 0),
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.link,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: Text(isVietnamese ? 'Xong' : 'Done'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceGroup(BuildContext context, NoteFlowUiTokens tokens) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: tokens.elevatedSurface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int index = 0; index < items.length; index++) ...[
              if (index > 0) Divider(height: 1, color: tokens.divider),
              _choiceRow(context, tokens, items[index]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choiceRow(
    BuildContext context,
    NoteFlowUiTokens tokens,
    DropdownMenuItem<T> item,
  ) {
    final T? value = item.value;
    final bool selected = value == initialValue;

    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: item.enabled && value != null
                ? () => Navigator.of(context).pop<T>(value)
                : null,
            style: TextButton.styleFrom(
              alignment: AlignmentDirectional.centerStart,
              foregroundColor: tokens.textPrimary,
              disabledForegroundColor: tokens.textMuted,
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
              shape: const RoundedRectangleBorder(),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: item.enabled
                          ? tokens.textPrimary
                          : tokens.textMuted,
                    ),
                    child: item.child,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: selected
                      ? Icon(Icons.check, size: 16, color: tokens.textPrimary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
