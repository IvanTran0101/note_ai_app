import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../domain/notes/note_document.dart';
import '../notes/notes_theme_tokens.dart';
import 'basic_block_commands.dart';
import 'basic_block_grid.dart';
import 'editor_popup_area.dart';
import 'slash_command_controller.dart';

part 'basic_block_menu_choices.dart';

final class BasicBlockMenu extends StatefulWidget {
  static const double desktopPopupWidth = 324;
  static const double desktopPopupHeight = 290;

  static bool isCompactDesktop(BuildContext context) =>
      kIsWeb && !NoteFlowLayout.isCompact(context);

  static Size popupSizeFor(BuildContext context) {
    final area = EditorPopupArea.of(context).bounds;
    final desktop = isCompactDesktop(context);
    return Size(
      math.min(desktop ? desktopPopupWidth : 320, area.width),
      math.min(desktop ? desktopPopupHeight : 320, area.height),
    );
  }

  const BasicBlockMenu({
    super.key,
    required this.controller,
    this.onChoose,
    this.onClose,
    this.sheet = false,
    this.toolbarOwnsClose = false,
  });
  final SlashCommandController controller;
  final ValueChanged<BasicBlockChoice>? onChoose;
  final VoidCallback? onClose;
  final bool sheet;
  final bool toolbarOwnsClose;
  @override
  State<BasicBlockMenu> createState() => _BasicBlockMenuState();
}

