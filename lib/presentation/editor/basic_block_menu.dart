import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import 'basic_block_commands.dart';
import 'basic_block_grid.dart';
import 'editor_popup_area.dart';
import 'slash_command_controller.dart';

final class BasicBlockMenu extends StatefulWidget {
  static const double desktopPopupWidth = 324;
  static const double desktopPopupHeight = 267;

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
  double get rowHeight {
    final textHeight = MediaQuery.textScalerOf(context).scale(14);
    return math.max(_desktopCompact ? 33 : 48, textHeight + 19);
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
      final extent = grid
          ? BasicBlockGrid.rowHeightFor(context) + 4
          : rowHeight;
      final row = grid
          ? controller.selected ~/ BasicBlockGrid.columnsFor(context)
          : controller.selected;
      final start = row * extent;
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

  @override
  Widget build(BuildContext context) {
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
        ? Size(
            double.infinity,
            math.min(
              math.max(MediaQuery.sizeOf(context).height * .34, 240),
              320,
            ),
          )
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
            _header(vi: vi, desktop: desktop, colors: colors),
            Expanded(
              child: controller.choices.isEmpty
                  ? Center(
                      child: Text(
                        vi ? 'Không tìm thấy khối' : 'No matching block',
                      ),
                    )
                  : nativeGrid
                  ? BasicBlockGrid(
                      choices: controller.choices,
                      controller: scroll,
                      labelFor: (choice) => vi
                          ? _vietnameseLabels[basicBlockChoices.indexOf(choice)]
                          : choice.label,
                      iconFor: (choice) =>
                          _icons[basicBlockChoices.indexOf(choice)],
                      onChoose: _choose,
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemExtent: rowHeight,
                      padding: EdgeInsets.zero,
                      itemCount: controller.choices.length,
                      itemBuilder: (context, index) => desktop
                          ? _desktopChoiceRow(index, vi, colors)
                          : _nativeChoiceRow(index, vi),
                    ),
            ),
            if (desktop) _footer(vi: vi, colors: colors),
          ],
        ),
      ),
    );
  }

  Widget _header({
    required bool vi,
    required bool desktop,
    required ColorScheme colors,
  }) => Padding(
    padding: desktop
        ? const EdgeInsets.symmetric(horizontal: 12)
        : const EdgeInsets.fromLTRB(16, 0, 8, 0),
    child: SizedBox(
      height: desktop
          ? 32
          : widget.sheet
          ? math.max(48, MediaQuery.textScalerOf(context).scale(14) + 14)
          : null,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: widget.sheet && !kIsWeb ? 14 : 0),
              child: Text(
                vi ? 'Khối cơ bản' : 'Basic blocks',
                style: desktop
                    ? TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      )
                    : TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
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

  Widget _nativeChoiceRow(int index, bool vi) {
    final choice = controller.choices[index];
    final choiceIndex = basicBlockChoices.indexOf(choice);
    return ListTile(
      dense: true,
      selected: index == controller.selected,
      title: Text(
        vi ? _vietnameseLabels[choiceIndex] : choice.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      leading: Icon(_icons[choiceIndex], size: 20),
      onTap: () => _choose(choice),
    );
  }

  Widget _desktopChoiceRow(int index, bool vi, ColorScheme colors) {
    final choice = controller.choices[index];
    final choiceIndex = basicBlockChoices.indexOf(choice);
    final selected = index == controller.selected;
    final neutral = colors.onSurface.withValues(alpha: 0.075);
    return Material(
      color: selected ? neutral : Colors.transparent,
      child: InkWell(
        onTap: () => _choose(choice),
        hoverColor: neutral,
        splashColor: neutral,
        child: SizedBox(
          height: rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    width: 20,
                    child: choice.level != null || choiceIndex == 0
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              choice.level == null
                                  ? 'T'
                                  : 'H${_headingSubscripts[choice.level!]}',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: choice.level == null ? 16 : 14,
                                height: 1,
                                fontFamily: choice.level == null
                                    ? 'serif'
                                    : null,
                                color: selected
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Icon(
                            _icons[choiceIndex],
                            size: 16,
                            color: selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vi ? _vietnameseLabels[choiceIndex] : choice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurface, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

const _vietnameseLabels = [
  'Văn bản',
  'Tiêu đề 1',
  'Tiêu đề 2',
  'Tiêu đề 3',
  'Tiêu đề 4',
  'Danh sách dấu đầu dòng',
  'Danh sách đánh số',
  'Việc cần làm',
  'Danh sách thu gọn',
  'Chú thích',
  'Trích dẫn',
  'Bảng',
  'Đường phân cách',
];
const _headingSubscripts = ['', '₁', '₂', '₃', '₄'];
const _icons = [
  Icons.notes,
  Icons.title,
  Icons.title,
  Icons.title,
  Icons.title,
  Icons.format_list_bulleted,
  Icons.format_list_numbered,
  Icons.check_box_outlined,
  Icons.arrow_right,
  Icons.lightbulb_outline,
  Icons.format_quote,
  Icons.table_chart_outlined,
  Icons.horizontal_rule,
];
