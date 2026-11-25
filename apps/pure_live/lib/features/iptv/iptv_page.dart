import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/iptv/iptv_cards.dart';
import 'package:pure_live/features/iptv/iptv_data.dart';
import 'package:pure_live/features/iptv/iptv_import.dart';
import 'package:pure_live/features/iptv/iptv_settings.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// IPTV: playlists, programme guides and their syncs (3.x
/// `lib/modules/iptv`: `IptvPage` "IPTV 设置" and `IptvManagePage`
/// "订阅源管理", now one page).
///
/// Routes: `RoutePath.kIptv`.
///
/// The data lives in `pure_live.db` (`StoreIptvLibrary`, M12.1) and changes
/// through `AppServices.iptvImporter`; the page shows it again after every
/// write, the background auto-sync included.
class IptvPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, this.onBack, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  /// Returns to the overview when an embedded settings page becomes narrow.
  final VoidCallback? onBack;

  @override
  ConsumerState<IptvPage> createState() => _IptvPageState();
}

/// `meta` key set once the default guide was imported on a first visit
/// (3.x imported it on every visit without a guide).
const String defaultGuideMetaKey = 'iptv.defaultGuideLoaded';

class _IptvPageState extends ConsumerState<IptvPage> {
  /// Items with an operation running (`p:<id>`, `g:<id>`).
  final _busy = <String>{};
  bool _importing = false;
  ({int done, int total})? _syncAll;
  bool _defaultPlaylistChecked = false;
  bool _defaultPlaylistLoading = false;
  bool _defaultPlaylistRestoreRequested = false;
  IptvImportResult? _defaultPlaylistFailure;
  bool _defaultGuideChecked = false;
  bool _defaultGuideLoading = false;
  bool _defaultGuideFailed = false;

  IptvImporter? get _importer => ref.read(iptvImporterProvider);

  LiveStore get _store => ref.read(storeProvider);

  bool _blocked(String key) => _syncAll != null || _busy.contains(key);

  void _toast(String? message) {
    if (message != null && message.isNotEmpty) AppNavigator.toast(message);
  }

  // Guide selection -----------------------------------------------------------

  /// Keeps the selected guide valid: the first guide when none (or a
  /// deleted one) is selected (3.x selected the first only when none was),
  /// none when there are no guides; the stored name follows renames.
  void _checkSelection(IptvOverview overview) {
    final settings = _store.settings;
    final id = settings.get(Settings.selectedSourceId);
    final EpgSource? target;
    if (overview.guides.isEmpty) {
      target = null;
    } else {
      target = overview.guide(id) ?? overview.guides.first.source;
    }
    final name = target?.name ?? '';
    if (target?.id == id && name == settings.get(Settings.selectedSourceName)) return;
    if (target == null && id.isEmpty) return;
    unawaited(_select(target, announce: false));
  }

  Future<void> _select(EpgSource? source, {bool announce = true}) async {
    try {
      await _store.settings.setAll({
        Settings.selectedSourceId: source?.id ?? '',
        Settings.selectedSourceName: source?.name ?? '',
      });
      if (announce && mounted && source != null) _toast(i18n('iptv_guide_switched', args: {'name': guideName(source)}));
    } on Object catch (error, stack) {
      log('Selecting the guide failed', name: 'IptvPage', error: error, stackTrace: stack);
      if (announce && mounted) _toast(i18n('iptv_save_failed'));
    }
  }

  /// "选择节目单" (3.x `_showEpgSourceSelector`, docs/A-界面设计/A13-网络电视和多画面界面/A13.1-网络电视管理 c13):
  /// a 20 px title, one radio row per guide, the current one in the primary
  /// colour; a tap switches and closes; only "取消" at the bottom.
  Future<void> _chooseGuide(IptvOverview overview) async {
    final current = _store.settings.get(Settings.selectedSourceId);
    final chosen = await showAppOptionDialog<EpgSource>(
      context: context,
      title: i18n('select_epg_source'),
      message: overview.guides.isEmpty ? i18n('no_epg_sources_found') : null,
      selected: overview.guides.map((info) => info.source).where((source) => source.id == current).firstOrNull,
      options: [
        for (final info in overview.guides)
          AppDialogOption(
            key: ValueKey('iptv-choose-${info.source.id}'),
            value: info.source,
            label: guideName(info.source),
            description: info.source.source,
            descriptionMaxLines: 1,
          ),
      ],
    );
    if (chosen != null && mounted && chosen.id != current) await _select(chosen);
  }

