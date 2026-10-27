part of 'basic_block_menu.dart';

extension _BasicBlockChoiceRows on _BasicBlockMenuState {
  Widget _nativeChoices({required bool vi}) {
    final basics = _basicChoices;
    final media = _mediaChoices;
    return SingleChildScrollView(
      controller: scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (basics.isNotEmpty)
            BasicBlockGrid(
              choices: basics,
              controller: null,
              shrinkWrap: true,
              selectedChoice:
                  _nativeSelectionVisible &&
                      controller.selected >= 0 &&
                      controller.selected < controller.choices.length
                  ? controller.choices[controller.selected]
                  : null,
              labelFor: (choice) => _label(choice, vi),
              iconFor: _icon,
              onChoose: _choose,
            ),
          if (media.isNotEmpty) ...[
            if (_showMediaHeader) _mediaSectionHeader(vi: vi, desktop: false),
            for (final choice in media)
              _nativeChoiceRow(
                choice,
                vi,
                selected:
                    _nativeSelectionVisible &&
                    controller.choices.indexOf(choice) == controller.selected,
              ),
          ],
        ],
      ),
    );
  }

  Widget _mediaSectionHeader({required bool vi, required bool desktop}) =>
      SizedBox(
        height: rowHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: desktop ? 12 : 16),
              child: Text(
                vi ? 'Phương tiện' : 'Media',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: desktop ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );

  String _label(BasicBlockChoice choice, bool vi) {
    if (choice.kind == DocumentBlockKind.attachment) return vi ? 'Tệp' : 'File';
    return vi
        ? _vietnameseLabels[basicBlockChoices.indexOf(choice)]
        : choice.label;
  }

  IconData _icon(BasicBlockChoice choice) =>
      choice.kind == DocumentBlockKind.attachment
      ? Icons.attach_file
      : _icons[basicBlockChoices.indexOf(choice)];

  Widget _nativeChoiceRow(
    BasicBlockChoice choice,
    bool vi, {
    required bool selected,
  }) {
    return ListTile(
      dense: true,
      minTileHeight: 48,
      visualDensity: VisualDensity.standard,
      selected: selected,
      title: Text(
        _label(choice, vi),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      leading: Icon(_icon(choice), size: 20),
      onTap: () => _choose(choice),
    );
  }

  Widget _desktopChoiceRow(
    BasicBlockChoice choice,
    bool vi,
    ColorScheme colors, {
    required bool selected,
  }) {
    final choiceIndex = basicBlockChoices.indexOf(choice);
    final media = choice.kind == DocumentBlockKind.attachment;
    final neutral = colors.onSurface.withValues(alpha: 0.075);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _choose(choice),
        borderRadius: BorderRadius.circular(6),
        hoverColor: neutral,
        splashColor: neutral,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? neutral : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SizedBox(
              height: rowHeight - 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 20,
                        child:
                            !media && (choice.level != null || choiceIndex == 0)
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
                                _icon(choice),
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
                        _label(choice, vi),
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
