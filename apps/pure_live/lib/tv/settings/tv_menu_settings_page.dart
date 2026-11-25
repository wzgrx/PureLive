import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/settings/tv_order_editor.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';

/// "导航栏显示控制" of the TV (A17.9 c11, A17.9-37～40): the side menu's
/// entries on one page — OK shows or hides one, a held OK moves it — and
/// "图标" below, which gives an entry another icon (A17.9-31).
class TvMenuSettingsPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    final mode = TvMode.of(watchSetting(ref, Settings.tvMode));
    final order = TvPane.orderOf(watchSetting(ref, Settings.tvMenuOrder), mode: mode);
    final hidden = watchSetting(ref, Settings.tvMenuHidden);
    final icons = watchSetting(ref, Settings.tvMenuIcons);
    return TvSettingsScaffold(
      pageKey: const ValueKey('tv-settings-page-navigation'),
      title: i18n('navigation_display_settings'),
      child: TvSettingsColumn(
        children: [
          TvOrderEditor(
            items: [
              for (final pane in order)
                TvOrderItem(id: pane.name, label: i18n(pane.labelKey), icon: pane.iconIn(icons)),
            ],
            hidden: hidden.toSet(),
            lastShownMessage: i18n('tv_menu_keep_one'),
            onChanged: (order, hidden) {
              unawaited(settings.set(Settings.tvMenuOrder, order));
              unawaited(
                settings.set(Settings.tvMenuHidden, [
                  for (final id in order)
                    if (hidden.contains(id)) id,
                ]),
              );
            },
          ),
          TvSettingsGroup(
            children: [
              TvLinkRow(
                id: 'menu-icons',
                icon: TvIcons.menuShown,
                title: i18n('tv_menu_icons'),
                subtitle: i18n('tv_menu_icons_desc'),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: 'tv-settings-menu-icons'),
                    builder: (context) => const TvMenuIconsPage(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "选择图标" (A17.9-31): each entry of the side menu with its icon; OK
/// offers the icons, the entry's own first.
class TvMenuIconsPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    final icons = watchSetting(ref, Settings.tvMenuIcons);
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    String? chosen(TvPane pane) {
      for (final pair in icons) {
        if (pair.startsWith('${pane.name}:')) return pair.substring(pane.name.length + 1);
      }
      return null;
    }

    Future<void> pick(TvPane pane) async {
      final value = await showTvChoice<String>(
        context,
        title: i18n(pane.labelKey),
        subtitle: i18n('tv_menu_icons'),
        current: chosen(pane) ?? '',
        options: [
          TvChoice(value: '', label: i18n('tv_menu_icon_default'), icon: pane.icon),
          for (final MapEntry(:key, :value) in TvIcons.menuChoices.entries)
            TvChoice(value: key, label: i18n('tv_icon_$key'), icon: value),
        ],
      );
      if (value == null) return;
      await settings.set(Settings.tvMenuIcons, [
        for (final pair in icons)
          if (!pair.startsWith('${pane.name}:')) pair,
        if (value.isNotEmpty) '${pane.name}:$value',
      ]);
    }

    return TvSettingsScaffold(
      pageKey: const ValueKey('tv-settings-page-menu-icons'),
      title: i18n('tv_menu_icons'),
      child: TvSettingsColumn(
        children: [
          TvSettingsGroup(
            children: [
              for (final pane in TvPane.orderOf(
                watchSetting(ref, Settings.tvMenuOrder),
                mode: TvMode.of(watchSetting(ref, Settings.tvMode)),
              ))
                TvSettingsRow(
                  id: 'icon-${pane.name}',
                  icon: pane.iconIn(icons),
                  title: i18n(pane.labelKey),
                  subtitle: chosen(pane) == null ? i18n('tv_menu_icon_default') : null,
                  trailing: (context, focused) =>
                      Icon(TvIcons.chevron, size: scale.pxText(24), color: palette.textSecondary),
                  onTap: () => unawaited(pick(pane)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
