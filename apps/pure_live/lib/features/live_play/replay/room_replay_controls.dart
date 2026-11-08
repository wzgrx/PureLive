import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/features/live_play/buttons/stream_menu.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_composer.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/archive/archive_rate_dialog.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';
import 'package:pure_live/shared/rooms/archive/archive_time.dart';
import 'package:pure_live/shared/rooms/archive/bilibili_archive_controller.dart';

/// Extra controls above the existing live-room bottom bar.
class RoomReplayTransport extends StatefulWidget {
  /// Never mounts another video view or session.
  const new({
    required this.controller,
    required this.immersive,
    required this.onInteract,
    required this.onHolding,
    super.key,
  });

  /// Existing room owner.
  final LiveRoomController controller;

  /// Fullscreen or a layout whose replay strip is out of reach: a compact
  /// extra tool row.
  final bool immersive;

  /// Uses the original control-layer hide policy.
  final VoidCallback onInteract;

  /// Prevents hiding during a seek drag.
  final ValueChanged<bool> onHolding;
  @override
  State<RoomReplayTransport> createState() => _RoomReplayTransportState();
}

class _RoomReplayTransportState extends State<RoomReplayTransport> {
  double? _scrub;
  bool _dragging = false;
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(RoomReplayTransport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    if (_dragging) scheduleMicrotask(() => widget.onHolding(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: widget.controller.session.states,
    initialData: widget.controller.session.state,
    builder: (context, snapshot) {
      final archive = widget.controller.archive;
      if (archive == null) return const SizedBox.shrink();
      final duration = archive.duration;
      final max = duration.inMilliseconds.toDouble();
      final value = (_scrub ?? archive.position.inMilliseconds.toDouble()).clamp(0.0, max > 0 ? max : 1.0);
      final ink = context.textStyles.t12.copyWith(color: OnVideoColors.foreground);
      return DecoratedBox(
        key: const ValueKey('room-replay-transport'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [OnVideoColors.ground.withValues(alpha: 0), OnVideoColors.ground.withValues(alpha: .8)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    vodTime(Duration(milliseconds: value.round())),
                    key: const ValueKey('archive-video-clock'),
                    style: ink,
                  ),
                  const Spacer(),
                  Text(vodTime(duration), style: ink),
                ],
              ),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: i18n('archive_rewind'),
                      icon: const Icon(AppIcons.vodRewind, color: OnVideoColors.foreground),
                      onPressed: archive.busy
                          ? null
                          : () {
                              widget.onInteract();
                              unawaited(archive.seek(archive.position - const Duration(seconds: 10)));
                            },
                    ),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('vod-seek'),
                        padding: EdgeInsets.zero,
                        value: value,
                        max: max > 0 ? max : 1,
                        onChangeStart: archive.busy || max <= 0
                            ? null
                            : (v) {
                                _dragging = true;
                                widget.onHolding(true);
                                setState(() => _scrub = v);
                              },
                        onChanged: archive.busy || max <= 0 ? null : (v) => setState(() => _scrub = v),
                        onChangeEnd: (v) {
                          _dragging = false;
                          widget.onHolding(false);
                          setState(() => _scrub = null);
                          unawaited(archive.seek(Duration(milliseconds: v.round())));
                          widget.onInteract();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: i18n('archive_forward'),
                      icon: const Icon(AppIcons.vodForward, color: OnVideoColors.foreground),
                      onPressed: archive.busy
                          ? null
                          : () {
                              widget.onInteract();
                              unawaited(archive.seek(archive.position + const Duration(seconds: 10)));
                            },
                    ),
                  ],
                ),
              ),
              if (widget.immersive) RoomReplayActions(controller: widget.controller, onVideo: true),
            ],
          ),
        ),
      );
    },
  );
}

/// Mode-only actions; the original mini/cast/audio/settings controls remain.
class RoomReplayActions extends StatelessWidget {
  /// Uses the room's existing panel scope.
  const new({required this.controller, this.onVideo = false, super.key});

  /// Existing room owner.
  final LiveRoomController controller;

