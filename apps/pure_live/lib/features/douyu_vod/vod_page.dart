import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/vod.dart';
import 'package:pure_live/features/douyu_vod/vod_player_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/archive/archive_time.dart';

export 'package:pure_live/shared/rooms/archive/archive_time.dart' show vodTime;

/// One responsive/focusable catalog for phones, desktop and TV. Search uses the
/// official separate video/replay tabs, author pages use their own server pages.
class DouyuVodCatalogPage extends ConsumerStatefulWidget {
  /// Optional route argument is a search term or official video URL.
  const new({required this.route, super.key});

  /// The route arguments.
  final RouteArgs route;

  @override
  ConsumerState<DouyuVodCatalogPage> createState() => _DouyuVodPageState();
}

class _DouyuVodPageState extends ConsumerState<DouyuVodCatalogPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  CancelToken? _cancel;
  int _generation = 0;
  int _page = 0;
  bool _busy = false;
  bool _more = false;
  bool _replay = true;
  bool _history = false;
  String _query = '';
  String _author = '';
  String _authorName = '';
  Object? _error;
  List<DouyuVodVideo> _videos = const [];
  Map<String, Duration> _positions = const {};

  @override
  void initState() {
    super.initState();
    final argument = widget.route.arguments;
    if (argument is String) _search.text = argument;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(argument is String && argument.trim().isNotEmpty ? _submit() : _load(reset: true)),
    );
  }

  @override
  void dispose() {
    _generation++;
    _cancel?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!mounted || (_busy && !reset)) return;
    if (reset) {
      _generation++;
      _cancel?.cancel();
      _page = 0;
      _videos = const [];
      _positions = const {};
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    final generation = _generation;
    final cancel = _cancel = CancelToken();
    final page = _page + 1;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      List<DouyuVodVideo> videos;
      var more = false;
      if (_history) {
        final entries = await ref.read(douyuVodProgressProvider).list();
        videos = [for (final entry in entries) entry.video];
        if (mounted && generation == _generation) {
          _positions = {for (final entry in entries) entry.video.id: entry.position};
        }
      } else {
        final source = ref.read(douyuVodProvider);
        final DouyuVodPage result;
        if (_author.isNotEmpty) {
          result = await source.author(_author, replay: _replay, page: page, cancel: cancel);
        } else if (_query.isNotEmpty) {
          result = await source.search(_query, replay: _replay, page: page, cancel: cancel);
        } else {
          result = await source.home(cancel: cancel);
        }
        videos = result.videos;
        more = result.hasMore;
      }
      if (!mounted || generation != _generation) return;
      final unique = {for (final video in _videos) video.id: video};
      for (final video in videos) {
        unique[video.id] = video;
      }
      setState(() {
        _videos = unique.values.toList();
        _page = page;
        _more = more;
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final text = _search.text.trim();
    final id = text.contains('://') || RegExp(r'^[A-Za-z0-9]{16}$').hasMatch(text)
        ? DouyuVodApi.idFromText(text)
        : null;
    if (id != null) {
      await _play(DouyuVodVideo(id: id, title: id));
      return;
    }
    _query = text;
    _author = '';
    _history = false;
    await _load(reset: true);
  }

  Future<void> _play(DouyuVodVideo video) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => DouyuVodPlayerPage(videoId: video.id)));
    if (mounted && _history) await _load(reset: true);
  }

  void _authorOf(DouyuVodVideo video) {
    _author = video.authorId;
    _authorName = video.authorName;
    _query = '';
    _history = false;
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(i18n('douyu_vod_title')),
      actions: [
        IconButton(
          key: const ValueKey('vod-home'),
          tooltip: i18n('douyu_vod_recommendations'),
          onPressed: () {
            _query = '';
            _author = '';
            _history = false;
            _search.clear();
            unawaited(_load(reset: true));
          },
          icon: const Icon(AppIcons.vodHome),
        ),
        IconButton(
          key: const ValueKey('vod-history'),
          tooltip: i18n('douyu_vod_history'),
          onPressed: () {
            _history = true;
            _author = '';
            unawaited(_load(reset: true));
          },
          icon: const Icon(AppIcons.watchHistory),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const ValueKey('vod-search'),
                  controller: _search,
                  maxLength: 240,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => unawaited(_submit()),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: i18n('douyu_vod_search_hint'),
                    suffixIcon: IconButton(
                      tooltip: i18n('douyu_vod_search'),
                      onPressed: () => unawaited(_submit()),
                      icon: const Icon(AppIcons.search),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (!_history && _author.isEmpty && _query.isEmpty)
                      Text(i18n('douyu_vod_recommendations'), style: context.textStyles.t14),
                    if (!_history && (_author.isNotEmpty || _query.isNotEmpty)) ...[
                      ChoiceChip(
                        label: Text(i18n('douyu_vod_replays')),
                        selected: _replay,
                        onSelected: (_) {
                          _replay = true;
                          unawaited(_load(reset: true));
                        },
                      ),
                      ChoiceChip(
                        label: Text(i18n('douyu_vod_videos')),
                        selected: !_replay,
                        onSelected: (_) {
                          _replay = false;
                          unawaited(_load(reset: true));
                        },
                      ),
                    ],
                    if (_author.isNotEmpty)
                      Chip(
                        label: Text(_authorName.isEmpty ? _author : _authorName),
                        onDeleted: () {
                          _author = '';
                          unawaited(_load(reset: true));
                        },
                      ),
                    if (_history) Text(i18n('douyu_vod_history')),
                    if (_history)
                      TextButton(
                        onPressed: () async {
                          if (await showAppConfirmDialog(
                            context: context,
                            title: i18n('douyu_vod_clear_history'),
                            message: i18n('douyu_vod_clear_history_hint'),
                            confirmLabel: i18n('clear'),
                          )) {
                            await ref.read(douyuVodProgressProvider).clear();
                            if (mounted) await _load(reset: true);
                          }
                        },
                        child: Text(i18n('douyu_vod_clear_history')),
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
                      Expanded(child: Text(i18n(_error is NeedsLogin ? 'douyu_vod_login' : 'douyu_vod_load_failed'))),
                      TextButton(
                        onPressed: () => unawaited(_load(reset: _page == 0)),
                        child: Text(i18n('retry')),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _videos.isEmpty && !_busy && _error == null
                    ? Center(child: Text(i18n('douyu_vod_empty')))
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: _videos.length + (_more ? 1 : 0),
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, index) {
                          if (index == _videos.length) {
                            return Center(
                              child: FilledButton(
                                onPressed: _busy ? null : () => unawaited(_load()),
                                child: Text(i18n('douyu_vod_more')),
                              ),
                            );
                          }
                          final video = _videos[index];
                          return Card(
                            child: ListTile(
                              key: ValueKey('vod-video-${video.id}'),
                              isThreeLine: true,
                              leading: video.cover.isEmpty
                                  ? const Icon(AppIcons.play, size: 40)
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        video.cover,
                                        width: 96,
                                        height: 64,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(AppIcons.vodCatalog),
                                      ),
                                    ),
                              title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                [
                                  video.authorName,
                                  if (video.duration > Duration.zero) vodTime(video.duration),
                                  if ((_positions[video.id] ?? Duration.zero) > Duration.zero)
                                    i18n('douyu_vod_resume_at', args: {'time': vodTime(_positions[video.id]!)}),
                                ].where((text) => text.isNotEmpty).join(' · '),
                              ),
                              onTap: () => unawaited(_play(video)),
                              trailing: video.authorId.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: i18n('douyu_vod_author'),
                                      onPressed: () => _authorOf(video),
                                      icon: const Icon(AppIcons.vodCatalog),
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
