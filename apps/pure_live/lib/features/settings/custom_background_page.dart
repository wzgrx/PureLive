import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/background/custom_background.dart';

/// Shared phone/desktop static background controls, under appearance.
class CustomBackgroundPage extends ConsumerStatefulWidget {
  /// Creates the settings page.
  const new({super.key});
  @override
  ConsumerState<CustomBackgroundPage> createState() => _CustomBackgroundPageState();
}

class _CustomBackgroundPageState extends ConsumerState<CustomBackgroundPage> {
  bool _busy = false;
  double? _mask;
  Future<void> _save(Map<String, Object?> patch) async {
    final settings = ref.read(storeProvider).settings;
    final config = CustomBackgroundConfig.fromJson({...settings.get(Settings.customBackground), ...patch});
    await settings.set(Settings.customBackground, config.toJson());
  }

  Future<void> _image() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final source = await ref.read(customBackgroundPickerProvider)();
      if (source == null || !mounted) return;
      final files = ref.read(customBackgroundFilesProvider);
      final settings = ref.read(storeProvider).settings;
      final name = await files.importImage(source);
      if (!mounted) {
        await files.keepOnly(CustomBackgroundConfig.fromJson(settings.get(Settings.customBackground)).file);
        return;
      }
      await _save({'kind': 'image', 'file': name});
      await files.keepOnly(name);
    } on Object {
      if (mounted) AppNavigator.toast(i18n('custom_background_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = CustomBackgroundConfig.fromJson(watchSetting(ref, Settings.customBackground));
    return Scaffold(
      key: const ValueKey('settings-custom-background'),
      appBar: settingsAppBar(context, title: i18n('custom_background_title'), embedded: SettingsPane.of(context)),
      body: SettingsPageBody(
        children: [
          SettingsNote(i18n('custom_background_desc')),
          SettingsRow(
            key: const ValueKey('background-pick-image'),
            title: i18n('custom_background_image'),
            subtitle: _busy ? i18n('loading') : i18n('custom_background_image_desc'),
            onTap: _busy ? null : () => unawaited(_image()),
          ),
          SettingsRow(
            key: const ValueKey('background-pick-color'),
            title: i18n('custom_background_color'),
            onTap: _busy
                ? null
                : () async {
                    final value = await showColorDialog(
                      context: context,
                      title: i18n('custom_background_color'),
                      current: Color(config.color),
                    );
                    if (value != null && mounted) await _save({'kind': 'color', 'color': value.toARGB32()});
                  },
          ),
          SettingsRow(
            key: const ValueKey('background-fit'),
            title: i18n('custom_background_fit'),
            subtitle: i18n('custom_background_${config.fit}'),
            onTap: () async {
              final value = await showChoiceDialog<String>(
                context: context,
                title: i18n('custom_background_fit'),
                options: [
                  for (final v in ['cover', 'contain', 'fill'])
                    (value: v, label: i18n('custom_background_$v'), description: null),
                ],
                selected: config.fit,
              );
              if (value != null && mounted) await _save({'fit': value});
            },
          ),
          SettingsSliderRow(
            key: const ValueKey('background-mask'),
            title: i18n('custom_background_mask'),
            value: _mask ?? config.mask,
            min: 0,
            max: 1,
            divisions: 20,
            label: '${((_mask ?? config.mask) * 100).round()}%',
            onChanged: (value) => setState(() => _mask = value),
            onChangeEnd: (value) => unawaited(
              _save({'mask': value}).then((_) {
                if (mounted) setState(() => _mask = null);
              }),
            ),
          ),
          SettingsRow(
            key: const ValueKey('background-clear'),
            title: i18n('custom_background_clear'),
            onTap: _busy
                ? null
                : () async {
                    await ref.read(storeProvider).settings.set(Settings.customBackground, <String, Object?>{});
                    await ref.read(customBackgroundFilesProvider).keepOnly('');
                  },
          ),
        ],
      ),
    );
  }
}
