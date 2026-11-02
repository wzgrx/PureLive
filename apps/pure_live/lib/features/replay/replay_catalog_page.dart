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
import 'package:pure_live/shared/rooms/archive/archive_time.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// Platforms with an implemented, official creator archive contract.
const replayPlatforms = <String>[SiteIds.huya, SiteIds.douyu, SiteIds.bilibili];

/// One date-led creator archive on phones, desktop and keyboard/remote clients.
class ReplayCatalogPage extends ConsumerStatefulWidget {
  /// A live room supplies identity and decoder ownership, without signed URLs.
  const new({this.room, this.beforePlay, this.onRetire, super.key});

  /// Initial public room.
  final LiveRoom? room;

  /// Stops the live decoder only after the user chooses a recording.
  final Future<void> Function()? beforePlay;

  /// Allows its owner to await actual native cleanup.
  final ValueChanged<Future<void>>? onRetire;
  @override
  ConsumerState<ReplayCatalogPage> createState() => _ReplayCatalogPageState();
}

class _ReplayCatalogPageState extends ConsumerState<ReplayCatalogPage> {
  late final _input = TextEditingController(text: widget.room?.roomId ?? '');
  final _scroll = ScrollController();
  late String _platform = widget.room?.platform ?? SiteIds.huya;
  String _author = '';
  int _generation = 0;
  int _page = 0;
  bool _busy = false;
  bool _opening = false;
  bool _more = false;
  Object? _error;
  CancelToken? _cancel;
  List<_Entry> _entries = const [];
  List<ReplayCollection> _collections = const [];
  ReplayCollection? _collection;
  Map<String, Duration> _positions = const {};
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
    _scroll.dispose();
    super.dispose();
  }

  String _label(String site) => i18n('site_$site');

  Future<void> _submit() async {
    final g = ++_generation;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
      _author = '';
      _page = 0;
      _more = false;
      _entries = const [];
      _positions = const {};
      _collections = const [];
      _collection = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      final text = _input.text.trim();
      String? author;
      final uri = Uri.tryParse(text);
      if (uri != null && uri.hasScheme) {
        if (!{'http', 'https'}.contains(uri.scheme) || uri.userInfo.isNotEmpty || uri.hasPort) {
          throw const FormatException('Invalid replay URL');
        }
        if (_platform == SiteIds.douyu && uri.host == 'v.douyu.com') {
          final id = DouyuVodApi.idFromText(text);
          if (id == null) throw const FormatException('Invalid replay video link');
          final detail = await ref.read(douyuVodProvider).detail(id, cancel: cancel);
          if (!mounted || g != _generation) return;
          final video = detail.video;
          _author = video.authorId;
          _entries = [
            _Entry(
              video,
              title: video.title,
              cover: video.cover,
              date: video.publishedAt?.toLocal(),
              duration: video.duration,
            ),
          ];
          await _readPositions(g);
          return;
        }
        if (_platform == SiteIds.huya) author = HuyaArchiveApi.uidFromText(text);
        if (_platform == SiteIds.bilibili && uri.host == 'space.bilibili.com') {
          final match = RegExp(r'^/([1-9][0-9]{0,18})/(?:lists|channel)(?:/([1-9][0-9]{0,18}))?/?$')
              .firstMatch(uri.path);
          author = match?[1];
          if (match?[2] != null) {
            _collection = ReplayCollection(
              id: int.parse(match![2]!),
              name: i18n('replay_selected_collection'),
              season: uri.queryParameters['type'] == 'season',
            );
          }
        }
        if (author == null) {
          final host = switch (_platform) {
            SiteIds.huya => 'huya.com',
            SiteIds.douyu => 'douyu.com',
            _ => 'live.bilibili.com',
          };
          if (uri.host != host && uri.host != 'www.$host') throw const FormatException('Wrong replay platform');
          final room = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (room.length != 1) throw const FormatException('Invalid room URL');
          author = await ref.read(replayIdentityProvider).resolve(_platform, room.single, cancel: cancel);
        }
      } else {
        if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(text)) throw const FormatException('Invalid room');
        author = await ref.read(replayIdentityProvider).resolve(_platform, text, cancel: cancel);
      }
      if (!mounted || g != _generation) return;
      _author = author;
      if (_platform == SiteIds.bilibili && _collection == null) {
        final all = <String, ReplayCollection>{};
        for (var page = 1; page <= 20; page++) {
          final result = await ref
              .read(bilibiliReplayProvider)
              .collections(int.parse(author), page: page, cancel: cancel);
          if (!mounted || g != _generation) return;
          for (final collection in result.items) {
            all[collection.key] = collection;
          }
          if (!result.hasMore) break;
          if (page == 20) throw const ApiChanged('bilibili', 'Too many replay collections');
        }
        _collections = all.values.toList()..sort((a, b) => b.updated.compareTo(a.updated));
        _collection = _collections.firstOrNull;
      } else if (_collection != null) {
        _collections = [_collection!];
      }
      if (_platform != SiteIds.bilibili || _collection != null) await _load(generation: g);
    } on Object catch (e) {
      if (mounted && g == _generation) setState(() => _error = e);
    } finally {
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _load({int? generation}) async {
    if (_author.isEmpty || generation == null && _busy) return;
    final g = generation ?? _generation;
    final cancel = _cancel ??= CancelToken();
    final page = _page + 1;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      List<_Entry> next;
      bool more;
      if (_platform == SiteIds.huya) {
        final result = await ref.read(huyaArchiveProvider).list(_author, page: page, cancel: cancel);
        next = [
          for (final v in result.videos)
            _Entry(v, title: v.title, cover: v.cover, date: DateTime.tryParse(v.date), duration: v.duration),
        ];
        more = result.hasMore;
      } else if (_platform == SiteIds.douyu) {
        final result = await ref.read(douyuVodProvider).author(_author, page: page, cancel: cancel);
        next = [
          for (final v in result.videos)
            _Entry(v, title: v.title, cover: v.cover, date: v.publishedAt?.toLocal(), duration: v.duration),
        ];
        more = result.hasMore;
      } else {
        final result = await ref
            .read(bilibiliReplayProvider)
            .list(int.parse(_author), _collection!, page: page, cancel: cancel);
        next = [
          for (final v in result.items)
            _Entry(v, title: v.title, cover: v.cover, date: v.publishedAt?.toLocal(), duration: v.duration),
        ];
        more = result.hasMore;
      }
      if (!mounted || g != _generation) return;
      final seen = _entries.map((e) => e.id).toSet();
      setState(() {
        _entries = [..._entries, ...next.where((v) => seen.add(v.id))];
        _page = page;
        _more = more && _entries.length < 1000;
      });
      await _readPositions(g);
    } on Object catch (e) {
      if (mounted && g == _generation) setState(() => _error = e);
    } finally {
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _readPositions(int g) async {
    final positions = <String, Duration>{};
    if (_platform == SiteIds.douyu) {
      for (final v in await ref.read(douyuVodProgressProvider).list()) {
        positions[v.video.id] = v.position;
      }
    } else {
      final progress = ref.read(
        _platform == SiteIds.huya ? huyaArchiveProgressProvider : bilibiliReplayProgressProvider,
      );
      for (final entry in _entries) {
        // Bilibili list rows can lack cid; detail resolves the correct per-part key.
        if (entry.video is VodArchive) {
          positions[entry.id] = (await progress.recent('${entry.id}:'))?.position ?? Duration.zero;
        }
        if (_platform == SiteIds.huya) positions[entry.id] = await progress.position(entry.id);
      }
    }
    if (mounted && g == _generation) setState(() => _positions = positions);
  }

  Future<void> _play(_Entry entry) async {
    if (_opening) return;
    setState(() => _opening = true);
    final g = _generation;
    try {
      await widget.beforePlay?.call();
      if (!mounted || g != _generation) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ArchivePlayerPage(
            videoId: entry.id,
            archiveVideo: entry.video is HuyaArchiveVideo ? entry.video as HuyaArchiveVideo : null,
            bilibiliVideo: entry.video is VodArchive ? entry.video as VodArchive : null,
            onRetire: widget.onRetire,
          ),
        ),
      );
      if (mounted && g == _generation) await _readPositions(g);
    } on Object {
      if (mounted) AppNavigator.toast(i18n('replay_open_failed'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tv = UiMode.parse(watchSetting(ref, Settings.uiMode))
        .showsTv(television: ref.watch(televisionDeviceProvider));
    final resume = _entries.where((e) => (_positions[e.id] ?? Duration.zero) > Duration.zero).firstOrNull;
    return Scaffold(
      key: const ValueKey('replay-catalog-page'),
      appBar: AppBar(
        title: Text(
          widget.room?.nick.isNotEmpty == true && _input.text.trim() == widget.room?.roomId
              ? widget.room!.nick
              : i18n('replay_title'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              key: const ValueKey('replay-catalog-list'),
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.room != null)
                  Row(
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('replay_back_live'))),
                      const SizedBox(width: 12),
                      Text(i18n('replay_title'), style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                if (widget.room == null)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final platform in replayPlatforms)
                        ChoiceChip(
                          key: ValueKey('replay-platform-$platform'),
                          label: Text(_label(platform)),
                          selected: platform == _platform,
                          onSelected: _busy
                              ? null
                              : (_) {
                                  _generation++;
                                  _cancel?.cancel();
                                  setState(() {
                                    _platform = platform;
                                    _author = '';
                                    _entries = const [];
                                    _collections = const [];
                                    _collection = null;
                                    _page = 0;
                                    _more = false;
                                    _error = null;
                                    _input.clear();
                                  });
                                },
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (tv)
                  TvInputField(
                    key: const ValueKey('replay-room-input'),
                    text: _input.text,
                    hint: i18n('replay_input'),
                    title: i18n('replay_title'),
                    icon: AppIcons.openLink,
                    onSubmitted: (text) {
                      _input.text = text;
                      unawaited(_submit());
                    },
                  )
                else
                  TextField(
                    key: const ValueKey('replay-room-input'),
                    controller: _input,
                    decoration: InputDecoration(
                      labelText: i18n('replay_input'),
                      helperText: i18n('replay_input_hint'),
                      suffixIcon: IconButton(
                        tooltip: i18n('replay_load'),
                        onPressed: _busy ? null : () => unawaited(_submit()),
                        icon: const Icon(AppIcons.forward),
                      ),
                    ),
                    onSubmitted: (_) => unawaited(_submit()),
                  ),
                const SizedBox(height: 20),
                if (_collections.length > 1)
                  DropdownButtonFormField<String>(
                    key: const ValueKey('replay-collection'),
                    initialValue: _collection?.key,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: i18n('replay_collection')),
                    items: [
                      for (final c in _collections)
                        DropdownMenuItem(
                          value: c.key,
                          child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (key) {
                            _generation++;
                            _cancel?.cancel();
                            _cancel = CancelToken();
                            setState(() {
                              _collection = _collections.firstWhere((c) => c.key == key);
                              _entries = const [];
                              _positions = const {};
                              _page = 0;
                              _more = false;
                            });
                            unawaited(_load());
                          },
                  ),
                if (resume != null)
                  ListTile(
                    key: const ValueKey('replay-resume'),
                    leading: const Icon(AppIcons.play),
                    title: Text(i18n('replay_continue')),
                    subtitle: Text(
                      '${resume.title}\n${vodTime(_positions[resume.id]!)}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: _opening ? null : () => unawaited(_play(resume)),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n(
                            _error is FormatException
                                ? 'replay_invalid'
                                : _error is NeedsLogin
                                ? 'replay_needs_login'
                                : _error is RiskControl || _error is RateLimited
                                ? 'replay_refused'
                                : 'replay_failed',
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_page == 0 ? _submit() : _load()),
                          child: Text(i18n('retry')),
                        ),
                      ],
                    ),
                  ),
                if (_entries.isEmpty && !_busy && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(i18n(_author.isEmpty ? 'replay_enter' : 'replay_empty')),
                  ),
                for (final entry in _entries) ...[
                  _ArchiveRow(
                    entry: entry,
                    position: _positions[entry.id],
                    onTap: _opening ? null : () => unawaited(_play(entry)),
                  ),
                  const Divider(height: 24),
                ],
                if (_more)
                  Center(
                    child: OutlinedButton(
                      key: const ValueKey('replay-more'),
                      onPressed: _busy ? null : () => unawaited(_load()),
                      child: Text(i18n('douyu_vod_more')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Entry {
  const new(this.video, {required this.title, required this.cover, required this.date, required this.duration});
  final Object video;
  final String title;
  final String cover;
  final DateTime? date;
  final Duration duration;
  String get id => switch (video) {
    final HuyaArchiveVideo v => v.id,
    final DouyuVodVideo v => v.id,
    final VodArchive v => v.bvid,
    _ => throw StateError('Unknown archive'),
  };
}

class _ArchiveRow extends StatelessWidget {
  const new({required this.entry, required this.position, required this.onTap});
  final _Entry entry;
  final Duration? position;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final date = entry.date;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('replay-recording-${entry.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date != null)
              SizedBox(
                width: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${date.month}/${date.day}',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                    ),
                    Text('${date.year}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            if (entry.cover.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  entry.cover,
                  width: 80,
                  height: 50,
                  cacheWidth: 240,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(width: 80, height: 50, child: Icon(AppIcons.play)),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text(vodTime(entry.duration), style: Theme.of(context).textTheme.bodySmall),
                  if (position != null && position! > Duration.zero)
                    Text(
                      i18n('replay_position', args: {'position': vodTime(position!)}),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.primary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
