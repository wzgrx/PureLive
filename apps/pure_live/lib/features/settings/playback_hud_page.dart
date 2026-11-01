import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/danmaku_color_palette.dart';
import 'package:pure_live/shared/rooms/playback_hud_config.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';

/// Shared settings for the information layer in all playback layouts.
class PlaybackHudPage extends ConsumerStatefulWidget {
  /// Creates the settings page, also usable in the desktop settings pane.
  const new({super.key});

  @override
  ConsumerState<PlaybackHudPage> createState() => _PlaybackHudPageState();
}

class _PlaybackHudPageState extends ConsumerState<PlaybackHudPage> {
  double? _size;
  String _editing = 'clock';

  Future<void> _appearance(PlaybackHudConfig config, Map<String, Object?> patch) async {
    if (!config.separate) {
      await _save(patch);
      return;
    }
    final style = config.styleFor(_editing);
    await _save({
      '${_editing}Style': PlaybackHudStyle.fromJson({...style.toJson(), ...patch}).toJson(),
    });
  }

  Future<void> _save(Map<String, Object?> patch) async {
    final settings = ref.read(storeProvider).settings;
    final next = PlaybackHudConfig.fromJson({...settings.get(Settings.playbackHud), ...patch});
    await settings.set(Settings.playbackHud, next.toJson());
  }

  Future<void> _pick(BuildContext context, String field, String title, Iterable<String> values, String selected) async {
    final value = await showChoiceDialog<String>(
      context: context,
      title: i18n(title),
      options: [for (final value in values) (value: value, label: i18n('playback_hud_$value'), description: null)],
      selected: selected,
    );
    if (value != null && mounted) {
      final config = PlaybackHudConfig.fromJson(ref.read(storeProvider).settings.get(Settings.playbackHud));
      if (field == 'mode') {
        await _save({field: value});
      } else if (field == 'edit') {
        setState(() {
          _editing = value;
          _size = null;
        });
      } else {
        await _appearance(config, {field: value});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = PlaybackHudConfig.fromJson(watchSetting(ref, Settings.playbackHud));
    final appearance = config.styleFor(_editing);
    final page = Builder(
      builder: (context) => Scaffold(
        key: const ValueKey('settings-playback-hud'),
        appBar: settingsAppBar(context, title: i18n('playback_hud_title'), embedded: SettingsPane.of(context)),
        body: SettingsPageBody(
          children: [
            SettingsNote(i18n('playback_hud_desc')),
            SettingsRow(
              key: const ValueKey('playback-hud-mode'),
              title: i18n('playback_hud_mode'),
              subtitle: i18n('playback_hud_${config.mode}'),
              onTap: () => unawaited(_pick(context, 'mode', 'playback_hud_mode', PlaybackHudConfig.modes, config.mode)),
            ),
            SettingsSwitchRow(
              key: const ValueKey('playback-hud-clock-toggle'),
              title: i18n('playback_hud_clock'),
              value: config.clock,
              onChanged: (value) => unawaited(_save({'clock': value})),
            ),
            SettingsSwitchRow(
              key: const ValueKey('playback-hud-speed-toggle'),
              title: i18n('playback_hud_speed'),
              subtitle: i18n('playback_hud_speed_desc'),
              value: config.speed,
              onChanged: (value) => unawaited(_save({'speed': value})),
            ),
            SettingsSwitchRow(
              key: const ValueKey('playback-hud-separate'),
              title: i18n('playback_hud_separate'),
              subtitle: i18n('playback_hud_separate_desc'),
              value: config.separate,
              onChanged: (value) => unawaited(_save({'separate': value})),
            ),
            if (config.separate)
              SettingsRow(
                key: const ValueKey('playback-hud-edit'),
                title: i18n('playback_hud_edit'),
                subtitle: i18n('playback_hud_$_editing'),
                onTap: () => unawaited(_pick(context, 'edit', 'playback_hud_edit', const ['clock', 'speed'], _editing)),
              ),
            SettingsRow(
              key: const ValueKey('playback-hud-corner'),
              title: i18n('playback_hud_position'),
              subtitle: i18n('playback_hud_${appearance.corner}'),
              onTap: () => unawaited(
                _pick(context, 'corner', 'playback_hud_position', PlaybackHudConfig.corners.keys, appearance.corner),
              ),
            ),
            SettingsRow(
              key: const ValueKey('playback-hud-font'),
              title: i18n('playback_hud_font'),
              subtitle: i18n('playback_hud_${appearance.font}'),
              onTap: () =>
                  unawaited(_pick(context, 'font', 'playback_hud_font', PlaybackHudConfig.fonts, appearance.font)),
            ),
            SettingsSliderRow(
              key: const ValueKey('playback-hud-size'),
              title: i18n('playback_hud_size'),
              value: _size ?? appearance.size,
              min: 12,
              max: 48,
              divisions: 36,
              label: '${(_size ?? appearance.size).round()}',
              onChanged: (value) => setState(() => _size = value),
              onChangeEnd: (value) => unawaited(
                _appearance(config, {'size': value}).then((_) {
                  if (mounted) setState(() => _size = null);
                }),
              ),
            ),
            DanmakuColorPickerRow(
              settingKey: 'playback-hud-color',
              title: i18n('playback_hud_color'),
              color: Color(appearance.color),
              onChanged: (color) => unawaited(_appearance(config, {'color': color.toARGB32()})),
            ),
            SettingsRow(
              key: const ValueKey('playback-hud-reset'),
              title: i18n('restore_default'),
              onTap: () => unawaited(ref.read(storeProvider).settings.set(Settings.playbackHud, <String, Object?>{})),
            ),
          ],
        ),
      ),
    );
    final tv = UiMode.parse(watchSetting(ref, Settings.uiMode))
        .showsTv(television: ref.watch(televisionDeviceProvider));
    return tv
        ? TvSettingsScaffold(
            title: i18n('playback_hud_title'),
            pageKey: const ValueKey('tv-settings-playback-hud'),
            contentHasHeader: true,
            child: page,
          )
        : page;
  }
}