  // Default playlist and guide -----------------------------------------------

  /// Settings and recommendations share the same first-use download. An
  /// existing row (including one restored from a backup) is left untouched;
  /// the deletion preference is the only opt-out, not an empty library.
  Future<void> _maybeLoadDefaultPlaylist(IptvOverview overview) async {
    if (_defaultPlaylistChecked) return;
    _defaultPlaylistChecked = true;
    if (overview.playlists.any((info) => info.playlist.isHot)) return;
    await _loadDefaultPlaylist();
  }

  Future<void> _loadDefaultPlaylist() => _runDefaultPlaylistLoad(_importer, _store.settings);

  Future<void> _runDefaultPlaylistLoad(IptvImporter? importer, SettingsStore settings) async {
    if (importer == null || _defaultPlaylistLoading || settings.get(Settings.iptvHotRemoved)) return;
    _defaultPlaylistLoading = true;
    _defaultPlaylistFailure = null;
    if (mounted) setState(() {});
    bool hotRemoved() => settings.get(Settings.iptvHotRemoved);
    var result = await importer.loadHotPlaylist(hotRemoved: hotRemoved, onlyIfMissing: true);
    final restoreRequested = _defaultPlaylistRestoreRequested;
    _defaultPlaylistRestoreRequested = false;
    if (restoreRequested &&
        !hotRemoved() &&
        (result.status == IptvImportStatus.stale || result.status == IptvImportStatus.cancelled)) {
      // Restore may have joined a download whose snapshot predates the
      // deletion. Once it settles, start one fresh guarded download, but
      // never overwrite a backup restored in the meantime.
      try {
        if (await importer.library.playlist(IptvPlaylist.hotId) == null && !hotRemoved()) {
          result = await importer.loadHotPlaylist(hotRemoved: hotRemoved, onlyIfMissing: true);
        }
      } on Object catch (error) {
        result = IptvImportResult(IptvImportStatus.failed, error: error);
      }
    }
    if (!mounted) return;
    setState(() {
      _defaultPlaylistLoading = false;
      _defaultPlaylistFailure = switch (result.status) {
        IptvImportStatus.imported || IptvImportStatus.cancelled || IptvImportStatus.stale => null,
        _ => settings.get(Settings.iptvHotRemoved) ? null : result,
      };
    });
  }

  /// On the first visit without any guide, imports the default guide (3.x
  /// did it on every visit without one, so a deleted default came back).
  Future<void> _maybeLoadDefaultGuide(IptvOverview overview) async {
    if (_defaultGuideChecked) return;
    _defaultGuideChecked = true;
    if (overview.guides.isNotEmpty) return;
    try {
      if (await _store.meta.get(defaultGuideMetaKey) != null) return;
    } on Object {
      return;
    }
    if (mounted) await _loadDefaultGuide();
  }

  Future<void> _loadDefaultGuide() async {
    final importer = _importer;
    if (importer == null || _defaultGuideLoading) return;
    setState(() {
      _defaultGuideLoading = true;
      _defaultGuideFailed = false;
    });
    final result = await importer.importGuideFromUrl(
      IptvImporter.defaultGuideUrl,
      name: IptvImporter.hotName,
      force: true,
    );
    if (result.isImported) {
      try {
        await _store.meta.set(defaultGuideMetaKey, '1');
      } on Object catch (error, stack) {
        log('Saving the default guide flag failed', name: 'IptvPage', error: error, stackTrace: stack);
      }
    } else {
      log('Default guide: $result', name: 'IptvPage');
    }
    if (!mounted) return;
    setState(() {
      _defaultGuideLoading = false;
      _defaultGuideFailed = !result.isImported;
    });
    _toast(result.isImported ? i18n('iptv_default_guide_done') : null);
  }

  // Imports -------------------------------------------------------------------

