import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';
import 'dashboard_view_models.dart';

/// Presentation of the existing keyword/sort/close controls above the IME.
final class DashboardSearchDock extends StatelessWidget {
  const DashboardSearchDock({
    super.key,
    required this.copy,
    required this.controller,
    required this.sort,
    required this.onChanged,
    required this.onClear,
    required this.onSortChanged,
    required this.onClose,
    required this.fieldKey,
    required this.sortKey,
    required this.closeKey,
  });

  final DashboardCopy copy;
  final TextEditingController controller;
  final DashboardSort sort;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<DashboardSort> onSortChanged;
  final VoidCallback onClose;
  final Key fieldKey;
  final Key sortKey;
  final Key closeKey;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowWorkspaceTokens.of(context);
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final double horizontalInset = viewportWidth < 360 ? 8 : 12;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 4),
        child: Row(
          children: [
            Expanded(child: _field(context, tokens)),
            const SizedBox(width: 4),
            IconButton.outlined(
              key: closeKey,
              tooltip: copy.closeSearch,
              onPressed: onClose,
              style: IconButton.styleFrom(
                backgroundColor: NoteFlowLayout.isNativePhone(context)
                    ? tokens.compactHomeSurface
                    : tokens.pageSurface,
                foregroundColor: tokens.textPrimary,
                side: BorderSide(color: tokens.divider),
                shape: const CircleBorder(),
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.close, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, NoteFlowWorkspaceTokens tokens) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: tokens.divider),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: copy.searchNotes,
        isDense: true,
        filled: true,
        fillColor: NoteFlowLayout.isNativePhone(context)
            ? tokens.compactHomeSurface
            : tokens.pageSurface,
        prefixIcon: const Icon(Icons.search, size: 24),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              IconButton(
                key: const ValueKey<String>('dashboard-clear-search-field'),
                tooltip: copy.clearSearch,
                onPressed: onClear,
                // Keep the real tap target at 48dp under compact themes.
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                visualDensity: VisualDensity.standard,
                icon: NoteFlowLayout.isNativePhone(context)
                    ? Icon(Icons.cancel, size: 20, color: tokens.textMuted)
                    : const Icon(Icons.clear),
              ),
            _sortButton(tokens),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: border,
        enabledBorder: border,
        focusedBorder: NoteFlowLayout.isNativePhone(context)
            ? border
            : border.copyWith(borderSide: BorderSide(color: tokens.focusRing)),
      ),
    );
  }

  Widget _sortButton(NoteFlowWorkspaceTokens tokens) =>
      PopupMenuButton<DashboardSort>(
        key: sortKey,
        tooltip: copy.sort,
        initialValue: sort,
        onSelected: onSortChanged,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: DashboardSort.updated,
            child: Text(copy.sortUpdated),
          ),
          PopupMenuItem(
            value: DashboardSort.created,
            child: Text(copy.sortCreated),
          ),
        ],
        child: SizedBox.square(
          dimension: 48,
          child: Tooltip(
            message: copy.sort,
            child: Icon(Icons.sort, color: tokens.textMuted),
          ),
        ),
      );
}
