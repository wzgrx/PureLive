import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// "选择颜色" of the TV (A17.9 c12): a grid of swatches, no names — a row of
/// common colours (the brand blue first) and the palette's 18 hues in three
/// shades; under them the focused colour's code and the current one. OK
/// picks and closes; Back keeps the colour.
Future<Color?> showTvColorGrid(BuildContext context, {required String title, required Color current}) =>
    showTvDialog<Color>(
      context,
      builder: (context) => TvDialog(
        key: const ValueKey('tv-color-grid'),
        title: title,
        width: 1720,
        actions: [
          TvButton(key: const ValueKey('tv-color-close'), label: i18n('cancel'), onTap: () => Navigator.pop(context)),
        ],
        child: _ColorGrid(current: current),
      ),
    );

class _ColorGrid extends StatefulWidget {
  const new({required this.current});

  final Color current;

  @override
  State<_ColorGrid> createState() => _ColorGridState();
}

class _ColorGridState extends State<_ColorGrid> {
  late Color _focused = widget.current;

  bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final rows = [LiveSwatches.common, ...LiveSwatches.palette];
    final hasCurrent = rows.any((row) => row.any((color) => _same(color, widget.current)));
    Widget label(String text) => Padding(
      padding: EdgeInsets.only(top: scale.px(16), bottom: scale.px(8)),
      child: Text(
        text,
        style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.textSecondary),
      ),
    );
    // 18 swatches share the row (A17.9 c12), squares with a gap of 12.
    Widget row(List<Color> colors, int rowIndex) => Row(
      children: [
        for (final (index, color) in colors.indexed) ...[
          if (index > 0) SizedBox(width: scale.px(12)),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: TvFocusable(
                key: ValueKey('tv-color-$rowIndex-$index'),
                autofocus: hasCurrent ? _same(color, widget.current) : rowIndex == 0 && index == 0,
                onFocusChange: (focused) {
                  if (focused) setState(() => _focused = color);
                },
                onTap: () => Navigator.pop(context, color),
                builder: (context, focused) => DecoratedBox(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(scale.px(TvRadius.card))),
                  child: _same(color, widget.current)
                      ? Icon(
                          TvIcons.ticked,
                          size: scale.px(36),
                          color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                              ? OnVideoColors.foreground
                              : OnVideoColors.ground,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          label(i18n('tv_color_common')),
          row(rows.first, 0),
          label(i18n('tv_color_palette')),
          for (final (index, colors) in rows.skip(1).indexed) ...[
            if (index > 0) SizedBox(height: scale.px(12)),
            row(colors, index + 1),
          ],
          Padding(
            padding: EdgeInsets.only(top: scale.px(20)),
            child: Text(
              i18n(
                'tv_color_codes',
                args: {
                  'focused': '#${colorHex(_focused).substring(2)}',
                  'current': '#${colorHex(widget.current).substring(2)}',
                },
              ),
              key: const ValueKey('tv-color-codes'),
              style: scale.font(TvTextSize.body, color: palette.text, height: 1.4),
            ),
          ),
          Text(i18n('tv_color_hint'), style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4)),
        ],
      ),
    );
  }
}
