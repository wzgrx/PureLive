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
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';
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
  Future<void> _retirement = Future.value();
  bool _more = false;
  Object? _error;
  CancelToken? _cancel;
  List<ArchiveRecording> _entries = const [];
  List<ReplayCollection> _collections = const [];
  ReplayCollection? _collection;
  Map<String, Duration> _positions = const {};
  final Map<String, int> _partNumbers = {};
  String? _dateFilter;
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
      _dateFilter = null;
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
            ArchiveRecording(
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
      List<ArchiveRecording> next;
      bool more;
      if (_platform == SiteIds.huya) {
        final result = await ref.read(huyaArchiveProvider).list(_author, page: page, cancel: cancel);
        next = [
          for (final v in result.videos)
            ArchiveRecording(v, title: v.title, cover: v.cover, date: DateTime.tryParse(v.date), duration: v.duration),
        ];
        more = result.hasMore;
      } else if (_platform == SiteIds.douyu) {
        final result = await ref.read(douyuVodProvider).author(_author, page: page, cancel: cancel);
        next = [
          for (final v in result.videos)
            ArchiveRecording(v, title: v.title, cover: v.cover, date: v.publishedAt?.toLocal(), duration: v.duration),
        ];
        more = result.hasMore;
      } else {
        final result = await ref
            .read(bilibiliReplayProvider)
            .list(int.parse(_author), _collection!, page: page, cancel: cancel);
        next = [
          for (final v in result.items)
            ArchiveRecording(v, title: v.title, cover: v.cover, date: v.publishedAt?.toLocal(), duration: v.duration),
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

  Future<void> _play(ArchiveRecording entry) async {
    if (_opening) return;
    setState(() => _opening = true);
    final g = _generation;
    try {
      await _retirement;
      await widget.beforePlay?.call();
      if (!mounted || g != _generation) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ArchivePlayerPage(
            videoId: entry.id,
            archiveVideo: entry.video is HuyaArchiveVideo ? entry.video as HuyaArchiveVideo : null,
            bilibiliVideo: entry.video is VodArchive ? entry.video as VodArchive : null,
            onRetire: (future) {
              _retirement = future;
              widget.onRetire?.call(future);
            },
            recordings: List.unmodifiable(_entries),
            room: _input.text.trim() == widget.room?.roomId ? widget.room : null,
            onProgress: (id, part, position) {
              // The player can report its last segment from dispose while the
              // widget tree is locked. The catalog refreshes after retirement.
              if (part != null) _partNumbers[id] = part;
            },
          ),
        ),
      );
      await _retirement;
      if (mounted && g == _generation) await _readPositions(g);
    } on Object {
      if (mounted) AppNavigator.toast(i18n('replay_open_failed'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _day(DateTime date) => '${date.year}-${date.month}-${date.day}';
  Future<void> _other() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReplayCatalogPage(
          beforePlay: widget.beforePlay,
          onRetire: (future) {
            _retirement = future;
            widget.onRetire?.call(future);
          },
        ),
      ),
    );
    await _retirement;
  }

  String _resumeLabel(ArchiveRecording entry) {
    final position = vodTime(_positions[entry.id] ?? Duration.zero);
    final part = _partNumbers[entry.id];
    return i18n(
      part != null
          ? 'archive_resume_part'
          : entry.video is VodArchive
          ? 'archive_part_resume_position'
          : 'replay_position',
      args: {'index': '${part ?? 1}', 'position': position},
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = UiMode.parse(watchSetting(ref, Settings.uiMode))
        .showsTv(television: ref.watch(televisionDeviceProvider));
    final resume = _entries.where((e) => (_positions[e.id] ?? Duration.zero) > Duration.zero).firstOrNull;
    final dates = <String, DateTime>{
      for (final entry in _entries)
        if (entry.date != null) _day(entry.date!): entry.date!,
    };
    final visible = _dateFilter == null
        ? _entries
        : _entries.where((e) => e.date != null && _day(e.date!) == _dateFilter).toList();
    return Scaffold(
      key: const ValueKey('replay-catalog-page'),
      appBar: AppBar(
        title: Text(widget.room?.nick.isNotEmpty == true ? widget.room!.nick : i18n('replay_title')),
        actions: [
          if (widget.room != null)
            IconButton(
              key: const ValueKey('replay-open-query'),
              tooltip: i18n('archive_open_query'),
              icon: const Icon(AppIcons.openLink),
              onPressed: () => unawaited(_other()),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              key: const ValueKey('replay-catalog-list'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (widget.room == null) ...[
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
                                    _positions = const {};
                                    _collections = const [];
                                    _collection = null;
                                    _page = 0;
                                    _more = false;
                                    _error = null;
                                    _dateFilter = null;
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
                  const SizedBox(height: 16),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(i18n('replay_title'), style: context.textStyles.t14),
                        Text(
                          i18n('archive_recording_dates'),
                          style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                if (_collections.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
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
                                _dateFilter = null;
                              });
                              unawaited(_load());
                            },
                    ),
                  ),
                if (resume != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(width: 2, color: Theme.of(context).colorScheme.primary)),
                    ),
                    child: ListTile(
                      key: const ValueKey('replay-resume'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      title: Text(
                        archiveDisplayTitle(resume.title, author: resume.author),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.t14,
                      ),
                      subtitle: Text(_resumeLabel(resume)),
                      trailing: const Icon(AppIcons.play),
                      onTap: _opening ? null : () => unawaited(_play(resume)),
                    ),
                  ),
                if (dates.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(i18n('archive_all_dates')),
                            selected: _dateFilter == null,
                            onSelected: (_) => setState(() => _dateFilter = null),
                          ),
                          for (final item in dates.entries.take(6))
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Text('${item.value.month}.${item.value.day}'),
                                selected: _dateFilter == item.key,
                                onSelected: (_) => setState(() => _dateFilter = item.key),
                              ),
                            ),
                        ],
                      ),
                    ),
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
                if (visible.isEmpty && !_busy && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(i18n(_author.isEmpty ? 'replay_enter' : 'replay_empty')),
                  ),
                for (final entry in visible) ...[
                  _ArchiveRow(
                    entry: entry,
                    position: _positions[entry.id],
                    onTap: _opening ? null : () => unawaited(_play(entry)),
                    tv: tv,
                    autofocus: tv && identical(entry, visible.first),
                  ),
                  const Divider(height: 12),
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

class _ArchiveRow extends StatelessWidget {
  const new({
    required this.entry,
    required this.position,
    required this.onTap,
    this.tv = false,
    this.autofocus = false,
  });
  final ArchiveRecording entry;
  final Duration? position;
  final VoidCallback? onTap;
  final bool tv;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => ArchiveRecordingTile(
    key: ValueKey('replay-recording-${entry.id}'),
    recording: entry,
    position: position,
    onTap: onTap,
    tv: tv,
    autofocus: autofocus,
  );
}
