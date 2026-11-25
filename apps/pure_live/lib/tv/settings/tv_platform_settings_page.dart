import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/hot_areas/hot_areas_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/settings/tv_order_editor.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';

/// "平台显示" of the TV (A17.9 c11, N1; A17.9-42～44): the phone's
/// platform display (`hotAreasList`, A09.6) as one page of the TV's
/// show-or-hide-and-move rows; at least one platform stays and the
/// preferred platform follows, as on the phone.
class TvPlatformSettingsPage extends ConsumerWidget {
  /// Creates the page for [route] (the phone's path).
  const new({this.route, super.key});

  /// The path and arguments it was opened with.
  final RouteArgs? route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    final sites = ref.read(sitesProvider);
    final visible = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    final order = [
      ...visible,
      for (final id in sites.ids)
        if (!visible.contains(id)) id,
    ];
    return TvSettingsScaffold(
      pageKey: const ValueKey('tv-settings-page-platforms-display'),
      title: i18n('platform_display'),
      child: TvSettingsColumn(
        children: [
          TvOrderEditor(
            items: [
              for (final id in order)
                TvOrderItem(
                  id: id,
                  label: platformName(id, fallback: sites.maybeOf(id)?.name),
                ),
            ],
            hidden: {
              for (final id in order)
                if (!visible.contains(id)) id,
            },
            lastShownMessage: i18n('at_least_one_platform_required'),
            onChanged: (order, hidden) {
              final shown = [
                for (final id in order)
                  if (!hidden.contains(id)) id,
              ];
              unawaited(() async {
                await settings.set(Settings.hotAreasList, shown);
                final preferred = settings.get(Settings.preferPlatform);
                final next = preferredAfter(shown, preferred);
                if (next != preferred) await settings.set(Settings.preferPlatform, next);
              }());
            },
          ),
        ],
      ),
    );
  }
}