  Future<IptvImportResult> _guarded(Future<IptvImportResult> Function() run) async {
    setState(() => _importing = true);
    try {
      return await run();
    } on Object catch (error, stack) {
      log('IPTV import failed', name: 'IptvPage', error: error, stackTrace: stack);
      return IptvImportResult(IptvImportStatus.failed, error: error);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  IptvReplaceConfirm _confirmFor(IptvImportKind kind) =>
      (name) async => mounted && await confirmReplace(context, name, kind);

  Future<void> _import(IptvImportKind kind) async {
    final importer = _importer;
    if (importer == null) return;
    if (_importing || _defaultGuideLoading) {
      _toast(i18n('iptv_import_in_progress'));
      return;
    }
    final origin = await chooseImportOrigin(context, kind);
    if (origin == null || !mounted) return;
    final playlist = kind == IptvImportKind.playlist;
    switch (origin) {
      case IptvImportOrigin.defaultGuide:
        await _loadDefaultGuide();
      case IptvImportOrigin.file:
        final file = await ref.read(iptvFilePickerProvider)(context, kind);
        if (file == null || !mounted) return;
        final result = await _guarded(
          () => playlist
              ? importer.importPlaylistFile(file, confirmReplace: _confirmFor(kind))
              : importer.importGuideFile(file, confirmReplace: _confirmFor(kind)),
        );
        await _announce(kind, result);
      case IptvImportOrigin.network:
      case IptvImportOrigin.text:
        // The dialog shows failures itself; once it is closed (the import
        // keeps running), the result comes as a toast.
        var open = true;
        Future<IptvImportResult> run(String address, String name) async {
          final result = await _guarded(
            () => origin == IptvImportOrigin.text
                ? importer.importPlaylistText(address, name, confirmReplace: _confirmFor(kind))
                : playlist
                ? importer.importPlaylistFromUrl(address, name: name, confirmReplace: _confirmFor(kind))
                : importer.importGuideFromUrl(address, name: name, confirmReplace: _confirmFor(kind)),
          );
          if (!open) await _announce(kind, result);
          return result;
        }

        final result = await showAppDialog<IptvImportResult>(
          context: context,
          dismissible: false,
          builder: (_) => origin == IptvImportOrigin.text
              ? IptvTextImportDialog(run: run)
              : IptvNetworkImportDialog(kind: kind, run: run),
        );
        open = false;
        if (result != null) await _announce(kind, result);
    }
  }

  Future<void> _announce(IptvImportKind kind, IptvImportResult result) async {
    final guide = kind == IptvImportKind.guide;
    if (!result.isImported) {
      _toast(failureText(result, guide: guide));
      return;
    }
    var name = '';
    try {
      final library = _importer!.library;
      final id = result.id ?? '';
      name = guide ? guideName((await library.guideSource(id))!) : playlistName((await library.playlist(id))!);
    } on Object {
      // The name is only for the message.
    }
    if (guide) {
      _toast(i18n('iptv_guide_imported', args: {'name': name}));
    } else if (result.issues.isEmpty) {
      _toast(i18n('iptv_playlist_imported', args: {'name': name}));
    } else {
      _toast(i18n('iptv_playlist_imported_skipped', args: {'name': name, 'count': '${result.issues.length}'}));
    }
  }

  // Item operations -----------------------------------------------------------

  Future<void> _runItem(String key, Future<void> Function() action) async {
    if (_blocked(key)) return;
    setState(() => _busy.add(key));
    try {
      await action();
    } on Object catch (error, stack) {
      log('IPTV operation failed', name: 'IptvPage', error: error, stackTrace: stack);
      if (mounted) _toast(i18n('iptv_save_failed'));
    } finally {
      _busy.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<IptvImportResult> _syncOne(Object item) {
    final importer = _importer!;
    return item is IptvPlaylist ? importer.syncPlaylist(item) : importer.syncGuide(item as EpgSource);
  }

  Future<void> _sync(Object item, String key, String name) => _runItem(key, () async {
    final result = await _syncOne(item);
    if (!mounted) return;
    _toast(
      result.isImported
          ? i18n('iptv_synced', args: {'name': name})
          : i18n(
              'iptv_sync_failed_named',
              args: {
                'name': name,
                'reason': failureText(result, guide: item is EpgSource) ?? '',
              },
            ),
    );
  });

  /// Syncs every network playlist and guide (3.x synced only those with
  /// automatic sync on).
  Future<void> _syncEverything(IptvOverview overview) async {
    if (_syncAll != null || _importer == null) return;
    final items = <Object>[
      for (final info in overview.playlists)
        if (info.playlist.isRemote) info.playlist,
      for (final info in overview.guides)
        if (info.source.isRemote) info.source,
    ];
    if (items.isEmpty) {
      _toast(i18n('iptv_sync_all_none'));
      return;
    }
    if (_busy.isNotEmpty || _importing) {
      _toast(i18n('iptv_import_in_progress'));
      return;
    }
    setState(() => _syncAll = (done: 0, total: items.length));
    var failed = 0;
    for (final (index, item) in items.indexed) {
      if (!mounted) return;
      try {
        if (!(await _syncOne(item)).isImported) failed++;
      } on Object catch (error, stack) {
        log('IPTV sync failed', name: 'IptvPage', error: error, stackTrace: stack);
        failed++;
      }
      if (mounted) setState(() => _syncAll = (done: index + 1, total: items.length));
    }
    if (!mounted) return;
    setState(() => _syncAll = null);
    _toast(
      failed == 0
          ? i18n('iptv_sync_all_done', args: {'count': '${items.length}'})
          : i18n('iptv_sync_all_partial', args: {'failed': '$failed', 'count': '${items.length}'}),
    );
  }

  Future<void> _setAutoUpdate(Object item, String key, bool value) => _runItem(key, () async {
    final library = _importer!.library;
    if (item is IptvPlaylist) {
      await library.updatePlaylist(item.copyWith(autoUpdate: value));
    } else if (item is EpgSource) {
      await library.updateGuideSource(item.copyWith(autoUpdate: value));
    }
    if (mounted) _toast(i18n(value ? 'iptv_auto_sync_on' : 'iptv_auto_sync_off'));
  });

  Future<void> _delete(Object item, String key, String name, int channels) async {
    if (_blocked(key)) {
      _toast(i18n('iptv_import_in_progress'));
      return;
    }
    final guide = item is EpgSource;
    final selected = guide && item.id == _store.settings.get(Settings.selectedSourceId);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: i18n(guide ? 'iptv_delete_guide' : 'iptv_delete_playlist'),
      message: [
        i18n(
          guide ? 'iptv_delete_guide_message' : 'iptv_delete_playlist_message',
          args: {'name': name, 'count': groupDigits(channels)},
        ),
        if (selected) i18n('iptv_delete_selected_guide'),
      ].join('\n'),
      confirmLabel: i18n('delete'),
      danger: true,
      confirmKey: const ValueKey('iptv-delete-confirm'),
    );
    if (!confirmed || !mounted) return;
    await _runItem(key, () async {
      final importer = _importer!;
      final deleted = item is IptvPlaylist
          ? await importer.deletePlaylist(item)
          : await importer.deleteGuide(item as EpgSource);
      if (!deleted) {
        if (mounted) _toast(i18n('iptv_changed_meanwhile'));
        return;
      }
      if (selected) {
        // 3.x kept the deleted guide selected (the page showed its name and
        // the live room looked it up in vain).
        await _select((await importer.library.guideSources()).firstOrNull, announce: false);
      }
      if (item is IptvPlaylist) await _playlistDeleted(item);
      if (mounted) _toast(i18n('iptv_deleted', args: {'name': name}));
    });
  }

  // The popular page's playlist (V02.9) ---------------------------------------

  /// A deleted hot list stays deleted (3.x imported it again on the next
  /// visit to 热门); a deleted playlist no longer shows in 热门.
  Future<void> _playlistDeleted(IptvPlaylist playlist) async {
    final settings = _store.settings;
    try {
      await settings.setAll({
        if (playlist.isHot) Settings.iptvHotRemoved: true,
        if (settings.get(Settings.iptvPopularPlaylist) == playlist.id) Settings.iptvPopularPlaylist: '',
      });
    } on Object catch (error, stack) {
      log('Saving the deleted playlist failed', name: 'IptvPage', error: error, stackTrace: stack);
    }
  }

  /// The playlists 热门 → 网络 can show: the hot list unless deleted, then
  /// the imported ones in the page's order.
  List<(String, String)> _popularOptions(IptvOverview overview) => [
    if (!_store.settings.get(Settings.iptvHotRemoved)) (IptvPlaylist.hotId, i18n('iptv_hot_playlist')),
    for (final info in overview.playlists)
      if (!info.playlist.isHot) (info.playlist.id, playlistName(info.playlist)),
  ];

  /// The id of the playlist 热门 → 网络 shows.
  String? _popularShown(IptvOverview overview) => shownIptvPlaylist(
    [for (final info in overview.playlists) info.playlist],
    wanted: watchSetting(ref, Settings.iptvPopularPlaylist),
    hotRemoved: watchSetting(ref, Settings.iptvHotRemoved),
  );

  /// "热门里显示": one radio row per playlist, like "选择节目单".
  Future<void> _choosePopular(IptvOverview overview) async {
    final current = _popularShown(overview);
    final options = _popularOptions(overview);
    final chosen = await showAppOptionDialog<String>(
      context: context,
      title: i18n('iptv_popular_playlist'),
      message: i18n('iptv_popular_playlist_desc'),
      selected: current,
      options: [
        for (final (id, name) in options) AppDialogOption(key: ValueKey('iptv-popular-$id'), value: id, label: name),
      ],
    );
    if (chosen == null || !mounted || chosen == current) return;
    final name = options.firstWhere((option) => option.$1 == chosen).$2;
    await _set(
      Settings.iptvPopularPlaylist,
      chosen,
      message: i18n('iptv_popular_playlist_switched', args: {'name': name}),
    );
  }

  /// Brings the deleted hot list back and downloads it.
  Future<void> _restoreHot() async {
    final importer = _importer;
    final settings = _store.settings;
    if (importer == null) return;
    await _set(Settings.iptvHotRemoved, false, message: i18n('iptv_hot_restored'));
    if (settings.get(Settings.iptvHotRemoved)) return;
    _defaultPlaylistRestoreRequested = true;
    await _runDefaultPlaylistLoad(importer, settings);
  }

  Future<void> _cardAction(IptvCardAction action, String address) async {
    switch (action) {
      case IptvCardAction.open:
        final remote = isHttpUrl(address);
        final uri = remote ? Uri.tryParse(address) : null;
        var opened = false;
        try {
          opened = remote ? uri != null && await AppNavigator.openExternal(uri) : await AppNavigator.openFile(address);
        } on Object {
          opened = false;
        }
        if (!opened && mounted) _toast(i18n('iptv_open_failed'));
      case IptvCardAction.copy:
        await Clipboard.setData(ClipboardData(text: address));
        if (mounted) _toast(i18n('iptv_address_copied'));
    }
  }

  // Settings ------------------------------------------------------------------

  Future<void> _set<T extends Object>(Setting<T> setting, T value, {String? message}) async {
    try {
      await _store.settings.set(setting, value);
      if (mounted) _toast(message);
    } on Object catch (error, stack) {
      log('Saving ${setting.key} failed', name: 'IptvPage', error: error, stackTrace: stack);
      if (mounted) _toast(i18n('iptv_save_failed'));
    }
  }

  // Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(iptvOverviewProvider, (_, next) {
      final overview = next.value;
      if (overview == null) return;
      _checkSelection(overview);
      unawaited(_maybeLoadDefaultPlaylist(overview));
      unawaited(_maybeLoadDefaultGuide(overview));
    });
    final importer = ref.watch(iptvImporterProvider);
    final state = ref.watch(iptvOverviewProvider);
    final overview = state.value;
    final syncAll = _syncAll;
    final tv = SettingsRowStyle.tvOf(context);
    final embedded = SettingsPane.of(context);
    return Scaffold(
      appBar: settingsPageAppBar(
        context,
        onBack: widget.onBack,
        title: i18n('iptv_settings'),
        actions: [
          IconButton(
            key: const ValueKey('iptv-sync-all'),
            tooltip: i18n('iptv_sync_all'),
            onPressed: overview == null || syncAll != null ? null : () => unawaited(_syncEverything(overview)),
            icon: syncAll != null
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.syncAll),
          ),
        ],
      ),
      body: Column(
        children: [
          if (tv && overview != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ReadableContent(
                child: IptvStats(
                  playlists: groupDigits(overview.playlists.length),
                  channels: groupDigits(overview.channelCount),
                  guides: groupDigits(overview.guides.length),
                ),
              ),
            ),
          Expanded(
            child: importer == null
                ? AppStatusView(type: AppStatusType.error, title: i18n('iptv_unavailable'))
                : ListView(
                    key: const ValueKey('iptv-scroll'),
                    physics: const PureLiveScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(embedded ? 24 : 16, embedded ? 0 : 12, embedded ? 24 : 16, 28),
                    children: [
                      for (final child in [
                        ..._enableNotice(),
                        if (overview == null && state.hasError)
                          IptvStateCard(
                            key: const ValueKey('iptv-load-failed'),
                            icon: AppIcons.failed,
                            iconColor: Theme.of(context).colorScheme.error,
                            title: i18n('iptv_load_failed_title'),
                            text: i18n('iptv_initial_load_failed'),
                            actions: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(48, 40),
                                  alignment: AlignmentDirectional.centerStart,
                                ),
                                onPressed: () => ref.invalidate(iptvOverviewProvider),
                                icon: const Icon(AppIcons.retry, size: 18),
                                label: Text(i18n('retry')),
                              ),
                            ],
                          )
                        else if (overview == null)
                          const IptvSkeleton(),
                        if (overview != null) ...[
                          if (syncAll != null)
                            IptvSyncProgress(done: syncAll.done, total: syncAll.total)
                          else if (!tv)
                            IptvStats(
                              playlists: groupDigits(overview.playlists.length),
                              channels: groupDigits(overview.channelCount),
                              guides: groupDigits(overview.guides.length),
                            ),
                          const SizedBox(height: 20),
                          ..._playlistSection(overview),
                          const SizedBox(height: 8),
                          ..._guideSection(overview),
                          const SizedBox(height: 8),
                        ] else
                          const SizedBox(height: 20),
                        ..._settingsSection(),
                      ])
                        ReadableContent(
                          child: SizedBox(width: double.infinity, child: child),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// IPTV is not in the platform list (c16): a warning with "启用".
  List<Widget> _enableNotice() {
    final platforms = watchSetting(ref, Settings.hotAreasList);
    if (platforms.contains(SiteIds.iptv)) return const [];
    return [
      IptvStateCard(
        key: const ValueKey('iptv-not-enabled'),
        warning: true,
        icon: AppIcons.info,
        title: i18n('iptv_not_enabled'),
        text: i18n('iptv_not_enabled_desc'),
        actions: [
          TextButton(
            key: const ValueKey('iptv-enable'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 40),
              alignment: AlignmentDirectional.centerStart,
            ),
            onPressed: () =>
                unawaited(_set(Settings.hotAreasList, [...platforms, SiteIds.iptv], message: i18n('iptv_enabled'))),
            child: Text(i18n('iptv_enable')),
          ),
        ],
      ),
      const SizedBox(height: 4),
    ];
  }

  /// The trailing spinner of an import row while an import runs (3.x).
  Widget? get _importSpinner => _importing || _defaultGuideLoading
      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
      : null;

  List<Widget> _playlistSection(IptvOverview overview) {
    final now = ref.watch(iptvClockProvider)();
    final hotRemoved = watchSetting(ref, Settings.iptvHotRemoved);
    final defaultFailure = _defaultPlaylistFailure;
    final hasHot = overview.playlists.any((info) => info.playlist.isHot);
    final shown = _popularShown(overview);
    final popularOptions = _popularOptions(overview);
    return [
      SettingsGroup(
        title: i18n('iptv_group_playlists'),
        first: true,
        children: [
          SettingsLinkRow(
            key: const ValueKey('iptv-import-playlist'),
            icon: AppIcons.importPlaylist,
            title: i18n('import_playlist'),
            subtitle: i18n('iptv_import_playlist_desc'),
            valueWidget: _importSpinner,
            onTap: () => unawaited(_import(IptvImportKind.playlist)),
          ),
          if (popularOptions.length > 1)
            SettingsLinkRow(
              key: const ValueKey('iptv-popular-playlist'),
              icon: AppIcons.homePopular,
              title: i18n('iptv_popular_playlist'),
              subtitle: popularOptions.where((option) => option.$1 == shown).firstOrNull?.$2,
              choice: true,
              onTap: () => unawaited(_choosePopular(overview)),
            ),
          if (hotRemoved)
            SettingsLinkRow(
              key: const ValueKey('iptv-restore-hot'),
              icon: AppIcons.restoreDefault,
              title: i18n('iptv_restore_hot'),
              subtitle: i18n('iptv_restore_hot_desc'),
              onTap: () => unawaited(_restoreHot()),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (_defaultPlaylistLoading && !hotRemoved)
        IptvStateCard(
          key: const ValueKey('iptv-default-playlist-loading'),
          leading: const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          title: i18n('iptv_default_playlist_loading'),
          text: i18n('iptv_default_playlist_loading_desc'),
        )
      else if (defaultFailure != null && !hotRemoved && !hasHot)
        IptvStateCard(
          key: const ValueKey('iptv-default-playlist-failed'),
          icon: AppIcons.failed,
          iconColor: Theme.of(context).colorScheme.error,
          title: i18n('iptv_default_playlist_failed'),
          text: failureText(defaultFailure, guide: false),
          actions: [
            TextButton(
              key: const ValueKey('iptv-default-playlist-retry'),
              onPressed: () => unawaited(_loadDefaultPlaylist()),
              child: Text(i18n('retry')),
            ),
            TextButton(
              onPressed: () => unawaited(_import(IptvImportKind.playlist)),
              child: Text(i18n('import_playlist')),
            ),
          ],
        )
      else if (overview.playlists.isEmpty)
        IptvStateCard(
          key: const ValueKey('iptv-no-playlists'),
          centered: true,
          icon: AppIcons.playlistAdd,
          title: i18n('iptv_no_playlists'),
          text: i18n('iptv_no_playlists_desc'),
          actions: [
            FilledButton.tonal(
              onPressed: () => unawaited(_import(IptvImportKind.playlist)),
              child: Text(i18n('import_playlist')),
            ),
          ],
        ),
      for (final info in overview.playlists)
        _playlistCard(
          info.playlist,
          info.channels,
          now,
          inPopular: popularOptions.length > 1 && info.playlist.id == shown,
        ),
    ];
  }

  Widget _playlistCard(IptvPlaylist playlist, int channels, DateTime now, {required bool inPopular}) {
    final key = 'p:${playlist.id}';
    final name = playlistName(playlist);
    return IptvSourceCard(
      id: playlist.id,
      isGuide: false,
      name: name,
      address: playlist.source,
      badge: playlistBadge(playlist),
      isRemote: playlist.isRemote,
      details: sourceDetails(channels: channels, updated: playlist.lastRefresh, remote: playlist.isRemote, now: now),
      autoUpdate: playlist.autoUpdate,
      busy: _busy.contains(key),
      blocked: _blocked(key),
      inUse: inPopular,
      onSync: () => unawaited(_sync(playlist, key, name)),
      onDelete: () => unawaited(_delete(playlist, key, name, channels)),
      onAutoUpdate: (value) => unawaited(_setAutoUpdate(playlist, key, value)),
      onAction: (action) => unawaited(_cardAction(action, playlist.source)),
    );
  }

  List<Widget> _guideSection(IptvOverview overview) {
    final now = ref.watch(iptvClockProvider)();
    final selectedId = watchSetting(ref, Settings.selectedSourceId);
    final selected = overview.guide(selectedId);
    final scheme = Theme.of(context).colorScheme;
    return [
      SettingsGroup(
        title: i18n('iptv_group_guides'),
        children: [
          SettingsLinkRow(
            key: const ValueKey('iptv-import-guide'),
            icon: AppIcons.importGuide,
            title: i18n('import_epg_source'),
            subtitle: i18n('iptv_import_guide_desc'),
            valueWidget: _importSpinner,
            onTap: () => unawaited(_import(IptvImportKind.guide)),
          ),
          SettingsLinkRow(
            key: const ValueKey('iptv-active-guide'),
            icon: AppIcons.guide,
            title: i18n('active_epg_source'),
            subtitle: selected == null ? i18n('please_select_epg_source') : guideName(selected),
            subtitleColor: selected == null ? LiveSemanticColors.warning(scheme.brightness) : null,
            choice: true,
            onTap: () => unawaited(_chooseGuide(overview)),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_defaultGuideLoading)
        IptvStateCard(
          key: const ValueKey('iptv-default-guide-loading'),
          leading: const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          title: i18n('iptv_default_guide_loading'),
          text: i18n('iptv_default_guide_loading_desc'),
        )
      else if (_defaultGuideFailed)
        IptvStateCard(
          key: const ValueKey('iptv-default-guide-failed'),
          icon: AppIcons.failed,
          iconColor: scheme.error,
          title: i18n('iptv_default_guide_failed'),
          text: i18n('iptv_default_epg_unavailable'),
          actions: [
            TextButton(onPressed: () => unawaited(_loadDefaultGuide()), child: Text(i18n('retry'))),
            TextButton(
              onPressed: () => unawaited(_import(IptvImportKind.guide)),
              child: Text(i18n('import_epg_source')),
            ),
          ],
        )
      else if (overview.guides.isEmpty)
        IptvStateCard(
          key: const ValueKey('iptv-no-guides'),
          centered: true,
          icon: AppIcons.guide,
          title: i18n('iptv_no_guides'),
          text: i18n('iptv_no_guides_desc'),
          actions: [
            OutlinedButton(
              key: const ValueKey('iptv-empty-default-guide'),
              onPressed: () => unawaited(_loadDefaultGuide()),
              child: Text(i18n('iptv_default_guide')),
            ),
            FilledButton.tonal(
              onPressed: () => unawaited(_import(IptvImportKind.guide)),
              child: Text(i18n('import_epg_source')),
            ),
          ],
        ),
      for (final info in overview.guides) _guideCard(info.source, info.channels, now, selectedId),
    ];
  }

  Widget _guideCard(EpgSource source, int channels, DateTime now, String selectedId) {
    final key = 'g:${source.id}';
    final name = guideName(source);
    return IptvSourceCard(
      id: source.id,
      isGuide: true,
      name: name,
      address: source.source,
      badge: guideBadge(source),
      isRemote: source.isRemote,
      details: sourceDetails(channels: channels, updated: source.lastRefresh, remote: source.isRemote, now: now),
      autoUpdate: source.autoUpdate,
      busy: _busy.contains(key),
      blocked: _blocked(key),
      inUse: source.id == selectedId,
      onSync: () => unawaited(_sync(source, key, name)),
      onDelete: () => unawaited(_delete(source, key, name, channels)),
      onAutoUpdate: (value) => unawaited(_setAutoUpdate(source, key, value)),
      onAction: (action) => unawaited(_cardAction(action, source.source)),
    );
  }

  /// "同步和播放" (3.x "自动化周期同步设置": the switch, the interval while it
  /// is on, the request header).
  List<Widget> _settingsSection() {
    final autoSync = watchSetting(ref, Settings.isAutoSyncEnabled);
    final hours = IptvImporter.normalizeAutoSyncHours(watchSetting(ref, Settings.autoSyncHoursInterval));
    final userAgent = watchSetting(ref, Settings.customIptvUserAgent);
    return [
      SettingsGroup(
        title: i18n('iptv_section_settings'),
        children: [
          SettingsSwitchRow(
            icon: AppIcons.syncAll,
            title: i18n('auto_sync_title'),
            subtitle: i18n('iptv_auto_sync_desc'),
            subtitleMaxLines: null,
            value: autoSync,
            onChanged: (value) => unawaited(_set(Settings.isAutoSyncEnabled, value)),
          ),
          if (autoSync)
            SettingsLinkRow(
              icon: AppIcons.syncInterval,
              title: i18n('sync_interval_title'),
              value: i18n('sync_interval_hours', args: {'hour': '$hours'}),
              choice: true,
              onTap: () async {
                final chosen = await chooseSyncInterval(context, hours);
                if (chosen != null && chosen != hours) {
                  await _set(Settings.autoSyncHoursInterval, chosen, message: i18n('settings_saved'));
                }
              },
            ),
          SettingsLinkRow(
            icon: AppIcons.userAgent,
            title: i18n('custom_ua_title'),
            subtitle: userAgent.isEmpty ? i18n('iptv_ua_default') : userAgent,
            onTap: () async {
              final value = await editUserAgent(context, userAgent);
              if (value != null && value != userAgent) {
                await _set(Settings.customIptvUserAgent, value, message: i18n('iptv_ua_saved'));
              }
            },
          ),
        ],
      ),
    ];
  }
}
