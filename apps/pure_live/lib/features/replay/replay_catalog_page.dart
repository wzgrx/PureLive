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
import 'package:pure_live/features/replay/replay_query.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/archive/archive_player_page.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';
import 'package:pure_live/shared/rooms/archive/archive_time.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// Literal translation keys keep all date presets visible to locale audits.
const replayDatePresetLabels = {
  'all': 'replay_date_all',
  'today': 'replay_date_today',
  'yesterday': 'replay_date_yesterday',
  'three': 'replay_date_three',
  'week': 'replay_date_week',
  'month': 'replay_date_month',
  'quarter': 'replay_date_quarter',
  'year': 'replay_date_year',
  'custom': 'replay_date_custom',
};

/// Platforms with an implemented, official creator archive contract.
const replayPlatforms = <String>[SiteIds.huya, SiteIds.douyu, SiteIds.bilibili];

/// One date-led creator archive on phones, desktop and keyboard/remote clients.
class ReplayCatalogPage extends ConsumerStatefulWidget {
  /// A live room supplies identity and decoder ownership, without signed URLs.
  const new({this.room, this.beforePlay, this.onRetire, this.pickOnly = false, super.key});

  /// Picks metadata for the existing live room, preserving its native session.
  final bool pickOnly;

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
  final _keyword = TextEditingController();
  ReplayCatalogQuery _query = ReplayCatalogQuery();
  String _datePreset = 'all';
  Timer? _scanNext;
  bool _fillQueued = false;
  int _emptyPages = 0;
  bool _repeatedPageStop = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
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
    _keyword.dispose();
    _cancelScan();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  String _label(String site) => i18n('site_$site');

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
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
      _query = ReplayCatalogQuery();
      _datePreset = 'all';
      _keyword.clear();
      _emptyPages = 0;
      _repeatedPageStop = false;
      _cancelScan();
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
      if (mounted && g == _generation) {
        setState(() => _busy = false);
        _scheduleLoad();
      }
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
      final fresh = next.where((entry) => seen.add(entry.id)).toList();
      setState(() {
        _entries = [..._entries, ...fresh];
        _page = page;
        _emptyPages = fresh.isEmpty && more ? _emptyPages + 1 : 0;
        _repeatedPageStop = _emptyPages >= 3;
        _more = more && !_repeatedPageStop;
      });
      await _readPositions(g);
    } on Object catch (e) {
      if (mounted && g == _generation) setState(() => _error = e);
    } finally {
      if (mounted && g == _generation) {
        setState(() => _busy = false);
        _scheduleLoad();
      }
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
    if (widget.pickOnly) {
      Navigator.of(context)
          .pop(ArchiveSelection(recording: entry, recordings: List.unmodifiable(_entries), room: widget.room));
      return;
    }
    setState(() => _opening = true);
    final g = _generation;
    try {
      await ref.read(beforeArchivePlaybackProvider)();
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
      if (mounted && g == _generation) await _readPositions(g);
    } on Object {
      if (mounted) AppNavigator.toast(i18n('replay_open_failed'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  List<ArchiveRecording> get _visible => _entries.where(_query.matches).toList();

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 500) _scheduleLoad();
  }

  void _scheduleLoad() {
    if (_fillQueued || !mounted || _busy || !_more || _error != null || _scanNext != null) return;
    _fillQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fillQueued = false;
      if (!mounted || _busy || !_more || _error != null || !_scroll.hasClients) return;
      final needsPage = _scroll.position.extentAfter < 500 || (_query.active && _visible.length < 30);
      if (!needsPage) return;
      final generation = _generation;
      // Cooperative search extends to subsequent pages, at most once a second.
      // Its progress labels state the examined range, never a whole-site claim.
      _scanNext = Timer(const Duration(seconds: 1), () {
        _scanNext = null;
        if (mounted && generation == _generation && !_busy && _more && _error == null) unawaited(_load());
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _cancelScan() {
    _scanNext?.cancel();
    _scanNext = null;
  }

  void _keywordChanged(String value) {
    _cancelScan();
    setState(() => _query = ReplayCatalogQuery(keyword: value, from: _query.from, through: _query.through));
    _scheduleLoad();
  }

  Future<void> _pickDates(BuildContext anchor) async {
    final options = replayDatePresetLabels.keys.toList();
    final index = await showSmallMenu(
      anchor,
      entries: [for (final id in options) i18n(replayDatePresetLabels[id]!)],
      current: options.indexOf(_datePreset),
      semanticLabel: i18n('replay_date_range'),
    );
    final selected = index == null ? null : options[index];
    if (!mounted || selected == null) return;
    ReplayCatalogQuery query;
    if (selected == 'custom') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        initialDateRange: _query.from == null || _query.through == null
            ? null
            : DateTimeRange(start: _query.from!, end: _query.through!),
      );
      if (!mounted || range == null) return;
      query = ReplayCatalogQuery(keyword: _keyword.text, from: range.start, through: range.end);
    } else {
      query = _query.preset(selected, DateTime.now());
    }
    _cancelScan();
    setState(() {
      _query = query;
      _datePreset = selected;
    });
    _scheduleLoad();
  }

  String get _dateLabel {
    if (_datePreset != 'custom') return i18n(replayDatePresetLabels[_datePreset] ?? 'replay_date_all');
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatShortDate(_query.from!)} – ${localizations.formatShortDate(_query.through!)}';
  }

  Widget _catalogList({
    required bool tv,
    required List<ArchiveRecording> visible,
    required List<Widget> header,
    required List<Widget> footer,
  }) => ListView.builder(
    key: const ValueKey('replay-catalog-list'),
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    itemCount: header.length + visible.length + footer.length,
    itemBuilder: (context, index) {
      if (index < header.length) return header[index];
      final row = index - header.length;
      if (row >= visible.length) return footer[row - visible.length];
      final entry = visible[row];
      return Column(
        key: ValueKey('replay-result-${entry.id}'),
        children: [
          _ArchiveRow(
            entry: entry,
            position: _positions[entry.id],
            onTap: _opening ? null : () => unawaited(_play(entry)),
            tv: tv,
            autofocus: tv && row == 0,
          ),
          const Divider(height: 12),
        ],
      );
    },
  );
  Future<void> _other() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReplayCatalogPage(
          pickOnly: widget.pickOnly,
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
    final resume = _entries
        .where(_query.matches)
        .where((e) => (_positions[e.id] ?? Duration.zero) > Duration.zero)
        .firstOrNull;
    final visible = _visible;
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
            child: _catalogList(
              tv: tv,
              visible: visible,
              header: [
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
                                    _query = ReplayCatalogQuery();
                                    _datePreset = 'all';
                                    _keyword.clear();
                                    _emptyPages = 0;
                                    _repeatedPageStop = false;
                                    _cancelScan();
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
                                _query = ReplayCatalogQuery();
                                _datePreset = 'all';
                                _keyword.clear();
                                _emptyPages = 0;
                                _repeatedPageStop = false;
                                _cancelScan();
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
                if (_author.isNotEmpty) ...[
                  if (tv)
                    TvInputField(
                      key: const ValueKey('replay-keyword'),
                      text: _keyword.text,
                      hint: i18n('replay_search_hint'),
                      title: i18n('replay_search_hint'),
                      icon: AppIcons.search,
                      onSubmitted: (text) {
                        _keyword.text = text;
                        _keywordChanged(text);
                      },
                    )
                  else
                    TextField(
                      key: const ValueKey('replay-keyword'),
                      controller: _keyword,
                      onChanged: _keywordChanged,
                      decoration: InputDecoration(
                        labelText: i18n('replay_search_label'),
                        hintText: i18n('replay_search_hint'),
                        helperMaxLines: 6,
                        helperText: i18n('replay_search_scope'),
                        prefixIcon: const Icon(AppIcons.search),
                        suffixIcon: _keyword.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: i18n('replay_clear_search'),
                                icon: const Icon(AppIcons.close),
                                onPressed: () {
                                  _keyword.clear();
                                  _keywordChanged('');
                                },
                              ),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Builder(
                      builder: (anchor) => TextButton.icon(
                        key: const ValueKey('replay-date-range'),
                        onPressed: () => unawaited(_pickDates(anchor)),
                        icon: const Icon(AppIcons.guideTitle),
                        label: Text(_dateLabel),
                      ),
                    ),
                  ),
                  Text(
                    i18n('replay_scan_progress', args: {'count': '${_entries.length}', 'matches': '${visible.length}'}),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_busy && _entries.isEmpty)
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
                          onPressed: () => unawaited(_author.isEmpty ? _submit() : _load()),
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
              ],
              footer: [
                if (_busy && _entries.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_author.isNotEmpty && !_more && !_busy && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(i18n(_repeatedPageStop ? 'replay_catalog_paused' : 'replay_catalog_end')),
                  ),
                if (_repeatedPageStop)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _emptyPages = 0;
                        _repeatedPageStop = false;
                        _more = true;
                      });
                      unawaited(_load());
                    },
                    child: Text(i18n('retry')),
                  ),
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
