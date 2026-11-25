import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/tv/settings/tv_menu_settings_page.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_pages.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';

/// The pages of the phone's overview the TV leaves out: the floating
/// windows' danmaku (there are no floating windows on a TV).
const Set<SettingsSection> tvHiddenSettingsSections = {SettingsSection.pipDanmaku};

/// The TV settings (A17.9 c9): the TV's own rows first (interface mode,
/// growing the focused item, the side menu always open), then the phone's
/// overview — its five groups and their pages in the phone's order, words
/// and icons — and "关于" last. A page opens in its TV look
/// ([TvSettingsSectionPage]); the pages that are a screen of their own (IPTV,
/// recording, backup, the log, …) open that screen, which the TV router
/// draws in the same look.
class TvSettingsCatalog extends ConsumerStatefulWidget {
  /// Creates the catalogue.
  const new({super.key});

  @override
  ConsumerState<TvSettingsCatalog> createState() => _TvSettingsCatalogState();
}

class _TvSettingsCatalogState extends ConsumerState<TvSettingsCatalog> {
  final _scroll = ScrollController();
  final _firstRow = FocusNode(canRequestFocus: false, skipTraversal: true);
  bool _headerPending = false;

  void _revealHeader() {
    if (_headerPending) return;
    _headerPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _headerPending = false;
      if (!mounted || !_firstRow.hasFocus || !_scroll.hasClients || _scroll.offset <= 0) return;
      // Directional traversal reveals the row, but its non-focusable headings
      // live above it. Restore them after that automatic row-only scrolling.
      _scroll.animateTo(0, duration: tvFocusDuration, curve: Curves.easeOutCubic);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _topKey(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _revealHeader();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _firstRow.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(storeProvider).settings;
    final scale = TvScale.of(context);
    return ListView(
      key: const ValueKey('tv-settings-catalog'),
      controller: _scroll,
      padding: EdgeInsets.symmetric(horizontal: scale.px(24), vertical: scale.px(28)),
      children: [
        TvPageHeader(title: i18n('tv_menu_settings')),
        SizedBox(height: scale.px(16)),
        TvSettingsGroup(
          title: i18n('tv_settings_group_tv'),
          children: [
            Focus(
              focusNode: _firstRow,
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _topKey,
              onFocusChange: (focused) {
                if (focused) _revealHeader();
              },
              child: TvChoiceRow<String>(
                id: 'ui_mode',
                icon: TvIcons.uiMode,
                title: i18n('ui_mode'),
                subtitle: i18n('tv_ui_mode_desc'),
                value: watchSetting(ref, Settings.uiMode),
                options: [
                  TvChoice(value: 'auto', label: i18n('ui_mode_auto'), description: i18n('ui_mode_auto_desc')),
                  TvChoice(value: 'phone', label: i18n('ui_mode_phone')),
                  TvChoice(value: 'tv', label: i18n('ui_mode_tv')),
                ],
                onChanged: (value) => settings.set(Settings.uiMode, value),
              ),
            ),
            TvSwitchRow(
              id: 'focus_zoom',
              icon: TvIcons.focusZoom,
              title: i18n('tv_focus_zoom'),
              subtitle: i18n('tv_focus_zoom_desc'),
              value: watchSetting(ref, Settings.tvFocusZoom),
              onChanged: (value) => unawaited(settings.set(Settings.tvFocusZoom, value)),
            ),
            TvLinkRow(
              id: 'wallpaper',
              icon: TvIcons.wallpaperSolid,
              title: i18n('tv_wallpaper'),
              subtitle: i18n('tv_wallpaper_desc'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'tv-settings-wallpaper'),
                  builder: (context) => const TvWallpaperSettingsPage(),
                ),
              ),
            ),
            TvSwitchRow(
              id: 'menu_expanded',
              icon: TvIcons.menuExpand,
              title: i18n('tv_menu_always_expanded'),
              subtitle: i18n('tv_menu_always_expanded_desc'),
              value: watchSetting(ref, Settings.tvMenuAlwaysExpanded),
              onChanged: (value) => unawaited(settings.set(Settings.tvMenuAlwaysExpanded, value)),
            ),
          ],
        ),
        for (final area in SettingsArea.values)
          TvSettingsGroup(
            title: i18n(area.titleKey),
            children: [
              for (final section in SettingsSection.values)
                if (section.area == area && !tvHiddenSettingsSections.contains(section))
                  TvLinkRow(
                    id: 'section-${section.name}',
                    icon: section.icon ?? TvIcons.danmakuOn,
                    title: i18n(section.titleKey),
                    subtitle: i18n(tvSectionDescriptions[section] ?? section.descriptionKey),
                    onTap: () => openTvSettingsSection(context, section),
                  ),
            ],
          ),
        TvSettingsGroup(
          children: [
            TvLinkRow(
              id: 'about',
              icon: AppIcons.about,
              title: i18n('about'),
              subtitle: i18n('tv_settings_about_desc'),
              onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kAbout)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The words under a section whose TV page differs from the phone's: "导航栏"
/// manages the TV's side rail, not the phone's bottom bar.
const Map<SettingsSection, String> tvSectionDescriptions = {SettingsSection.navigation: 'tv_settings_navigation_desc'};

/// Opens [section]: a page of the catalogue in its TV look, or the screen
/// that is the page (its route, or the phone's settings opened on it for
/// the danmaku and the configuration preview, which have pages of their
/// own).
void openTvSettingsSection(BuildContext context, SettingsSection section) {
  if (section.route case final route?) {
    unawaited(AppNavigator.toNamed<void>(route));
    return;
  }
  if (section == SettingsSection.navigation) {
    // The TV's side menu, not the phone's bottom bar (A17.9 c11).
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'tv-settings-navigation'),
        builder: (context) => const TvMenuSettingsPage(),
      ),
    );
    return;
  }
  if (section == SettingsSection.danmaku) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'tv-settings-danmaku'),
        builder: (context) => const TvDanmakuSettingsPage(),
      ),
    );
    return;
  }
  if (section == SettingsSection.configPreview) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'tv-settings-configPreview'),
        builder: (context) => TvSettingsScaffold(
          title: i18n(section.titleKey),
          contentHasHeader: true,
          pageKey: const ValueKey('tv-settings-page-configPreview'),
          child: const ConfigPreviewPage(),
        ),
      ),
    );
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(name: 'tv-settings-${section.name}'),
      builder: (context) => TvSettingsSectionPage(section: section),
    ),
  );
}
