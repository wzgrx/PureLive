import 'dart:async';

import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/web_dav/web_dav_auto_backup.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/backup/backup_files.dart';

/// The automatic WebDAV backup settings (J04.2, A12.7).
Future<void> showWebDavAutoBackupDialog(BuildContext context, {required LiveStore store}) => showAppDialog<void>(
  context: context,
  builder: (_) => _WebDavAutoBackupDialog(store: store),
);

const List<int> _hourOptions = [1, 6, 12, 24, 48, 72, 168];
const List<int> _keepOptions = [1, 3, 7, 15, 30];

class _WebDavAutoBackupDialog extends StatefulWidget {
  const new({required this.store});

  final LiveStore store;

  @override
  State<_WebDavAutoBackupDialog> createState() => _WebDavAutoBackupDialogState();
}

class _WebDavAutoBackupDialogState extends State<_WebDavAutoBackupDialog> {
  late bool _enabled;
  late int _hours;
  late String _scope;
  late int _keep;
  late bool _accounts;
  late final TextEditingController _folder;
  String? _folderError;
  bool? _hasServer;
  DateTime? _lastSuccess;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.store.settings;
    _enabled = settings.get(Settings.webdavAutoBackupEnabled);
    _hours = settings.get(Settings.webdavAutoBackupHours);
    _scope = settings.get(Settings.webdavAutoBackupScope);
    _keep = settings.get(Settings.webdavAutoBackupKeep);
    _accounts = settings.get(Settings.webdavAutoBackupIncludeAccounts);
    _folder = TextEditingController(text: settings.get(Settings.webdavAutoBackupFolder));
    unawaited(_load());
  }

  Future<void> _load() async {
    final current = await widget.store.webdav.current();
    final saved = await widget.store.meta.get(WebDavAutoBackupService.lastSuccessKey);
    if (!mounted) return;
    setState(() {
      _hasServer = current != null;
      _lastSuccess = saved == null ? null : DateTime.tryParse(saved)?.toLocal();
    });
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _chooseHours() async {
    final choices = {..._hourOptions, _hours}.toList()..sort();
    final hours = await showAppOptionDialog<int>(
      context: context,
      title: i18n('webdav_auto_backup_interval'),
      icon: AppIcons.syncInterval,
      selected: _hours,
      showCancel: false,
      options: [
        for (final hours in choices)
          AppDialogOption(
            key: ValueKey('webdav-auto-hours-$hours'),
            value: hours,
            label: i18n('webdav_auto_backup_hours', args: {'hour': '$hours'}),
          ),
      ],
    );
    if (hours != null && mounted) setState(() => _hours = hours);
  }

  Future<void> _chooseScope() async {
    final scope = await showAppOptionDialog<String>(
      context: context,
      title: i18n('webdav_auto_backup_scope'),
      icon: AppIcons.backupFiles,
      selected: _scope,
      showCancel: false,
      options: [
        AppDialogOption(
          key: const ValueKey('webdav-auto-scope-all'),
          value: 'all',
          label: i18n('webdav_auto_backup_scope_all'),
        ),
        AppDialogOption(
          key: const ValueKey('webdav-auto-scope-follows'),
          value: 'follows',
          label: i18n('webdav_auto_backup_scope_follows'),
        ),
      ],
    );
    if (scope == null || !mounted) return;
    setState(() {
      _scope = scope;
      if (scope == 'follows') _accounts = false;
    });
  }

  Future<void> _chooseKeep() async {
    final choices = {..._keepOptions, _keep}.toList()..sort();
    final keep = await showAppOptionDialog<int>(
      context: context,
      title: i18n('webdav_auto_backup_keep'),
      icon: AppIcons.backupFiles,
      selected: _keep,
      showCancel: false,
      options: [
        for (final keep in choices)
          AppDialogOption(
            key: ValueKey('webdav-auto-keep-$keep'),
            value: keep,
            label: i18n('webdav_auto_backup_keep_value', args: {'count': '$keep'}),
          ),
      ],
    );
    if (keep != null && mounted) setState(() => _keep = keep);
  }

  Future<void> _save() async {
    final folder = parseWebDavFolder(_folder.text);
    if (folder == null) {
      setState(() => _folderError = i18n('webdav_auto_backup_folder_invalid'));
      return;
    }
    setState(() {
      _folderError = null;
      _saving = true;
    });
    try {
      await widget.store.settings.setAll({
        Settings.webdavAutoBackupEnabled: _enabled,
        Settings.webdavAutoBackupHours: _hours,
        Settings.webdavAutoBackupScope: _scope,
        Settings.webdavAutoBackupFolder: folder.join('/'),
        Settings.webdavAutoBackupKeep: _keep,
        Settings.webdavAutoBackupIncludeAccounts: _accounts,
      });
    } on Object {
      if (mounted) setState(() => _saving = false);
      AppNavigator.toast(i18n('webdav_auto_backup_save_failed'));
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    AppNavigator.toast(i18n('webdav_auto_backup_saved'));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final last = _lastSuccess;
    return AppDialog(
      title: i18n('webdav_auto_backup'),
      icon: AppIcons.autoSync,
      wide: true,
      busy: _saving,
      onEnter: _saving ? null : _save,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
            children: [
              SettingsSwitchRow(
                key: const ValueKey('webdav-auto-enabled'),
                icon: AppIcons.autoSync,
                title: i18n('webdav_auto_backup_enabled'),
                subtitle: i18n('webdav_auto_backup_enabled_desc'),
                subtitleMaxLines: null,
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              SettingsLinkRow(
                key: const ValueKey('webdav-auto-hours'),
                icon: AppIcons.syncInterval,
                title: i18n('webdav_auto_backup_interval'),
                value: i18n('webdav_auto_backup_hours', args: {'hour': '$_hours'}),
                choice: true,
                onTap: () => unawaited(_chooseHours()),
              ),
              SettingsLinkRow(
                key: const ValueKey('webdav-auto-scope'),
                icon: AppIcons.backupFiles,
                title: i18n('webdav_auto_backup_scope'),
                value: i18n(_scope == 'follows' ? 'webdav_auto_backup_scope_follows' : 'webdav_auto_backup_scope_all'),
                choice: true,
                onTap: () => unawaited(_chooseScope()),
              ),
              SettingsLinkRow(
                key: const ValueKey('webdav-auto-keep'),
                icon: AppIcons.backupFiles,
                title: i18n('webdav_auto_backup_keep'),
                value: i18n('webdav_auto_backup_keep_value', args: {'count': '$_keep'}),
                choice: true,
                onTap: () => unawaited(_chooseKeep()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsGroup(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TextField(
                  key: const ValueKey('webdav-auto-folder'),
                  controller: _folder,
                  autocorrect: false,
                  decoration:
                      dialogFieldDecoration(
                        context,
                        label: i18n('webdav_auto_backup_folder'),
                        helper: i18n('webdav_auto_backup_folder_desc'),
                      ).copyWith(
                        prefixIcon: const Icon(AppIcons.webDavFolder, size: 20),
                        errorText: _folderError,
                        helperMaxLines: 3,
                      ),
                  onChanged: (_) {
                    if (_folderError != null) setState(() => _folderError = null);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsGroup(
            children: [
              SettingsSwitchRow(
                key: const ValueKey('webdav-auto-accounts'),
                icon: AppIcons.webDavServer,
                title: i18n('webdav_auto_backup_accounts'),
                subtitle: i18n('webdav_auto_backup_accounts_desc'),
                subtitleMaxLines: null,
                value: _accounts,
                enabled: _scope == 'all',
                disabledReason: _scope == 'all' ? null : i18n('webdav_auto_backup_accounts_follows'),
                onChanged: _scope == 'all' ? (value) => setState(() => _accounts = value) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            last == null
                ? i18n('webdav_auto_backup_never')
                : i18n('webdav_auto_backup_last', args: {'time': formatFileTime(last)}),
            key: const ValueKey('webdav-auto-last'),
            style: context.textStyles.t12.copyWith(color: colors.onSurfaceVariant),
          ),
          if (_hasServer == false) ...[
            const SizedBox(height: 8),
            Text(
              i18n('webdav_auto_backup_no_server'),
              key: const ValueKey('webdav-auto-no-server'),
              style: context.textStyles.t12.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
      actions: [
        DialogCancelButton(label: i18n('webdav_cancel')),
        DialogActionButton(
          key: const ValueKey('webdav-auto-save'),
          label: i18n('save'),
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
