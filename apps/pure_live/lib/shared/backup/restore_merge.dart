import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/features/multiview/logic/multiview_session.dart';
import 'package:pure_live/features/search/search_history.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_iptv.dart';

/// The 合并 restore: the file's lists join the device's (a union — nothing
/// that is here goes), and the single values it carries (a setting, the
/// multi-view arrangement, the sign-ins) overwrite.
///
/// 3.x and [BackupService.restoreAll] replace every list the file has, which
/// is why 72 follows and a 61-room file used to end at 61; merging is what
/// Obtainium's import does with its lists, and what the preview promises
/// (只新增, no 移除).
Future<void> mergeBackup(
  BackupService service,
  LiveStore store,
  Map<String, Object?> json,
  BackupScope scope, {
  IptvLibrary? iptv,
}) => service.runExclusive(() async {
  final snapshot = LegacySnapshot.fromBackup(json);
  if (snapshot.follows case final rooms?) await _unionFollows(store, rooms);
  if (snapshot.followAreas case final areas?) await _unionAreas(store, areas);
  if (scope == BackupScope.follows) return;
  await store.settings.setAll(snapshot.settings);
  if (snapshot.history case final rooms?) await _unionHistory(store, rooms);
  if (snapshot.tags != null || snapshot.roomTags != null) {
    await _unionTags(store, snapshot.tags ?? const [], snapshot.roomTags ?? const {});
  }
  if (snapshot.blockedKeywords case final values?) await _unionWords(store, BlockKind.keyword, values);
  if (snapshot.blockedUsers case final values?) await _unionWords(store, BlockKind.user, values);
  if (snapshot.webdav case final configs?) await _unionWebDav(store, configs);
  if (snapshot.secrets case final secrets?) await store.secrets.writeAll(secrets);
  for (final MapEntry(key: site, value: accounts) in (snapshot.savedAccounts ?? const {}).entries) {
    await store.accounts.merge(site, accounts);
  }
  if (LocalEventStore.inBackup(json) case final events?) await _unionLocalEvents(store, events);
  if (searchWordsIn(json) case final words?) await _unionSearchWords(store, words);
  if (iptvBackupIn(json) case final library?) await _unionIptv(iptv ?? StoreIptvLibrary(store), library);
  // A single value, like a setting: the file's arrangement wins.
  if (multiviewSessionIn(json) case final session?) await writeMultiviewSession(store.meta, session);
});



Future<void> _unionFollows(LiveStore store, List<LiveRoom> incoming) async {
  final current = await store.follows.all();
  final known = {for (final room in current) room.identityKey};
  final novel = [for (final room in incoming) if (!known.contains(room.identityKey)) room];
  if (novel.isNotEmpty) await store.follows.replaceAll([...current, ...novel]);
}

Future<void> _unionAreas(LiveStore store, List<LiveArea> incoming) async {
  final current = await store.followAreas.all();
  final known = {for (final area in current) ?area.identityKey};
  final novel = [for (final area in incoming) if (!known.contains(area.identityKey)) area];
  if (novel.isNotEmpty) await store.followAreas.replaceAll([...current, ...novel]);
}

/// The rooms the device watched stay where they are; the file's new ones
/// join at the end (the store trims to the history limit).
Future<void> _unionHistory(LiveStore store, List<LiveRoom> incoming) async {
  final current = await store.history.all();
  final known = {for (final room in current) room.identityKey};
  final novel = [for (final room in incoming) if (!known.contains(room.identityKey)) room];
  if (novel.isNotEmpty) await store.history.replaceAll([...current, ...novel]);
}

/// Groups join by name (the case-insensitive one the store keeps); a name
/// on both sides keeps the device's group and takes the file's rooms.
Future<void> _unionTags(LiveStore store, List<StoreTag> incoming, Map<String, List<String>> roomTags) async {
  final tags = await store.tags.all();
  final assignments = {for (final MapEntry(:key, :value) in (await store.tags.assignments()).entries) key: [...value]};
  final byName = {for (final tag in tags) tag.name.toLowerCase(): tag};
  final ids = <String, String>{};
  for (final tag in incoming) {
    final kept = byName[tag.name.toLowerCase()];
    if (kept != null) {
      ids[tag.id] = kept.id;
    } else {
      byName[tag.name.toLowerCase()] = tag;
      ids[tag.id] = tag.id;
      tags.add(tag);
    }
  }
  for (final MapEntry(key: room, value: fileIds) in roomTags.entries) {
    final roomIds = assignments.putIfAbsent(room, () => []);
    for (final id in fileIds) {
      final mapped = ids[id] ?? id;
      if (!roomIds.contains(mapped)) roomIds.add(mapped);
    }
  }
  await store.tags.replaceAll(tags, assignments);
}

Future<void> _unionWords(LiveStore store, BlockKind kind, List<String> incoming) async {
  final current = await store.blockLists.list(kind);
  final known = {for (final word in current) word.toLowerCase()};
  final novel = [for (final word in incoming) if (known.add(word.toLowerCase())) word];
  if (novel.isNotEmpty) await store.blockLists.replaceAll(kind, [...current, ...novel]);
}

/// Servers join by name; the current one stays.
Future<void> _unionWebDav(LiveStore store, List<WebDavConfig> incoming) async {
  final current = await store.webdav.all();
  final known = {for (final config in current) config.name};
  final novel = [for (final config in incoming) if (!known.contains(config.name)) config];
  if (novel.isEmpty) return;
  await store.webdav.replaceAll([...current, ...novel], current: await store.webdav.current());
}

Future<void> _unionLocalEvents(LiveStore store, List<LocalEvent> incoming) async {
  String key(LocalEvent event) => '${event.kind.name}|${event.at.millisecondsSinceEpoch}|${event.text}|${event.giftId}';
  final current = await store.localEvents.all();
  final known = {for (final event in current) key(event)};
  final novel = [for (final event in incoming) if (known.add(key(event))) event];
  if (novel.isNotEmpty) await store.localEvents.replaceAll([...current, ...novel]);
}

Future<void> _unionSearchWords(LiveStore store, List<String> incoming) async {
  final current = await storedSearchWords(store);
  final known = {for (final word in current) word.toLowerCase()};
  final merged = [...current, for (final word in incoming) if (known.add(word.toLowerCase())) word];
  if (merged.length == current.length) return;
  await store.meta.set(SearchHistory.key, jsonEncode(merged));
}

/// Playlists and guide sources join by id: nothing saved is deleted, the
/// file's new entries are added as they are.
Future<void> _unionIptv(IptvLibrary library, IptvBackup backup) async {
  final playlists = {for (final playlist in await library.playlists()) playlist.id};
  for (final (:playlist, :channels, :mappings) in backup.playlists) {
    if (playlists.contains(playlist.id)) continue;
    final kept = {for (final channel in channels) channel.id};
    await library.savePlaylist(
      playlist,
      channels,
      expected: null,
      mappings: (
        upserts: [
          for (final mapping in mappings)
            if (kept.contains(mapping.channelId)) mapping,
        ],
        deletes: const [],
      ),
    );
  }
  final guides = await library.guideSources();
  for (final guide in backup.guides) {
    final known = guides.any((saved) => saved.id == guide.id || saved.source.trim() == guide.source.trim());
    if (!known) await library.saveGuide(guide, const [], const [], expected: null);
  }
}