final class _BasicBlockMenuState extends State<BasicBlockMenu> {
  final scroll = ScrollController();
  SlashCommandController get controller => widget.controller;
  int _selected = 0;
  String _query = '';
  bool get _desktopCompact =>
      BasicBlockMenu.isCompactDesktop(context) && !widget.sheet;
  List<BasicBlockChoice> get _basicChoices => controller.choices
      .where((choice) => choice.kind != DocumentBlockKind.attachment)
      .toList(growable: false);
  List<BasicBlockChoice> get _mediaChoices => controller.choices
      .where((choice) => choice.kind == DocumentBlockKind.attachment)
      .toList(growable: false);
  double get rowHeight {
    final textHeight = MediaQuery.textScalerOf(context).scale(14);
    final lines = _desktopCompact ? 1 : 2;
    return math
        .max(_desktopCompact ? 33.0 : 48.0, textHeight * lines + 12.0)
        .toDouble();
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant BasicBlockMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_refresh);
      controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (_selected == controller.selected && _query == controller.query) return;
    _selected = controller.selected;
    _query = controller.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final grid = widget.sheet && !kIsWeb;
      if (controller.selected < 0 ||
          controller.selected >= controller.choices.length) {
        return;
      }
      final choice = controller.choices[controller.selected];
      late final double start;
      late final double extent;
      if (grid) {
        final columns = BasicBlockGrid.columnsFor(context);
        final gridRowHeight = BasicBlockGrid.rowHeightFor(context);
        final basicIndex = _basicChoices.indexOf(choice);
        if (basicIndex >= 0) {
          final row = basicIndex ~/ columns;
          start =
              BasicBlockGrid.topPadding +
              row.toDouble() * (gridRowHeight + BasicBlockGrid.rowSpacing);
          extent = gridRowHeight;
        } else {
          final mediaIndex = _mediaChoices.indexOf(choice);
          if (mediaIndex < 0) return;
          final gridRows = (_basicChoices.length / columns).ceil();
          final rowGaps = gridRows > 1
              ? (gridRows - 1).toDouble() * BasicBlockGrid.rowSpacing
              : 0.0;
          final gridHeight = _basicChoices.isEmpty
              ? 0.0
              : BasicBlockGrid.topPadding +
                    gridRows.toDouble() * gridRowHeight +
                    rowGaps +
                    BasicBlockGrid.bottomPadding;
          start =
              gridHeight +
              (_showMediaHeader ? rowHeight : 0.0) +
              mediaIndex.toDouble() * rowHeight;
          extent = rowHeight;
        }
      } else {
        final selectedRow =
            controller.selected +
            (_showMediaHeader && choice.kind == DocumentBlockKind.attachment
                ? 1
                : 0);
        start = selectedRow.toDouble() * rowHeight;
        extent = rowHeight;
      }
      final end = start + extent;
      final viewport = scroll.position.viewportDimension;
      final target = start < scroll.offset
          ? start
          : end > scroll.offset + viewport
          ? end - viewport
          : scroll.offset;
      scroll.jumpTo(
        target.clamp(0, scroll.position.maxScrollExtent).toDouble(),
      );
    });
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    scroll.dispose();
    super.dispose();
  }

  double _sheetHeight(BuildContext context, BoxConstraints constraints) {
    final media = MediaQuery.of(context);
    // Native Notion replaces the keyboard with a compact two-column palette.
    // Keep the existing safe-height bound for rotation, IME and enlarged text.
    final native = !kIsWeb;
    final preferred = math
        .min(
          math.max(media.size.height * (native ? .315 : .34), 240.0),
          native ? 288.0 : 320.0,
        )
        .toDouble();
    final available =
        (constraints.hasBoundedHeight
                ? constraints.maxHeight
                : math.max(
                    0.0,
                    media.size.height -
                        media.padding.vertical -
                        media.viewInsets.vertical -
                        48,
                  ))
            .toDouble();
    return math.min(preferred, available).toDouble();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final vi = Localizations.localeOf(context).languageCode == 'vi';
      final desktop = _desktopCompact;
      final colors = Theme.of(context).colorScheme;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final nativeGrid = widget.sheet && !kIsWeb;
      final surface = nativeGrid
          ? (dark ? const Color(0xFF202020) : const Color(0xFFF9F8F7))
          : desktop && dark
          ? const Color(0xFF252525)
          : colors.surface;
      final popupSize = widget.sheet
          ? Size(double.infinity, _sheetHeight(context, constraints))
          : BasicBlockMenu.popupSizeFor(context);
      return Material(
        elevation: widget.sheet ? 0 : 8,
        clipBehavior: Clip.antiAlias,
        color: surface,
        shape: widget.sheet
            ? const RoundedRectangleBorder()
            : _desktopCompact
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.55),
                ),
              )
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SizedBox.fromSize(
          size: popupSize,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(
                vi: vi,
                desktop: desktop,
                colors: colors,
                availableHeight: popupSize.height,
              ),
              Expanded(
                child: controller.choices.isEmpty
                    ? Center(
                        child: Text(
                          vi ? 'Không tìm thấy khối' : 'No matching block',
                        ),
                      )
                    : nativeGrid
                    ? _nativeChoices(vi: vi)
                    : ListView.builder(
                        controller: scroll,
                        itemExtent: rowHeight,
                        padding: EdgeInsets.zero,
                        itemCount: _displayChoiceCount,
                        itemBuilder: (context, index) {
                          final basicCount = _basicChoices.length;
                          if (_showMediaHeader && index == basicCount) {
                            return _mediaSectionHeader(
                              vi: vi,
                              desktop: desktop,
                            );
                          }
                          final choiceIndex =
                              _showMediaHeader && index > basicCount
                              ? index - 1
                              : index;
                          final choice = controller.choices[choiceIndex];
                          return desktop
                              ? _desktopChoiceRow(
                                  choice,
                                  vi,
                                  colors,
                                  selected: choiceIndex == controller.selected,
                                )
                              : _nativeChoiceRow(
                                  choice,
                                  vi,
                                  selected: choiceIndex == controller.selected,
                                );
                        },
                      ),
              ),
              if (desktop) _footer(vi: vi, colors: colors),
            ],
          ),
        ),
      );
    },
  );

  Widget _header({
    required bool vi,
    required bool desktop,
    required ColorScheme colors,
    required double availableHeight,
  }) {
    final sheetHeaderHeight = math
        .max(48.0, MediaQuery.textScalerOf(context).scale(14) + 14)
        .toDouble();
    if (widget.sheet && availableHeight < sheetHeaderHeight) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: desktop
          ? const EdgeInsets.symmetric(horizontal: 12)
          : const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: SizedBox(
        height: desktop
            ? 32
            : widget.sheet
            ? sheetHeaderHeight
            : null,
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: widget.sheet && !kIsWeb ? 14 : 0),
                child: Text(
                  controller.query.isNotEmpty
                      ? (vi ? 'Kết quả lọc' : 'Filtered results')
                      : (vi ? 'Khối cơ bản' : 'Basic blocks'),
                  style: desktop
                      ? TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        )
                      : TextStyle(
                          fontSize: 14,
                          color: widget.sheet && !kIsWeb
                              ? Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF999999)
                                    : const Color(0xFF686867)
                              : colors.onSurfaceVariant,
                        ),
                ),
              ),
            ),
            if (!desktop && !widget.toolbarOwnsClose)
              IconButton(
                tooltip: vi ? 'Đóng menu khối' : 'Close block menu',
                onPressed: _close,
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  int get _displayChoiceCount =>
      controller.choices.length + (_showMediaHeader ? 1 : 0);
  bool get _showMediaHeader =>
      controller.query.isEmpty && _mediaChoices.isNotEmpty;

  Widget _footer({required bool vi, required ColorScheme colors}) => InkWell(
    onTap: _close,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              vi ? 'Đóng menu' : 'Close menu',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.7),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Esc',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );

  void _choose(BasicBlockChoice choice) {
    if (widget.onChoose != null) {
      widget.onChoose!(choice);
    } else {
      unawaited(controller.choose(choice));
    }
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      controller.close(cancel: true);
    }
  }
}
