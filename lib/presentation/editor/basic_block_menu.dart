import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'basic_block_commands.dart';
import 'slash_command_controller.dart';

final class BasicBlockMenu extends StatefulWidget {
  const BasicBlockMenu({
    super.key,
    required this.controller,
    this.onChoose,
    this.onClose,
    this.sheet = false,
  });
  final SlashCommandController controller;
  final ValueChanged<BasicBlockChoice>? onChoose;
  final VoidCallback? onClose;
  final bool sheet;
  @override
  State<BasicBlockMenu> createState() => _BasicBlockMenuState();
}

final class _BasicBlockMenuState extends State<BasicBlockMenu> {
  final scroll = ScrollController();
  SlashCommandController get controller => widget.controller;
  int _selected = 0;
  String _query = '';
  double get rowHeight =>
      math.max(48, MediaQuery.textScalerOf(context).scale(14) * 2 + 16);
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
      final start = controller.selected * rowHeight;
      final end = start + rowHeight;
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
    return Material(
      elevation: widget.sheet ? 0 : 8,
      borderRadius: BorderRadius.circular(widget.sheet ? 0 : 10),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: widget.sheet
            ? double.infinity
            : math.min(MediaQuery.sizeOf(context).width - 32, 320),
        height: widget.sheet
            ? math.min(MediaQuery.sizeOf(context).height * .65, 480)
            : 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      vi ? 'Khối cơ bản' : 'Basic blocks',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: vi ? 'Đóng menu khối' : 'Close block menu',
                    onPressed:
                        widget.onClose ?? () => controller.close(cancel: true),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: controller.choices.isEmpty
                  ? Center(
                      child: Text(
                        vi ? 'Không tìm thấy khối' : 'No matching block',
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemExtent: rowHeight,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: controller.choices.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        selected: index == controller.selected,
                        title: Text(
                          vi
                              ? _vietnameseLabels[basicBlockChoices.indexOf(
                                  controller.choices[index],
                                )]
                              : controller.choices[index].label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: Icon(
                          _icons[basicBlockChoices.indexOf(
                            controller.choices[index],
                          )],
                          size: 20,
                        ),
                        onTap: () {
                          final choice = controller.choices[index];
                          if (widget.onChoose != null) {
                            widget.onChoose!(choice);
                          } else {
                            unawaited(controller.choose(choice));
                          }
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
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
