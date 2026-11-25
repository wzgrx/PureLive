import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/auth/auth_page.dart';
import 'package:pure_live/features/backup/backup_page.dart';
import 'package:pure_live/features/backup/log_page.dart';
import 'package:pure_live/features/iptv/iptv_page.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/record_settings/record_settings_page.dart';
import 'package:pure_live/features/remote_receiver/playback_remote_page.dart';
import 'package:pure_live/features/remote_receiver/remote_receiver_page.dart';
import 'package:pure_live/features/web_dav/web_dav_page.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// The application composition factory for standalone and embedded settings.
Widget? buildSettingsRoutePage(RouteArgs route, {VoidCallback? onBack}) => switch (route.path) {
  RoutePath.kIptv => IptvPage(route: route, onBack: onBack),
  RoutePath.kRecordSettings => RecordSettingsPage(route: route, onBack: onBack),
  RoutePath.kLocalInteraction => LocalInteractionSettingsPage(route: route, onBack: onBack),
  RoutePath.kBackup => BackupPage(route: route, onBack: onBack),
  RoutePath.kLogs => LogPage(onBack: onBack),
  RoutePath.kMine => AuthPage(route: route),
  RoutePath.kWebDavPage => WebDavPage(route: route),
  RoutePath.kRemoteSync => RemoteReceiverPage(route: route),
  RoutePath.kPlaybackRemote => PlaybackRemotePage(route: route, onBack: onBack),
  _ => null,
};
