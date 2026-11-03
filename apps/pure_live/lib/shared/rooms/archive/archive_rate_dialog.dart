import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Rates supported by the native on-demand engine, in reading order.
const archiveRates = <double>[0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 3.5, 4];

/// Compact speed label, retaining the normal-speed decimal.
String archiveRateLabel(double rate) =>
    '${rate == rate.roundToDouble() ? rate.toStringAsFixed(1) : rate.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')}×';

/// Custom edits remain drafts until a value is explicitly returned.
class ArchiveRateDialog extends StatefulWidget {
  /// Opens with the actual controller rate.
  const new({required this.rate, this.embedded = false, this.onSelected, this.onClose, super.key});

  /// Current playback rate.
  final double rate;

  /// Renders within the page-owned bottom sheet/right drawer.
  final bool embedded;

  /// Applies an explicit choice in embedded mode.
  final ValueChanged<double>? onSelected;

  /// Discards the current draft in embedded mode.
  final VoidCallback? onClose;
  @override
  State<ArchiveRateDialog> createState() => _ArchiveRateDialogState();
}

class _ArchiveRateDialogState extends State<ArchiveRateDialog> {
  late final _input = TextEditingController(text: widget.rate.toStringAsFixed(2));
  late bool _fine = !archiveRates.contains(widget.rate);
  double? get _value {
    final n = double.tryParse(_input.text.trim());
    return n != null && n.isFinite && n >= 0.25 && n <= 4 && (n * 20 - (n * 20).round()).abs() < 0.000001 ? n : null;
  }

  void _finish(double? value) {
    if (widget.embedded) {
      if (value == null) {
        widget.onClose?.call();
      } else {
        widget.onSelected?.call(value);
      }
    } else {
      Navigator.pop<double>(context, value);
    }
  }

  void _step(int direction) {
    final next = (((_value ?? widget.rate) * 20).round() + direction).clamp(5, 80) / 20;
    setState(() => _input.text = next.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = MediaQuery.sizeOf(context);
      final available = widget.embedded && constraints.hasBoundedHeight
          ? constraints.maxHeight
          : size.height - MediaQuery.viewInsetsOf(context).vertical - 48;
      final preferredColumns = size.width > size.height ? 6 : 4;
      final labelStyle = DefaultTextStyle.of(context).style.merge(context.textStyles.t14);
      final scheme = Theme.of(context).colorScheme;
      final header = Padding(
        padding: const EdgeInsets.only(left: 20, right: 4),
        child: Row(
          children: [
            Expanded(child: Text(i18n('archive_rate_title'), style: Theme.of(context).textTheme.titleLarge)),
            IconButton(tooltip: i18n('close'), onPressed: () => _finish(null), icon: const Icon(AppIcons.close)),
          ],
        ),
      );
      final body = Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i18n('archive_rate_current', args: {'rate': archiveRateLabel(widget.rate)})),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                var widest = 0.0;
                for (final rate in archiveRates) {
                  final painter = TextPainter(
                    text: TextSpan(text: archiveRateLabel(rate), style: labelStyle),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    locale: Localizations.maybeLocaleOf(context),
                  )..layout();
                  if (painter.width > widest) widest = painter.width;
                  painter.dispose();
                }
                final columns = ((box.maxWidth + 8) / (widest + 16 + 8)).floor().clamp(1, preferredColumns);
                return FocusTraversalGroup(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final rate in archiveRates)
                        SizedBox(
                          width: (box.maxWidth - (columns - 1) * 8) / columns,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Semantics(
                              selected: rate == widget.rate,
                              child: OutlinedButton(
                                key: ValueKey('archive-rate-$rate'),
                                style: OutlinedButton.styleFrom(
                                  textStyle: labelStyle,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                  backgroundColor: rate == widget.rate ? scheme.primaryContainer : null,
                                  foregroundColor: rate == widget.rate ? scheme.onPrimaryContainer : null,
                                ),
                                onPressed: () => _finish(rate),
                                child: Text(archiveRateLabel(rate)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey('archive-rate-fine'),
              onPressed: () => setState(() => _fine = !_fine),
              child: Text('${i18n('archive_rate_fine')}  ${archiveRateLabel(_value ?? widget.rate)}'),
            ),
            if (_fine) ...[
              Row(
                children: [
                  IconButton(tooltip: i18n('archive_rate_slower'), onPressed: () => _step(-1), icon: const Text('−')),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('archive-rate-input'),
                      controller: _input,
                      autofocus: !archiveRates.contains(widget.rate),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: i18n('archive_rate_value'),
                        errorText: _value == null ? i18n('archive_rate_invalid') : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (_value != null) _finish(_value);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: i18n('archive_rate_faster'),
                    onPressed: () => _step(1),
                    icon: const Icon(AppIcons.add),
                  ),
                ],
              ),
              Slider(
                key: const ValueKey('archive-rate-slider'),
                min: 0.25,
                max: 4,
                divisions: 75,
                value: _value ?? widget.rate,
                onChanged: (v) => setState(() => _input.text = ((v * 20).round() / 20).toStringAsFixed(2)),
              ),
              Text(i18n('archive_rate_hint')),
            ],
          ],
        ),
      );
      final footer = Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('archive-rate-reset'),
              onPressed: () => _finish(1),
              child: Text(i18n('archive_rate_reset')),
            ),
            FilledButton(
              key: const ValueKey('archive-rate-apply'),
              onPressed: _fine ? (_value == null ? null : () => _finish(_value)) : () => _finish(null),
              child: Text(i18n(_fine ? 'apply' : 'done')),
            ),
          ],
        ),
      );
      // A landscape IME can leave less space than the header and footer need.
      // Let the whole panel scroll then; ordinary viewports keep actions fixed.
      final panel = available < 280
          ? SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [header, body, const Divider(height: 1), footer]),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Flexible(child: SingleChildScrollView(child: body)),
                const Divider(height: 1),
                footer,
              ],
            );
      if (widget.embedded) return SizedBox.expand(child: panel);
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: available.clamp(1, double.infinity)),
          child: panel,
        ),
      );
    },
  );
}