  /// White text on the picture.
  final bool onVideo;
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: controller, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final archive = controller.archive;
    final style = onVideo ? context.textStyles.t12.copyWith(color: OnVideoColors.foreground) : context.textStyles.t12;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton(
            key: const ValueKey('archive-rate'),
            onPressed: archive == null || archive.busy
                ? null
                : () => RoomPanelScope.maybeOf(context)?.open(RoomPanelKind.archiveRate),
            child: Text('${i18n('archive_rate_short')} ${archiveRateLabel(archive?.rate ?? 1)}', style: style),
          ),
          TextButton(
            key: const ValueKey('archive-catalog'),
            onPressed: () => RoomPanelScope.maybeOf(context)?.open(RoomPanelKind.archiveCatalog),
            child: Text(i18n('archive_scenes'), style: style),
          ),
          if (controller.canReturnToLive)
            TextButton(
              key: const ValueKey('archive-return-live'),
              onPressed: archive?.busy == true ? null : () => unawaited(controller.leaveArchive()),
              child: Text(i18n('archive_return_live'), style: style),
            ),
        ],
      ),
    );
  }
}

/// Replaces the live audience figures with truthful replay metadata.
class RoomReplayInfo extends StatelessWidget {
  /// Uses the existing quality/line pickers while [showPickers].
  const new({required this.controller, this.showPickers = true, super.key});

  /// Existing room owner.
  final LiveRoomController controller;

  /// Whether this strip owns the quality and line pickers (A07.46 puts them
  /// in the player's control bar instead).
  final bool showPickers;
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: controller, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final selection = controller.archiveSelection;
    if (selection == null) return const SizedBox.shrink();
    final recording = selection.recording;
    final date = recording.date;
    if (MediaQuery.sizeOf(context).height < 360) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(controller.archiveTitle, style: context.textStyles.t14),
            ),
            RoomReplayActions(controller: controller),
            if (showPickers) StreamPickers(controller: controller),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            controller.archiveTitle,
            key: const ValueKey('archive-visible-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.t16,
          ),
          if (date != null || recording.duration > Duration.zero)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (date != null) '${date.year}.${date.month}.${date.day}',
                  if (recording.duration > Duration.zero)
                    i18n('archive_total_duration', args: {'duration': vodTime(recording.duration)}),
                ].join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                RoomReplayActions(controller: controller),
                if (showPickers) StreamPickers(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Replay tab and side-panel content, without changing the live tabs.
class RoomReplayLibrary extends StatelessWidget {
  /// Lists real segments and loaded creator recordings only.
  const new({required this.controller, this.onClose, this.withComposer = false, super.key});

  /// Existing room owner.
  final LiveRoomController controller;

  /// Side-panel choices close it first.
  final VoidCallback? onClose;

  /// Preserves the original local-danmaku composer beneath the list.
  final bool withComposer;
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: controller, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final archive = controller.archive;
    final selection = controller.archiveSelection;
    if (selection == null) return const SizedBox.shrink();
    final tv = MediaQuery.navigationModeOf(context) == NavigationMode.directional;
    final parts = archive?.segments ?? const <ArchiveVideo>[];
    final list = ListView(
      key: const ValueKey('room-replay-library'),
      padding: const EdgeInsets.all(16),
      children: [
        if (parts.length > 1) ...[
          Text(i18n('archive_parts', args: {'count': '${parts.length}'}), style: context.textStyles.t14),
          for (var i = 0; i < parts.length; i++)
            ListTile(
              key: ValueKey('archive-part-${parts[i].id}'),
              selected: parts[i].id == archive?.video?.id,
              leading: Text('${i + 1}'.padLeft(2, '0'), style: context.textStyles.t14),
              title: Text(
                parts[i] is BilibiliArchivePart ? (parts[i] as BilibiliArchivePart).part.title : parts[i].title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(vodTime(parts[i].duration)),
              onTap: archive == null || archive.busy
                  ? null
                  : () {
                      onClose?.call();
                      unawaited(archive.open(parts[i].id));
                    },
            ),
          const SizedBox(height: 16),
        ],
        Text(i18n('archive_creator_replays'), style: context.textStyles.t14),
        for (final item in selection.recordings.isEmpty ? [selection.recording] : selection.recordings)
          ArchiveRecordingTile(
            key: ValueKey('archive-related-${item.id}'),
            recording: item,
            tv: tv,
            onTap: archive?.busy == true || item.id == selection.recording.id
                ? null
                : () {
                    onClose?.call();
                    unawaited(
                      controller.playArchive(
                        ArchiveSelection(recording: item, recordings: selection.recordings, room: selection.room),
                      ),
                    );
                  },
          ),
      ],
    );
    return withComposer ? LocalComposerBelow(child: list) : list;
  }
}
