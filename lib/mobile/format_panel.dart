import 'package:flutter/material.dart';

import '../design.dart';
import '../strings.dart';

/// Everything the format panel can do to the note's text.
///
/// The panel only says *what* was asked for; the page owns the text and does the work. That
/// keeps the editing rules in one place instead of split across a sheet that comes and goes.
enum FormatAction {
  bold,
  italic,
  strike,
  code,
  checkbox,
  divider,
  bullet,
  numbered,
  indent,
  outdent,
  quote,
  date,
}

/// One button in the panel's grid.
class _PanelButton {
  const _PanelButton({
    required this.action,
    required this.tooltip,
    this.label,
    this.icon,
  });

  final FormatAction action;
  final String tooltip;
  final String? label;
  final IconData? icon;
}

/// The sheet that slides up from the bottom of the editor.
///
/// Laid out from `design/final/ed4_format.png`: a grab handle, the title with a round close
/// button, a font-size slider, six size chips, then three rows of buttons.
///
/// The things the user explicitly ruled out are **not** here, and must not be added: no
/// heading/body style row, no colour picker, and no centre or right alignment (Markdown has
/// none of the three).
class FormatPanel extends StatefulWidget {
  const FormatPanel({
    super.key,
    required this.fontSize,
    required this.lineHeight,
    required this.monoFont,
    required this.onFontSize,
    required this.onLineHeight,
    required this.onMonoFont,
    required this.onAction,
  });

  final double fontSize;
  final double lineHeight;
  final bool monoFont;

  final ValueChanged<double> onFontSize;
  final ValueChanged<double> onLineHeight;
  final ValueChanged<bool> onMonoFont;
  final ValueChanged<FormatAction> onAction;

  /// The six sizes offered as blocks, and the smallest and largest the slider reaches.
  static const List<double> sizes = <double>[12, 14, 16, 18, 20, 24];
  static const double minSize = 12;
  static const double maxSize = 24;

  /// The line heights offered.
  static const List<double> lineHeights = <double>[1.4, 1.6, 1.8, 2.0, 2.4];

  @override
  State<FormatPanel> createState() => _FormatPanelState();
}

class _FormatPanelState extends State<FormatPanel> {
  late double _fontSize = widget.fontSize;
  late double _lineHeight = widget.lineHeight;

  static const List<_PanelButton> _firstRow = <_PanelButton>[
    _PanelButton(
      action: FormatAction.bold,
      label: 'B',
      tooltip: NotesStrings.toolBold,
    ),
    _PanelButton(
      action: FormatAction.italic,
      label: 'I',
      tooltip: NotesStrings.toolItalic,
    ),
    _PanelButton(
      action: FormatAction.strike,
      label: 'S',
      tooltip: NotesStrings.toolStrike,
    ),
    _PanelButton(
      action: FormatAction.code,
      label: '</>',
      tooltip: NotesStrings.toolCode,
    ),
    _PanelButton(
      action: FormatAction.checkbox,
      icon: Icons.check_circle_outline,
      tooltip: NotesStrings.toolCheckbox,
    ),
    _PanelButton(
      action: FormatAction.divider,
      icon: Icons.horizontal_rule,
      tooltip: NotesStrings.toolDivider,
    ),
  ];

