import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// What the area dialog offers.
enum _AreaAction { open, follow, unfollow }

/// The dialog of an area card (A17.3 c7 as changed by the cross-task rule of
/// 2026-10-01: the unified card dialog of A17.1 c9, as the phone's
/// `showAreaDialog`): the area's name over "平台 · 分类", "打开分区" and
/// "关注分区" — or "取消关注", which asks first with the focus on "取消".
Future<void> showTvAreaDialog(BuildContext context, WidgetRef ref, LiveArea area) async {
  final store = ref.read(storeProvider).followAreas;
  final followed = await store.contains(area);
  if (!context.mounted) return;
  final action = await showTvChoice<_AreaAction>(
    context,
    title: areaDisplayName(area),
    subtitle: areaPlatformAndCategory(area),
    options: [
      TvChoice(value: _AreaAction.open, label: i18n('tv_area_open'), icon: TvIcons.menuAreas),
      if (followed)
        TvChoice(value: _AreaAction.unfollow, label: i18n('unfollow'), icon: TvIcons.followArea)
      else
        TvChoice(value: _AreaAction.follow, label: i18n('area_follow'), icon: TvIcons.followedArea),
    ],
  );
  if (action == null || !context.mounted) return;
  final name = areaDisplayName(area);
  try {
    switch (action) {
      case _AreaAction.open:
        openArea(ref, area);
      case _AreaAction.follow:
        await store.add(area);
        AppNavigator.toast(i18n('areas_follow_done', args: {'name': name}));
      case _AreaAction.unfollow:
        final yes = await showTvConfirm(
          context,
          title: i18n('unfollow'),
          message: i18n('tv_area_unfollow_confirm', args: {'name': name}),
          confirmLabel: i18n('unfollow'),
          danger: true,
        );
        if (!yes) return;
        await store.remove(area);
        AppNavigator.toast(i18n('areas_unfollow_done', args: {'name': name}));
    }
  } on Object {
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
  }
}
