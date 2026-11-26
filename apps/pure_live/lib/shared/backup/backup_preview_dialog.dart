import 'dart:developer';

import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/sync_parts.dart';

/// Where a backup file comes from, in words.
String backupSourceText(RestorePreview preview) {
  if (preview.followsOnlyFile) return i18n('backup_source_follows');
  return switch (preview.version) {
    null => i18n('backup_source_flat'),
    final version when version < 4 => i18n('backup_source_v3', args: {'version': '$version'}),
    _ => i18n('backup_source_v4'),
  };
}

/// One line of the preview: `关注的直播间：12 → 15（新增 4，移除 1）`.
String restorePartText(RestorePart part) {
  final counts = i18n('backup_preview_count', args: {'current': '${part.current}', 'incoming': '${part.incoming}'});
  final detail = part.unchanged
      ? i18n('backup_preview_same')
      : i18n('backup_preview_diff', args: {'added': '${part.added}', 'removed': '${part.removed}'});
  return i18n('backup_preview_part', args: {'part': i18n(part.kind.labelKey), 'counts': counts, 'detail': detail});
}

/// Shows what restoring [fileName] changes and asks to go on. The parts the
/// file holds go in a ticked box each (as Obtainium's import sheet ticks its
/// settings and apps), so a restore can leave a part out; [partsInFile] is
/// [syncPartsIn] of the file (empty for a flat 3.x file, which goes whole
/// and gets no boxes). Null when the user cancelled, otherwise the parts to
/// restore.
Future<Set<SyncPart>?> confirmRestore(
  BuildContext context, {
  required String fileName,
  required RestorePreview preview,
  required List<SyncPart> partsInFile,
}) async {
  final chosen = await showAppDialog<Set<SyncPart>>(
    context: context,
    builder: (dialogContext) {
      final styles = dialogContext.textStyles;
      final colors = Theme.of(dialogContext).colorScheme;
      final follows = preview.scope == BackupScope.follows;
      final ticked = {...partsInFile};
      Widget line(String text, {Color? color, IconData icon = AppIcons.bullet, double iconSize = 6}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              height: 20,
              child: Center(
                child: Icon(icon, size: iconSize, color: color ?? colors.primary),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: styles.t13.copyWith(color: color)),
            ),
          ],
        ),
      );
      // The text of a box: the preview's own line for a part that has one,
      // the count lines for settings and the accounts.
      String textOf(SyncPart part) => switch (part) {
        SyncPart.settings when preview.settingsInFile > 0 => i18n(
          'backup_preview_settings',
          args: {'count': '${preview.settingsInFile}', 'changed': '${preview.settingsChanged}'},
        ),
        // A data-only file keeps this section for the search words, the
        // IPTV playlists and the multi-view: name it plainly.
        SyncPart.settings => i18n('remote_sync_part_settings'),
        SyncPart.accounts => i18n('backup_preview_accounts', args: {'count': '${preview.accounts}'}),
        final part => switch (preview.parts.where((line) => line.kind == part.kind).firstOrNull) {
          final line? => restorePartText(line),
          null => i18n(part.labelKey),
        },
      };
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          final none = ticked.isEmpty;
          final all = ticked.length == partsInFile.length;
          Widget box(SyncPart part) => InkWell(
            key: ValueKey('backup-part-${part.name}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => ticked.contains(part) ? ticked.remove(part) : ticked.add(part)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    height: 32,
                    child: Center(
                      child: Checkbox(
                        value: ticked.contains(part),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (_) => setState(() => ticked.contains(part) ? ticked.remove(part) : ticked.add(part)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(textOf(part), style: styles.t13.copyWith(color: colors.primary)),
                    ),
                  ),
                ],
              ),
            ),
          );
          return AppDialog(
            title: i18n(follows ? 'recover_favorite_backup' : 'recover_backup'),
            onEnter: none ? null : () => Navigator.pop(dialogContext, {...ticked}),
            content: Column(
              key: const ValueKey('backup-preview'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(fileName, style: styles.t14SemiBold, maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(backupSourceText(preview), style: styles.t12Muted),
                if (preview.followsOnlyFile)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(i18n('backup_preview_follows_file'), style: styles.t13Primary),
                  ),
                const SizedBox(height: 12),
                Text(i18n('backup_preview_title'), style: styles.t13SemiBold),
                const SizedBox(height: 4),
                if (partsInFile.isEmpty && preview.settingsInFile > 0)
                  line(
                    i18n(
                      'backup_preview_settings',
                      args: {'count': '${preview.settingsInFile}', 'changed': '${preview.settingsChanged}'},
                    ),
                  )
                else if (partsInFile.isEmpty && preview.contents == BackupContents.data)
                  line(
                    i18n('backup_preview_no_settings'),
                    color: colors.onSurfaceVariant,
                    icon: AppIcons.selected,
                    iconSize: 14,
                  ),
                if (partsInFile.length > 1)
                  InkWell(
                    key: const ValueKey('backup-part-all'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() {
                      if (all) {
                        ticked.clear();
                      } else {
                        ticked.addAll(partsInFile);
                      }
                    }),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            height: 32,
                            child: Center(
                              child: Checkbox(
                                value: all ? true : (none ? false : null),
                                tristate: true,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (_) => setState(() {
                                  if (all) {
                                    ticked.clear();
                                  } else {
                                    ticked.addAll(partsInFile);
                                  }
                                }),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(i18n('remote_sync_parts_all'), style: styles.t14SemiBold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final part in partsInFile) box(part),
                for (final part in preview.parts)
                  if (SyncPart.of(part.kind) == null) line(restorePartText(part)),
                if (partsInFile.isNotEmpty && preview.accounts > 0 && !partsInFile.contains(SyncPart.accounts))
                  line(i18n('backup_preview_accounts', args: {'count': '${preview.accounts}'})),
                if (preview.kept.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  line(
                    i18n(
                      'backup_preview_kept',
                      args: {
                        'parts': [for (final kind in preview.kept) i18n(kind.labelKey)].join('、'),
                      },
                    ),
                    color: colors.onSurfaceVariant,
                    icon: AppIcons.selected,
                    iconSize: 14,
                  ),
                ],
                if (follows)
                  line(
                    i18n('webdav_favorites_unchanged_hint'),
                    color: colors.onSurfaceVariant,
                    icon: AppIcons.selected,
                    iconSize: 14,
                  ),
                if (preview.skipped > 0)
                  line(
                    i18n('backup_preview_skipped', args: {'count': '${preview.skipped}'}),
                    color: colors.error,
                    icon: AppIcons.warning,
                    iconSize: 14,
                  ),
                if (!preview.changesSomething)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(i18n('backup_preview_nothing'), style: styles.t13Muted),
                  ),
                const SizedBox(height: 8),
                Text(i18n('backup_preview_warning'), style: styles.t12Muted),
              ],
            ),
            actions: [
              DialogCancelButton(onPressed: () => Navigator.pop(dialogContext)),
              DialogActionButton(
                key: const ValueKey('backup-restore-confirm'),
                label: i18n('backup_restore_now'),
                onPressed: none ? null : () => Navigator.pop(dialogContext, {...ticked}),
              ),
            ],
          );
        },
      );
    },
  );
  return chosen;
}