  static const List<_PanelButton> _secondRow = <_PanelButton>[
    _PanelButton(
      action: FormatAction.bullet,
      icon: Icons.format_list_bulleted,
      tooltip: NotesStrings.toolBulletList,
    ),
    _PanelButton(
      action: FormatAction.numbered,
      icon: Icons.format_list_numbered,
      tooltip: NotesStrings.toolNumberList,
    ),
    _PanelButton(
      action: FormatAction.indent,
      icon: Icons.format_indent_increase,
      tooltip: NotesStrings.toolIndent,
    ),
    _PanelButton(
      action: FormatAction.outdent,
      icon: Icons.format_indent_decrease,
      tooltip: NotesStrings.toolOutdent,
    ),
    _PanelButton(
      action: FormatAction.quote,
      icon: Icons.format_quote,
      tooltip: NotesStrings.toolQuote,
    ),
    _PanelButton(
      action: FormatAction.date,
      icon: Icons.calendar_today_outlined,
      tooltip: NotesStrings.toolDate,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NotesPanelMetrics.radius),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: NotesPanelMetrics.handleWidth,
              height: NotesPanelMetrics.handleHeight,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(
                  NotesPanelMetrics.handleHeight / 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NotesPanelMetrics.sideInset,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  NotesStrings.formatTitle,
                  style: TextStyle(
                    fontSize: NotesPanelMetrics.titleSize,
                    fontWeight: NotesType.emphasis,
                    color: palette.ink,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: NotesPanelMetrics.closeDiameter,
                  height: NotesPanelMetrics.closeDiameter,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: NotesStrings.formatClose,
                    padding: EdgeInsets.zero,
                    iconSize: 17,
                    icon: Icon(Icons.close, color: palette.sub),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NotesPanelMetrics.sideInset,
            ),
            child: _sliderRow(palette),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NotesPanelMetrics.sideInset - 3,
            ),
            child: Row(
              children: <Widget>[
                for (final double size in FormatPanel.sizes)
                  Expanded(child: _chip(palette, size)),
              ],
            ),
          ),
          const SizedBox(height: NotesPanelMetrics.rowGap + 6),
          _buttonRow(palette, _firstRow),
          const SizedBox(height: NotesPanelMetrics.rowGap),
          _buttonRow(palette, _secondRow),
          const SizedBox(height: NotesPanelMetrics.rowGap),
          _lastRow(palette),
        ],
      ),
    );
  }

  Widget _sliderRow(NotesPalette palette) {
    return Row(
      children: <Widget>[
        Text(
          'A',
          style: TextStyle(
            fontSize: NotesPanelMetrics.sliderMarkSize,
            color: palette.ink,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: NotesPanelMetrics.trackHeight,
              activeTrackColor: palette.amber,
              inactiveTrackColor: palette.divider,
              thumbColor: palette.card,
              overlayShape: SliderComponentShape.noOverlay,
              // The slider snaps to whole sizes but the mock-up has no tick marks on the
              // track, so the divisions are kept and only their marks are taken away.
              tickMarkShape: SliderTickMarkShape.noTickMark,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: NotesPanelMetrics.thumbRadius,
                elevation: 3,
              ),
            ),
            child: Slider(
              value: _fontSize.clamp(
                FormatPanel.minSize,
                FormatPanel.maxSize,
              ),
              min: FormatPanel.minSize,
              max: FormatPanel.maxSize,
              divisions: (FormatPanel.maxSize - FormatPanel.minSize).round(),
              onChanged: (double value) {
                setState(() => _fontSize = value);
                widget.onFontSize(value);
              },
            ),
          ),
        ),
        Text(
          'A',
          style: TextStyle(
            fontSize: NotesPanelMetrics.sliderMarkBigSize,
            fontWeight: NotesType.emphasis,
            color: palette.ink,
          ),
        ),
      ],
    );
  }

  Widget _chip(NotesPalette palette, double size) {
    final bool selected = _fontSize.round() == size.round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: () {
          setState(() => _fontSize = size);
          widget.onFontSize(size);
        },
        child: Container(
          height: NotesPanelMetrics.chipHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.chipSelected : palette.panelButton,
            borderRadius: BorderRadius.circular(NotesPanelMetrics.chipRadius),
            border: selected
                ? Border.all(color: palette.amber, width: 1.5)
                : null,
          ),
          child: Text(
            size.round().toString(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? NotesType.emphasis : NotesType.body,
              // The mock-up uses the darkened amber here: plain amber on a pale amber wash
              // is not readable.
              color: selected ? palette.accentText : palette.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttonRow(NotesPalette palette, List<_PanelButton> buttons) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NotesPanelMetrics.sideInset - 3,
      ),
      child: Row(
        children: <Widget>[
          for (final _PanelButton button in buttons)
            Expanded(child: _button(palette, button)),
        ],
      ),
    );
  }

  Widget _button(NotesPalette palette, _PanelButton button) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        height: NotesPanelMetrics.buttonHeight,
        child: Material(
          color: palette.panelButton,
          borderRadius: BorderRadius.circular(NotesPanelMetrics.buttonRadius),
          child: InkWell(
            onTap: () => widget.onAction(button.action),
            borderRadius: BorderRadius.circular(
              NotesPanelMetrics.buttonRadius,
            ),
            child: Tooltip(
              message: button.tooltip,
              child: Center(
                child: button.icon != null
                    ? Icon(button.icon, size: 21, color: palette.ink)
                    : Text(
                        button.label!,
                        style: TextStyle(
                          fontSize: button.label == '</>' ? 14 : 18,
                          fontWeight: button.label == 'B'
                              ? NotesType.emphasis
                              : NotesType.body,
                          fontStyle: button.label == 'I'
                              ? FontStyle.italic
                              : FontStyle.normal,
                          decoration: button.label == 'S'
                              ? TextDecoration.lineThrough
                              : null,
                          color: palette.ink,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lastRow(NotesPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NotesPanelMetrics.sideInset - 3,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Builder(
              builder: (BuildContext anchor) => _wideButton(
                palette,
                widget.monoFont
                    ? NotesStrings.fontFamilyMono
                    : NotesStrings.fontFamilySystem,
                () => _pickFontFamily(anchor),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Builder(
              builder: (BuildContext anchor) => _wideButton(
                palette,
                '${NotesStrings.pickLineHeight} ${_lineHeight.toStringAsFixed(1)}',
                () => _pickLineHeight(anchor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideButton(NotesPalette palette, String label, VoidCallback onTap) {
    return SizedBox(
      height: NotesPanelMetrics.buttonHeight,
      child: Material(
        color: palette.panelButton,
        borderRadius: BorderRadius.circular(NotesPanelMetrics.buttonRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NotesPanelMetrics.buttonRadius),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: NotesType.body,
                color: palette.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickLineHeight(BuildContext anchor) async {
    final double? chosen = await _menu<double>(
      anchor,
      <double>[
        for (final double height in FormatPanel.lineHeights) height,
      ],
      (double height) => height.toStringAsFixed(1),
    );
    if (chosen == null) return;
    setState(() => _lineHeight = chosen);
    widget.onLineHeight(chosen);
  }

  Future<void> _pickFontFamily(BuildContext anchor) async {
    final bool? mono = await _menu<bool>(
      anchor,
      const <bool>[false, true],
      (bool value) =>
          value ? NotesStrings.fontFamilyMono : NotesStrings.fontFamilySystem,
    );
    if (mono == null) return;
    widget.onMonoFont(mono);
  }

  Future<T?> _menu<T>(
    BuildContext anchor,
    List<T> values,
    String Function(T) label,
  ) {
    final RenderBox overlay =
        Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
    final RenderBox box = anchor.findRenderObject()! as RenderBox;
    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return showMenu<T>(
      context: anchor,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - box.size.width,
        0,
      ),
      items: <PopupMenuEntry<T>>[
        for (final T value in values)
          PopupMenuItem<T>(value: value, child: Text(label(value))),
      ],
    );
  }
}
