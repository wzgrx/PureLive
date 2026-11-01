import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// In-memory ownership callbacks for the application's registered archive route.
@immutable
final class HuyaArchiveArguments {
  /// Keeps media ownership local; this object is never serialized or persisted.
  const new({this.room, this.beforePlay, this.onRetire});

  /// Optional presenter identity already known by the invoking page.
  final LiveRoom? room;

  /// Releases a covered live decoder before opening the selected recording.
  final Future<void> Function()? beforePlay;

  /// Reports actual asynchronous native retirement to the owning page.
  final ValueChanged<Future<void>>? onRetire;
}

/// Uses the route table so individual features do not import each other's pages.
Future<bool> openHuyaArchives(BuildContext context, {LiveRoom? room, Future<void> Function()? beforePlay}) async {
  if (!context.mounted) return true;
  var retirement = Future<void>.value();
  await AppNavigator.toNamed<void>(
    RoutePath.kHuyaArchives,
    arguments: HuyaArchiveArguments(room: room, beforePlay: beforePlay, onRetire: (future) => retirement = future),
  );
  try {
    await retirement;
    return true;
  } on Object {
    AppNavigator.toast(i18n('huya_replay_open_failed'));
    return false;
  }
}
