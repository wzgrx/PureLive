import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/room/tv_live_play_page.dart' show tvEngineConfig;
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// Two streams, one audio focus and the TV's normal remote-control targets.
final class TvDualViewPane extends ConsumerStatefulWidget {
  /// Creates the TV view. The home removes it on leaving the destination.
  const new({super.key});

  @override
  ConsumerState<TvDualViewPane> createState() => _TvDualViewPaneState();
}

class _TvDualViewPaneState extends ConsumerState<TvDualViewPane> {
  late final MultiviewController _controller;
  late final Future<void> _ready;
  late final AppLifecycleListener _lifecycle;
  bool _choosing = false;
  bool _foreground = true;
  final _pending = <Future<void>>{};

  Future<void> _track(Future<void> operation) async {
    _pending.add(operation);
    try {
      await operation;
    } finally {
      _pending.remove(operation);
    }
  }

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    final sites = ref.read(sitesProvider);
    final danmaku = ref.read(danmakuProvider);
    final createSession = ref.read(playbackSessionFactoryProvider);
    final engine = tvEngineConfig(store.settings, allowLiveRewind: false);
    _controller = MultiviewController(
      siteOf: sites.maybeOf,
      newSession: () => createSession(config: engine),
      danmakuFor: danmaku.connectionFor,
      danmakuSupports: (_) => false,
      store: store,
      mobile: true,
      maxCells: 2,
      initialLayout: MultiviewLayout.dual,
      persistSession: false,
      allowAudioMix: false,
      toast: (message) => AppNavigator.toast(message),
    );
    _ready = Future.wait<void>([TvWallpaperVideo.hold(), _controller.start()]).then((_) {});
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        if (!_foreground) {
          for (var i = 0; i < _controller.cells.length; i++) {
            unawaited(_track(_controller.remove(i)).catchError((Object _) {}));
          }
        }
      },
    );
  }

  Future<void> _choose(int index) async {
    if (_choosing || !_foreground) return;
    _choosing = true;
    try {
      final store = ref.read(storeProvider);
      final sources = await Future.wait([store.savedRoomQueue.all(), store.follows.all(), store.history.all()]);
      if (!mounted || !_foreground) return;
      final sites = ref.read(sitesProvider);
      final seen = <String>{};
      final rooms = [
        for (final room in sources.expand((source) => source))
          if (sites.maybeOf(room.platform) != null && seen.add(room.identityKey)) room,
      ].take(100).toList();
      if (rooms.isEmpty) {
        AppNavigator.toast(i18n('tv_multiview_empty'));
        return;
      }
      final choice = await showTvChoice<LiveRoom>(
        context,
        title: i18n('multiview_title'),
        options: [
          for (final room in rooms)
            TvChoice(
              value: room,
              label: room.nick.isEmpty ? room.roomId : room.nick,
              description: room.title.isEmpty ? null : room.title,
            ),
        ],
      );
      if (!mounted || !_foreground || choice == null) return;
      await _ready;
      if (!mounted || !_foreground) return;
      await _controller.setAudioFocus(index);
      if (mounted && _foreground) await _track(_controller.assign(index, choice));
    } on Object {
      if (mounted) AppNavigator.toast(i18n('tv_multiview_pick_failed'));
    } finally {
      _choosing = false;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.dispose();
    final cleanup = Future.wait<void>([_ready, ..._pending, _controller.retirement]).then((_) {});
    unawaited(TvWallpaperVideo.releaseAfter(cleanup));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Padding(
        padding: EdgeInsets.all(scale.px(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n('multiview_title'), style: scale.font(TvTextSize.title, color: palette.text)),
            Text(i18n('tv_multiview_hint'), style: scale.font(TvTextSize.small, color: palette.textSecondary)),
            SizedBox(height: scale.px(18)),
            Expanded(
              child: Row(
                children: [
                  for (final (index, cell) in _controller.cells.indexed) ...[
                    if (index > 0) SizedBox(width: scale.px(14)),
                    Expanded(child: _tile(context, index, cell)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int index, MultiviewCell cell) {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final room = cell.room;
    final session = cell.session;
    final title = room == null
        ? i18n('multiview_cell_number', args: {'index': '${index + 1}'})
        : room.nick.isEmpty
        ? room.roomId
        : room.nick;
    return TvFocusable(
      key: ValueKey('tv-multiview-cell-$index'),
      zoom: false,
      onTap: () => unawaited(_choose(index)),
      onLongPress: room == null ? null : () => unawaited(_track(_controller.remove(index)).catchError((Object _) {})),
      onFocusChange: (focused) {
        if (focused) unawaited(_controller.setAudioFocus(index));
      },
      builder: (context, focused) => Material(
        color: focused ? palette.highest : palette.low,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(scale.px(12)),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: scale.font(22, color: palette.text),
              ),
            ),
            Expanded(
              child: session != null && cell.stage == CellStage.playing
                  ? IgnorePointer(child: LiveVideoView(session: session))
                  : Center(
                      child: Text(
                        i18n(switch (cell.stage) {
                          CellStage.resolving => 'tv_multiview_loading',
                          CellStage.offline || CellStage.failed => 'tv_multiview_pick_failed',
                          _ => 'tv_multiview_pick',
                        }),
                        style: scale.font(18, color: palette.textSecondary),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
