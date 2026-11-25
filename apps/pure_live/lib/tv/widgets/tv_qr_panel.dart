import 'dart:math' as math;

import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/tv/tv_theme.dart';

/// "扫码到手机" (A17.9 c15): the code on the left; on the right what it is
/// for, how things stand, the numbered steps and the address (for a
/// browser on the same network). One layout for every such page: cookies,
/// logs, links, addresses.
class TvQrPanel extends StatelessWidget {
  /// Creates the panel.
  const new({required this.data, required this.title, required this.steps, this.status, this.address, super.key});

  /// What the code holds.
  final String data;

  /// What it is for.
  final String title;

  /// How things stand ("局域网服务运行中").
  final String? status;

  /// What to do, in order.
  final List<String> steps;

  /// The address shown under the steps.
  final String? address;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    // The code is as large as the dialog lets it be, at most 360: a dialog
    // on a TV has about 320 left, a phone in the TV look even less.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QrCodeWidget(
            key: const ValueKey('tv-qr-code'),
            data: data,
            size: math.min(scale.px(360), constraints.maxHeight),
          ),
          SizedBox(width: scale.px(32)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: scale.font(TvTextSize.heading, weight: FontWeight.w600, color: palette.text),
                ),
                if (status case final status?)
                  Padding(
                    padding: EdgeInsets.only(top: scale.px(6)),
                    child: Text(
                      status,
                      key: const ValueKey('tv-qr-status'),
                      style: scale.font(TvTextSize.small, color: palette.accent, height: 1.4),
                    ),
                  ),
                SizedBox(height: scale.px(16)),
                for (final (index, step) in steps.indexed)
                  Padding(
                    padding: EdgeInsets.only(bottom: scale.px(8)),
                    child: Text(
                      '${index + 1}. $step',
                      style: scale.font(TvTextSize.body, color: palette.text, height: 1.5),
                    ),
                  ),
                if (address case final address?)
                  Padding(
                    padding: EdgeInsets.only(top: scale.px(8)),
                    child: Text(
                      address,
                      key: const ValueKey('tv-qr-address'),
                      style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
