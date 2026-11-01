import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/app/vod.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/archive/archive_player_page.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// Public presenter archive with deterministic pagination, errors and retry.
class HuyaArchivePage extends ConsumerStatefulWidget {
  /// An existing room pre-fills its public identity; no live media is opened.
  const new({this.room, this.beforePlay, this.onRetire, super.key});

  /// Optional initial room, including its presenter uid when known.
  final LiveRoom? room;

  /// Releases an owning live session before a VOD decoder is opened.
  final Future<void> Function()? beforePlay;

  /// Allows the owner to wait for asynchronous native retirement before resuming.
  final ValueChanged<Future<void>>? onRetire;

  @override
  ConsumerState<HuyaArchivePage> createState() => _HuyaArchivePageState();
}

class _HuyaArchivePageState extends ConsumerState<HuyaArchivePage> {
  late final TextEditingController _input = TextEditingController(text: widget.room?.roomId ?? '');
  String _uid = '';
  int _generation = 0;
  int _page = 0;
  bool _busy = false;
  bool _more = false;
  Object? _error;
  List<HuyaArchiveVideo> _videos = const [];
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    if (widget.room != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_submit());
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancel?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final generation = ++_generation;
    _cancel?.cancel();
    _uid = '';
    _page = 0;
    _videos = const [];
    _more = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = _input.text.trim();
      String? uid;
      if (text.startsWith('http://') || text.startsWith('https://')) {
        uid = HuyaArchiveApi.uidFromText(text);
        if (uid == null) throw const FormatException('Invalid archive URL');
      } else {
        if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(text)) throw const FormatException('Invalid room number');
        var room = text == widget.room?.roomId ? widget.room : null;
        if (room?.userId?.isNotEmpty != true) {
          room = await ref.read(sitesProvider).of(SiteIds.huya).getRoomDetail(roomId: text);
        }
        uid = room?.userId;
        if (uid == null || !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(uid)) {
          throw const ApiChanged('huya', 'Presenter uid missing');
        }
      }
      if (!mounted || generation != _generation) return;
      _uid = uid;
      await _load(generation: generation);
    } on Object catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _load({int? generation}) async {
    if (_uid.isEmpty || (_busy && generation == null)) return;
    final current = generation ?? _generation;
    final cancel = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(huyaArchiveProvider).list(_uid, page: _page + 1, cancel: cancel);
      if (!mounted || current != _generation) return;
      final ids = _videos.map((v) => v.id).toSet();
      setState(() {
        _videos = [..._videos, ...result.videos.where((v) => ids.add(v.id))];
        _more = result.hasMore;
        _page++;
      });
    } on Object catch (error) {
      if (mounted && current == _generation) setState(() => _error = error);
    } finally {
      if (mounted && current == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _play(HuyaArchiveVideo video) async {
    try {
      await widget.beforePlay?.call();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'huya-archive-player'),
          builder: (_) => ArchivePlayerPage(videoId: video.id, archiveVideo: video, onRetire: widget.onRetire),
        ),
      );
    } on Object {
      if (mounted) AppNavigator.toast(i18n('huya_replay_open_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tv = UiMode.parse(watchSetting(ref, Settings.uiMode))
        .showsTv(television: ref.watch(televisionDeviceProvider));
    final title = widget.room?.nick.trim();
    return Scaffold(
      key: const ValueKey('huya-archive-page'),
      appBar: AppBar(title: Text(i18n('huya_replay_title'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null && title.isNotEmpty) Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(i18n('huya_replay_hint')),
                  if (tv)
                    TvInputField(
                      key: const ValueKey('huya-archive-input'),
                      text: _input.text,
                      hint: i18n('huya_replay_input'),
                      title: i18n('huya_replay_title'),
                      icon: AppIcons.link,
                      onSubmitted: (value) {
                        _input.text = value;
                        unawaited(_submit());
                      },
                    )
                  else
                    TextField(
                      key: const ValueKey('huya-archive-input'),
                      controller: _input,
                      decoration: InputDecoration(labelText: i18n('huya_replay_input')),
                      onSubmitted: (_) => unawaited(_submit()),
                    ),
                  FilledButton(
                    key: const ValueKey('huya-archive-search'),
                    onPressed: _busy ? null : () => unawaited(_submit()),
                    child: Text(i18n('douyu_vod_search')),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i18n(
                          _error is FormatException
                              ? 'huya_replay_invalid'
                              : _error is NeedsLogin || _error is RiskControl
                              ? 'huya_replay_refused'
                              : 'huya_replay_failed',
                        ),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('huya-archive-retry'),
                      onPressed: _busy ? null : () => unawaited(_uid.isEmpty ? _submit() : _load()),
                      child: Text(i18n('retry')),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _videos.isEmpty && !_busy && _error == null
                  ? Center(child: Text(i18n(_uid.isEmpty ? 'huya_replay_enter' : 'huya_replay_empty')))
                  : ListView.builder(
                      key: const ValueKey('huya-archive-list'),
                      padding: const EdgeInsets.all(12),
                      itemCount: _videos.length + (_more ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _videos.length) {
                          return Center(
                            child: FilledButton(
                              key: const ValueKey('huya-archive-more'),
                              onPressed: _busy ? null : () => unawaited(_load()),
                              child: Text(i18n('douyu_vod_more')),
                            ),
                          );
                        }
                        final video = _videos[index];
                        final tile = ListTile(
                          key: ValueKey('huya-archive-${video.id}'),
                          leading: video.cover.isEmpty
                              ? const Icon(AppIcons.play)
                              : Image.network(
                                  video.cover,
                                  width: 96,
                                  height: 54,
                                  cacheWidth: 320,
                                  cacheHeight: 180,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(AppIcons.play),
                                ),
                          title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              video.date,
                              '${video.duration.inHours}:${(video.duration.inMinutes % 60).toString().padLeft(2, '0')}:${(video.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                            ].where((s) => s.isNotEmpty).join(' · '),
                          ),
                          onTap: tv ? null : () => unawaited(_play(video)),
                        );
                        return Card(
                          child: tv
                              ? TvFocusable(
                                  autofocus: index == 0,
                                  zoom: false,
                                  onTap: () => unawaited(_play(video)),
                                  builder: (_, _) => tile,
                                )
                              : tile,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