/// The restore flow of both pages: [read] the file, show what it changes,
/// restore after the user agrees, say how it went. [readFailedKey] is the
/// message when the file cannot be read (a local file, a download). True
/// when something was restored.
Future<bool> restoreWithPreview(
  BuildContext context, {
  required BackupService service,
  required LiveStore store,
  required String fileName,
  required BackupScope scope,
  required Future<Map<String, Object?>> Function() read,
  required String readFailedKey,
}) async {
  final Map<String, Object?> json;
  final RestorePreview preview;
  try {
    json = await read();
  } on FormatException {
    AppNavigator.toast(i18n('backup_not_backup'));
    return false;
  } on Object catch (error, stack) {
    log('Reading the backup failed', name: 'Backup', error: error, stackTrace: stack);
    AppNavigator.toast(i18n(readFailedKey));
    return false;
  }
  try {
    BackupService.checkVersion(json);
  } on FormatException {
    AppNavigator.toast(i18n('backup_newer_version', args: {'version': '${json['backupVersion']}'}));
    return false;
  }
  try {
    preview = await previewRestore(store, json, scope);
  } on FormatException {
    AppNavigator.toast(i18n(scope == BackupScope.follows ? 'backup_no_follows' : 'backup_not_backup'));
    return false;
  }
  if (!context.mounted) return false;
  final parts = await confirmRestore(
    context,
    fileName: fileName,
    preview: preview,
    partsInFile: syncPartsIn(json),
  );
  if (parts == null) return false;
  final follows = preview.scope == BackupScope.follows;
  try {
    await restoreBackup(service, store, onlySyncParts(json, parts), preview.scope);
    // BackupService signals a restore already running with a StateError.
    // ignore: avoid_catching_errors
  } on StateError {
    AppNavigator.toast(i18n('backup_restore_busy'));
    return false;
  } on Object catch (error, stack) {
    log('Restoring the backup failed', name: 'Backup', error: error, stackTrace: stack);
    AppNavigator.toast(i18n(follows ? 'recover_favorite_backup_failed' : 'recover_backup_failed'));
    return false;
  }
  AppNavigator.toast(i18n(follows ? 'recover_favorite_backup_success' : 'recover_backup_success'));
  return true;
}
