import 'dart:developer';

import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/backup/backup_data.dart';

/// Asks which of the three kinds of file to write: app data only, app data
/// and settings, or both plus the accounts (J03.1, as Obtainium asks "apps"
/// or "apps and settings"). The answer is remembered in
/// [Settings.backupContents] and preselected next time, as Obtainium's
/// dropdown keeps its value; null when the user cancelled.
///
/// Both pages that write a backup ask this way (the backup page's "创建备份"
/// and the WebDAV page's "备份到当前目录"), so a device has one preference.
Future<BackupContents?> chooseBackupContents(
  BuildContext context,
  LiveStore store, {
  IconData icon = AppIcons.backupCreate,
}) async {
  final stored = storedBackupContents(store.settings.get(Settings.backupContents));
  final contents = await showAppOptionDialog<BackupContents>(
    context: context,
    title: i18n('backup_contents_title'),
    icon: icon,
    selected: stored,
    options: [
      for (final contents in BackupContents.values)
        AppDialogOption(
          key: ValueKey('backup-contents-${contents.name}'),
          value: contents,
          label: i18n(contents.labelKey),
          description: i18n(contents.descriptionKey),
          descriptionMaxLines: 3,
          leading: Icon(switch (contents) {
            BackupContents.data => AppIcons.backupFollows,
            BackupContents.settings => AppIcons.backupFile,
            BackupContents.sensitive => AppIcons.password,
          }, size: 20),
        ),
    ],
  );
  if (contents == null) return null;
  // A preference of this device: failing to store it must not stop the
  // backup.
  try {
    await store.settings.set(Settings.backupContents, contents.name);
  } on Object catch (error, stack) {
    log('Remembering the backup contents failed', name: 'Backup', error: error, stackTrace: stack);
  }
  return contents;
}
