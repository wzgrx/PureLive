import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';

/// In-memory ownership callbacks for the application's registered archive route.
@immutable
final class HuyaArchiveArguments {
  /// Keeps media ownership local; this object is never serialized or persisted.
  const new({this.room, this.beforePlay, this.onRetire, this.pickOnly = false});

  /// Returns metadata to the existing room without creating a second player.
  final bool pickOnly;

  /// Optional presenter identity already known by the invoking page.
  final LiveRoom? room;

  /// Releases a covered live decoder before opening the selected recording.
  final Future<void> Function()? beforePlay;

  /// Reports actual asynchronous native retirement to the owning page.
  final ValueChanged<Future<void>>? onRetire;
}

/// Uses the route table so individual features do not import each other's pages.
Future<bool> openHuyaArchives(BuildContext context, {LiveRoom? room, Future<void> Function()? beforePlay}) =>
    _openArchives(context, RoutePath.kHuyaArchives, room: room, beforePlay: beforePlay);

/// Opens a platform-aware catalog and awaits both entry and native retirement.
Future<bool> openReplayArchives(BuildContext context, {LiveRoom? room, Future<void> Function()? beforePlay}) =>
    _openArchives(context, RoutePath.kReplayArchives, room: room, beforePlay: beforePlay);

Future<bool> _openArchives(
  BuildContext context,
  String path, {
  LiveRoom? room,
  Future<void> Function()? beforePlay,
}) async {
  if (!context.mounted) return false;
  var entering = Future<void>.value();
  var retirement = Future<void>.value();
  Object? retirementError;
  try {
    await AppNavigator.toNamed<void>(
      path,
      arguments: HuyaArchiveArguments(
        room: room,
        beforePlay: beforePlay == null ? null : () => entering = Future<void>.sync(beforePlay),
        onRetire: (future) {
          retirement = future.then<void>(
            (_) {},
            onError: (Object error, StackTrace _) {
              retirementError = error;
            },
          );
        },
      ),
    );
    // Back may close the catalog while the live decoder is still stopping.
    // Never decide whether to resume until that owning callback has settled.
    await entering;
    await retirement;
    if (retirementError != null) throw StateError('Archive native retirement failed');
    return true;
  } on Object {
    await entering.catchError((Object _) {});
    await retirement.catchError((Object _) {});
    AppNavigator.toast(i18n('replay_open_failed'));
    return false;
  }
}

/// Picks a recording for the invoking live room's existing playback session.
Future<ArchiveSelection?> pickReplayArchive(BuildContext context, LiveRoom? room) =>
    AppNavigator.toNamed<ArchiveSelection>(
      RoutePath.kReplayArchives,
      arguments: HuyaArchiveArguments(room: room, pickOnly: true),
    );
