import 'dart:async';

import 'package:flutter/services.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/playback_info.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/playback_telemetry.dart';

/// Opens “播放信息”: the room's panel, or the same panel in a sheet where
/// there is no room page around [context] (a lone button in a test).
void showPlaybackInfo(BuildContext context, LiveRoomController controller) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.playbackInfo);
    return;
  }
  unawaited(
    showRoomPanelSheet(
      context,
      builder: (_, close) => PlaybackInfoPanel(controller: controller, onClose: close),
    ),
  );
}

/// The room's “播放信息” (A07.33): nine stream values from mpv and the
/// session, refreshed once a second while open. The panel sits where the
/// other room panels do (below the picture in portrait, on the right in
/// landscape and on wide windows) and never covers the picture itself.
class PlaybackInfoPanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, required this.onClose, this.dragToClose = false, this.statsReader, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes the panel (portrait).
  final bool dragToClose;

  /// Replaces the engine's statistics source in tests; null uses
  /// `controller.session.engine` when it is a [PlaybackStatsSource].
  final Future<PlaybackStats?> Function()? statsReader;

  @override
  State<PlaybackInfoPanel> createState() => _PlaybackInfoPanelState();
}

class _PlaybackInfoPanelState extends State<PlaybackInfoPanel> {
  PlaybackStats? _stats;
  late PlaybackTelemetry _telemetry;
  bool _ownsTelemetry = false;
  StreamSubscription<PlaybackState>? _states;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _ownsTelemetry = widget.statsReader != null;
    _telemetry = _ownsTelemetry ? PlaybackTelemetry(read: widget.statsReader!) : _room.telemetry;
    _stats = _telemetry.value;
    _telemetry.addListener(_changed);
    _states = _room.session.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _changed() {
    if (mounted) setState(() => _stats = _telemetry.value);
  }

  void _detach() {
    _telemetry.removeListener(_changed);
    if (_ownsTelemetry) _telemetry.dispose();
    unawaited(_states?.cancel());
  }

  @override
  void didUpdateWidget(PlaybackInfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller || oldWidget.statsReader != widget.statsReader) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  double? get _downloadAverage => _telemetry.downloadAverage;

  PlaybackInfo get _info => playbackInfoOf(
    state: _room.session.state,
    stats: _stats,
    downloadBytesPerSecond: _stats == null ? null : _downloadAverage,
  );

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _info.copyText));
      AppNavigator.toast(i18n('playback_info_copied'));
    } on Object {
      AppNavigator.toast(i18n('toolbox_copy_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final theme = Theme.of(context);
    return RoomSidePanel(
      key: const ValueKey('panel-playback-info'),
      title: i18n('playback_info'),
      onClose: widget.onClose,
      dragToClose: widget.dragToClose,
      actions: [
        IconButton(
          key: const ValueKey('playback-info-copy'),
          tooltip: i18n('playback_info_copy'),
          onPressed: () => unawaited(_copy()),
          icon: const Icon(AppIcons.copy),
        ),
      ],
      child: ListView(
        key: const ValueKey('playback-info-list'),
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        children: [
          PanelCard(
            children: [
              for (final (index, row) in info.rows.indexed) ...[
                _PlaybackInfoRowView(row),
                if (index < info.rows.length - 1) const _PlaybackInfoDivider(),
              ],
              if (info.playerCore != null) ...[
                const _PlaybackInfoDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Text(
                    '${i18n('player_kernel')} · ${info.playerCore}',
                    style: context.textStyles.t12.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One label/value row inside the panel: a fixed label column with a
/// left-aligned value on wide rows, stacked when the panel is narrow or the
/// text is large.
class _PlaybackInfoRowView extends StatelessWidget {
  const new(this.row);

  final PlaybackInfoRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      row.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.regular.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    final value = Text(
      row.value,
      maxLines: row.multiline ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.regular,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(1) > 1.5;
        return ConstrainedBox(
          key: ValueKey('playback-info-${row.id}'),
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: stacked ? 8 : 9),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [label, const SizedBox(height: 3), value],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 104, child: label),
                      const SizedBox(width: 12),
                      Expanded(child: value),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// A hairline between two rows (and before the player core line).
class _PlaybackInfoDivider extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 16,
    endIndent: 16,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
  );
}
